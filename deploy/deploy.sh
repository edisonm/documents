#!/bin/bash

. `dirname $0`/common.sh

# 2021-05-03 by Edison Mera

# Script to automate deployment of Debian 11 (bullseye) in several scenarios

# Assumptions: this will be used in a VM of 32GB of storage, 8GB RAM, it should
# support UEFI, the root fs will be a btrfs encrypted via LUKS, password-less
# unlock via a key-file which is encrypted via clevis+(tang or tpm2), and
# password input via keyboard as failover.  We can not use dracut since is too
# much hastle, and proxmox is not compatible with it yet.

# Implementation guidelines:

# - Questions are allowed only at the beginning, and once settled, the installer
#   must run in a non-interactive way.

# Machine specific configuration:
USERNAME=edison
FULLNAME="Edison Mera"
DESTNAME=gitlab
# APT Cache Server, leave it empty to disable:
APTCACHER=10.8.0.1

# Specifies if the machine is encrypted:
# ENCRYPT=yes
# TANG Server, leave it empty to disable:
TANGSERV=10.8.0.2
# Use TPM2, if available
if [ -e /dev/tpm0 ]; then
    WITHTPM2=1
else
    WITHTPM2=0
fi
# Extra packages you want to install, leave empty for a small footprint
DEBPACKS="acl binutils build-essential openssh-server"
# DEBPACKS+=" emacs firefox-esr"
# Equivalent to live xfce4 installation + some tools
# DEBPACKS+=" xfce4 task-xfce-desktop"
# DEBPACKS+=" lxde task-lxde-desktop"
# DEBPACKS+=" cinnamon task-cinnamon-desktop"
# DEBPACKS+="acpid alsa-utils anacron fcitx libreoffice"
# Disk layout: dualboot, singboot or wipeout (TBD)
# DISKLAYOUT=dualboot
# DISKLAYOUT=singboot
DISKLAYOUT=wipeout

# Unit where you will install Debian
# DISK=/dev/mmcblk0
# DISK=/dev/nvme0n1
DISK=/dev/vda

ROOTDIR=${ROOTDIR:-/mnt}

LASTCHDSK=${DISK: -1}

if [ "${LASTCHDSK##[0-9]}" == "" ] ; then
    PSEP="p"
else
    PSEP=""
fi

if [ "$DISKLAYOUT" == singboot ] ; then
    PARTUEFI=${DISK}${PSEP}2
    PARTBOOT=${DISK}${PSEP}3
    PARTROOT=${DISK}${PSEP}4
    PARTSWAP=${DISK}${PSEP}5
else # dual boot
    PARTUEFI=${DISK}${PSEP}1
    PARTBOOT=${DISK}${PSEP}4
    PARTROOT=${DISK}${PSEP}5
    PARTSWAP=${DISK}${PSEP}6
fi

export DEBIAN_FRONTEND=noninteractive
ASKPASS_='/lib/cryptsetup/askpass'

if [ "${ENCRYPT}" == yes ] ; then
    ROOTPART=/dev/mapper/crypt_root
    SWAPPART=/dev/mapper/crypt_swap
else
    ROOTPART=${PARTROOT}
    SWAPPART=${PARTSWAP}
fi

warn_confirm () {
    YES_="$($ASKPASS_ "WARNING: This script will destroy all data on your computer, are you sure? (Type uppercase yes):")"

    if [ "$YES_" != "YES" ]; then
        echo "Deployment cancelled"
        exit 1
    fi
}

singboot_partitions () {
    # Partition your disk(s). This scheme works for both BIOS and UEFI, so that
    # we can switch without resizing partitions (which is a headache):
    # BIOS booting:
    sgdisk -a1 -n1:24K:+1000K -t1:EF02 $DISK
    # UEFI booting:
    sgdisk     -n2:1M:+512M   -t2:EF00 $DISK
    # Boot patition:
    sgdisk     -n3:0:+1536M   -t3:8300 $DISK
    # Root partition:
    sgdisk     -n4:0:+26G     -t4:8300 $DISK
    # SWAP partition:
    sgdisk     -n5:0:0        -t5:8300 $DISK
}

build_partitions () {
    if [ "$DISKLAYOUT" == wipeout ] ; then
        # First, wipeout the disk:
        sgdisk -o $DISK
        singboot_partitions
    fi
    if [ "$DISKLAYOUT" == singboot ] ; then
        singboot_partitions
    else
        # Boot patition:
        sgdisk     -n4:0:+1536M   -t3:8300 $DISK
        # Root partition:
        sgdisk     -n5:0:+26G     -t4:8300 $DISK
        # SWAP partition:
        sgdisk     -n6:0:+16G     -t5:8300 $DISK
    fi

    if [ "${ENCRYPT}" == yes ] ; then
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${PARTROOT}
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${PARTSWAP}
        printf "%s" "$KEY_"|cryptsetup luksOpen   --key-file - ${PARTROOT} crypt_root
        printf "%s" "$KEY_"|cryptsetup luksOpen   --key-file - ${PARTSWAP} crypt_swap
    fi

    if [ "$DISKLAYOUT" == wipeout ] ; then
        FORCEEXT4="-F"
        FORCBTRFS="-f"
    fi
    
    mkfs.ext4  ${FORCEEXT4} -L boot ${PARTBOOT}
    mkfs.btrfs ${FORCBTRFS} -L root ${ROOTPART}
    mkswap ${SWAPPART}

    if [ "$DISKLAYOUT" != dualboot ] ; then
        mkdosfs -F 32 -s 1 -n EFI ${PARTUEFI}
    fi
    
    mount ${ROOTPART} ${ROOTDIR}
    btrfs subvolume create ${ROOTDIR}/@
    mkdir ${ROOTDIR}/@/home
    mkdir ${ROOTDIR}/@/boot
    btrfs subvolume create ${ROOTDIR}/@home

    if [ "${ENCRYPT}" == yes ] ; then
        dd if=/dev/urandom bs=2048 count=1 of=${ROOTDIR}/@/crypto_keyfile.bin
        chmod go-rw ${ROOTDIR}/@/crypto_keyfile.bin
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${PARTROOT} ${ROOTDIR}/@/crypto_keyfile.bin --key-file -
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${PARTSWAP} ${ROOTDIR}/@/crypto_keyfile.bin --key-file -
    fi

    umount ${ROOTDIR}
    mount ${PARTBOOT} ${ROOTDIR}
    mkdir ${ROOTDIR}/efi
    umount ${ROOTDIR}
}

setup_aptinstall () {
    echo "deb http://deb.debian.org/debian bullseye main contrib"            > /etc/apt/sources.list
    # echo "deb http://deb.debian.org/debian buster-backports main contrib" >> /etc/apt/sources.list
    apt-get update --yes
    apt-get install --yes debootstrap curl net-tools efibootmgr
}

setup_nic () {
    for nic in `ls /sys/class/net` ; do
        ( echo "auto $nic"
          if [ "$nic" != "lo" ] ; then
              echo "iface $nic inet dhcp"
          else
              echo "iface $nic inet loopback"
          fi
        ) > ${ROOTDIR}/etc/network/interfaces.d/$nic
    done
}

setup_hostname () {
    echo $DESTNAME > ${ROOTDIR}/etc/hostname
    ( echo "127.0.0.1	localhost" ; \
      echo "::1		localhost ip6-localhost ip6-loopback" ; \
      echo "ff02::1		ip6-allnodes" ; \
      echo "ff02::2		ip6-allrouters" ; \
      echo "127.0.1.1	$DESTNAME" ; \
      ) > ${ROOTDIR}/etc/hosts
}

mount_partitions () {
    mount ${ROOTPART} ${ROOTDIR} -o subvol=@
    mount ${ROOTPART} ${ROOTDIR}/home -o subvol=@home
    mount ${PARTBOOT} ${ROOTDIR}/boot
    mount ${PARTUEFI} ${ROOTDIR}/boot/efi
}

unmount_partitions () {
    umount -l ${ROOTDIR}/boot/efi
    umount -l ${ROOTDIR}/boot
    umount -l ${ROOTDIR}/home
    umount -l ${ROOTDIR}
}

config_grubip () {
    if [ "${ENCRYPT}" == yes ] && [ "$TANGSERV" != "" ] ; then
        IP=$(hostname -I|awk '{print $1}')
        GW=$(ip route|awk '/default/{print $3}')
        cp ${ROOTDIR}/etc/default/grub /tmp/
        # in some systems, in /etc/default/grub, a line like this could be required:
        sed -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'"ip=$IP::$GW:$MK"'"/g' /tmp/grub \
            > ${ROOTDIR}/etc/default/grub
    fi
}

config_grub () {
    if [ "$EFI_" == "0" ]; then
        # FOR BIOS:
        apt-get install --yes grub-pc
        grub-install $DISK
    else
        # FOR UEFI:
        apt-get install --yes grub-efi-amd64 shim-signed
	# --bootloader-id=debian
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck --no-floppy
    fi
}

config_fstab () {
    if [ "${ENCRYPT}" == yes ] ; then
        ROOTDEV="${ROOTPART}                   "
        SWAPDEV="${SWAPPART}                   "
    else
        ROOTDEV="UUID=$(blkid -s UUID -o value ${ROOTPART})"
        SWAPDEV="UUID=$(blkid -s UUID -o value ${SWAPPART})"
    fi

    ( echo "UUID=$(blkid -s UUID -o value ${PARTUEFI})                            /boot/efi vfat  defaults,noatime 0 2" ; \
      echo "UUID=$(blkid -s UUID -o value ${PARTBOOT}) /boot     ext4  defaults,noatime 0 2" ; \
      echo "$ROOTDEV /         btrfs     subvol=@,defaults,noatime,compress,space_cache,autodefrag 0 1" ; \
      echo "$ROOTDEV /home     btrfs subvol=@home,defaults,noatime,compress,space_cache,autodefrag 0 2" ; \
      echo "$SWAPDEV none      swap  sw 0 0" ; \
      ) > /etc/fstab
}

config_clevis_tang () {
    cat <<'EOF' | sed -e s:'<TANGSERV>':"$TANGSERV":g \
                      > /etc/initramfs-tools/hooks/clevis_tang
#!/bin/sh

PREREQ="clevis"
prereqs() {
    echo "$PREREQ"
}
case "$1" in
    prereqs)
	prereqs
	exit 0
	;;
esac

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

copy_file script /usr/bin/clevis-decrypt-tang

curl -sfg http://<TANGSERV>/adv -o /tmp/adv.jws
clevis encrypt tang '{"url":"http://<TANGSERV>","adv":"/tmp/adv.jws"}' < /crypto_keyfile.bin > ${DESTDIR}/autounlock.key

EOF
    chmod a+x /etc/initramfs-tools/hooks/clevis_tang
}

config_clevis_tpm2 () {
    cat <<'EOF' > /etc/initramfs-tools/hooks/clevis_tpm2
#!/bin/sh

PREREQ="clevis"
prereqs() {
    echo "$PREREQ"
}
case "$1" in
    prereqs)
	prereqs
	exit 0
	;;
esac

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

copy_file script /usr/bin/clevis-decrypt-tpm2
copy_exec /usr/bin/tpm2_pcrlist
copy_exec /usr/bin/tpm2_createprimary
copy_exec /usr/bin/tpm2_load
copy_exec /usr/bin/tpm2_unseal
copy_exec /usr/bin/tpm2_createpolicy
copy_exec /usr/bin/tpm2_create
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0.0.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-mssim.so.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-mssim.so.0.0.0

# for file in `ls /usr/bin/tpm2_*` ; do
#     copy_exec $file
# done

clevis encrypt tpm2 '{"key":"rsa","pcr_ids":"7"}' < /crypto_keyfile.bin > ${DESTDIR}/autounlock.key

EOF
    chmod a+x /etc/initramfs-tools/hooks/clevis_tpm2
}

config_tpm_tis () {
    # Determine wether the module tpm_tis needs to be added to initramfs-tools modules
    if [ "`lsmod|grep tpm`" != "" ] ; then
        if [ "`cat /etc/initramfs-tools/modules|grep tpm_tis`" == "" ] ; then
            echo "tpm_tis" >> /etc/initramfs-tools/modules
        fi
    fi
}

config_clevis () {
    cat <<'EOF' | sed -e s:'<TANGSERV>':"$TANGSERV":g \
                      > /etc/initramfs-tools/hooks/clevis
#!/bin/sh

PREREQ=""
prereqs() {
    echo "$PREREQ"
}
case "$1" in
    prereqs)
	prereqs
	exit 0
	;;
esac

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

copy_file script /lib/cryptsetup/scripts/decrypt_clevis
copy_file script /usr/bin/clevis
copy_file script /usr/bin/clevis-decrypt
copy_exec /usr/bin/clevis-decrypt-sss
copy_exec /usr/bin/jose
copy_exec /usr/bin/bash
copy_exec /usr/bin/curl

EOF
    chmod a+x /etc/initramfs-tools/hooks/clevis
}

config_decrypt_clevis () {
    # Note: since I didn't manage to encrypt a luks drive via clevis, my next
    # approach is to encrypt the decryption key in the initramfs via clevis, so
    # that it will be safe to keep it in the initrd file.

    cat <<'EOF' | sed -e s:'<KEYSTORE>':"$KEYSTORE":g \
                      -e s:'<HOSTNAME>':"$DESTNAME":g \
                      > /lib/cryptsetup/scripts/decrypt_clevis
#!/bin/sh

ASKPASS_='/lib/cryptsetup/askpass'
PROMPT_="${CRYPTTAB_NAME}'s password: "

if /usr/bin/clevis decrypt < $1 ; then
    exit 0
fi

$ASKPASS_ "$PROMPT_"
EOF
    chmod a+x /lib/cryptsetup/scripts/decrypt_clevis
}

config_clevis_network () {
    cat <<'EOF' > /etc/initramfs-tools/scripts/local-top/network
#!/bin/sh

set -e

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /scripts/functions

configure_networking
EOF
    chmod a+x /etc/initramfs-tools/scripts/local-top/network
}

config_noresume () {
    echo "RESUME=none" > /etc/initramfs-tools/conf.d/noresume.conf
}

config_crypttab () {
    if [ "${ENCRYPT}" == yes ] ; then
        if [ "$TANGSERV" != "" ] || [ "$WITHTPM2" == "1" ] ; then
            UNLOCKFILE="/autounlock.key"
            UNLOCKOPTS=",keyscript=decrypt_clevis"
        else
            UNLOCKFILE="none               "
            UNLOCKOPTS=""
        fi
        if [ -f /etc/crypttab ] ; then
            cp /etc/crypttab /etc/crypttab-
        fi
        ( echo "crypt_root             UUID=$(blkid -s UUID -o value ${PARTROOT}) ${UNLOCKFILE} luks,discard,initramfs${UNLOCKOPTS}" ; \
          echo "crypt_swap             UUID=$(blkid -s UUID -o value ${PARTSWAP}) /crypto_keyfile.bin luks"
        ) > /etc/crypttab
    fi
}

config_encryption () {
    if [ "${ENCRYPT}" == yes ] ; then
        if [ "$TANGSERV" != "" ] || [ "$WITHTPM2" == "1" ] ; then
            config_decrypt_clevis
            config_clevis
            if [ "$TANGSERV" != "" ] ; then
                config_clevis_network
                config_clevis_tang
            fi
            if [ "$WITHTPM2" == "1" ] ; then
                config_clevis_tpm2
                config_tpm_tis
            fi
        fi
        config_noresume
    fi
}

inspkg_encryption () {
    if [ "${ENCRYPT}" == yes ] ; then
        apt-get install --yes cryptsetup
        if [ "$TANGSERV" != "" ] || [ "$WITHTPM2" == "1" ] ; then
            apt-get install --yes clevis
            if [ "$WITHTPM2" == "1" ] ; then
                apt-get install --yes clevis-tpm2
            fi
        fi
    fi
}

do_chroot () {
    config_aptcacher
    config_initpacks
    config_fstab
    config_grub
    inspkg_encryption
    config_encryption
    config_crypttab
    config_suspend
    update-grub
    config_init
    update-initramfs -c -k all
}

config_chroot () {
    cp deploy.sh common.sh ${ROOTDIR}/tmp/
    EFI_=$(efibootmgr -q && echo 1 || echo 0)
    chroot ${ROOTDIR} /tmp/deploy.sh $*
}

wipeout () {
    ROOTDIR=/mnt
    warn_confirm
    config_key
    config_aptcacher
    setup_aptinstall
    build_partitions
    mount_partitions
    unpack_debian
    setup_apt
    config_aptcacher ${ROOTDIR}
    setup_hostname
    setup_nic
    bind_dirs
    config_grubip
    config_chroot do_chroot
    unbind_dirs
    unmount_partitions
}

# vmdesktop () {
    
# }

# vmserver () {
# }

# vmtiny () {
# }

# phdesktop () {
# }

# phserver () {
# }

if [ $# = 0 ] ; then
    wipeout
else
    $*
fi

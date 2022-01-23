#!/bin/bash

set -e

# 2021-05-03 by Edison Mera

# Script to automate deployment of Debian 11 (bullseye)

# Assumptions: this will be used in a VM of 32GB of storage, 8GB RAM, it should
# support UEFI, the root fs will be a btrfs encrypted via LUKS, password-less
# unlock via a key-file which is encrypted via clevis+(tang or tpm2), and
# password input via keyboard as failover.  We can not use dracut since is too
# much hastle, and proxmox is not compatible with it yet.

# Implementation guidelines:

# - All must be contained in just one file, to avoid installers, packs, and
#   complications when sending this file to the target PC.

# - Questions are allowed only at the beginning, and once settled, the installer
#   must run in a non-interactive way.

# Machine specific configuration:
USERNAME=admin
FULLNAME="Administrative Account"
HOSTNAME=pxeclient
# Specifies if the machine is encrypted:
# ENCRYPT=yes
# TANG Server, leave it empty to disable:
#TANGSERV=10.8.0.2
# Use TPM2, if available
if [ -e /dev/tpm0 ]; then
    WITHTPM2=1
else
    WITHTPM2=0
fi
# Extra packages you want to install, leave empty for a small footprint
# Equivalent to live xfce4 installation + some tools
DEBPACKS="acl binutils build-essential openssh-server"
# DEBPACKS+=" emacs firefox-esr"
# DEBPACKS+=" xfce4 task-xfce-desktop"
# DEBPACKS+=" lxde task-lxde-desktop"
# DEBPACKS+=" cinnamon task-cinnamon-desktop"
# DEBPACKS+="acpid alsa-utils anacron fcitx libreoffice"
# APT Cache Server, leave it empty to disable:
APTCACHER=10.8.0.1
# Disk layout: dualboot, singboot or wipeout (TBD)
# DISKLAYOUT=dualboot
DISKLAYOUT=singboot
# Unit where you will install Debian
# DISK=/dev/mmcblk0
# DISK=/dev/nvme0n1
DISK=/dev/vda

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

if [ "$ENCRYPT" == yes ] ; then
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

config_key () {
    echo "The master passphrase is used as failover decryption method and admin user password"
    export KEY_="$($ASKPASS_ "Master passphrase:")"
    CONFIRM_="$($ASKPASS_ "Confirm master passphrase:")"
    if [ "${KEY_}" != "${CONFIRM_}" ] ; then
        echo "ERROR: Confirmation didn't match, aborting"
        exit 1
    fi
}

build_partitions () {
    if [ "$DISKLAYOUT" == singboot ] ; then
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
    else
        # Boot patition:
        sgdisk     -n4:0:+1536M   -t3:8300 $DISK
        # Root partition:
        sgdisk     -n5:0:+26G     -t4:8300 $DISK
        # SWAP partition:
        sgdisk     -n6:0:+16G     -t5:8300 $DISK
    fi

    if [ "$ENCRYPT" == yes ] ; then
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${PARTROOT}
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${PARTSWAP}
        printf "%s" "$KEY_"|cryptsetup luksOpen   --key-file - ${PARTROOT} crypt_root
        printf "%s" "$KEY_"|cryptsetup luksOpen   --key-file - ${PARTSWAP} crypt_swap
    fi
    
    mkfs.ext4  -L boot ${PARTBOOT}
    mkfs.btrfs -L root $ROOTPART
    mkswap $SWAPPART

    if [ "$DISKLAYOUT" != dualboot ] ; then
        mkdosfs -F 32 -s 1 -n EFI ${PARTUEFI}
    fi
    
    mount $ROOTPART /mnt
    btrfs subvolume create /mnt/@
    mkdir /mnt/@/home
    mkdir /mnt/@/boot
    btrfs subvolume create /mnt/@home

    if [ "$ENCRYPT" == yes ] ; then
        dd if=/dev/urandom bs=2048 count=1 of=/mnt/@/crypto_keyfile.bin
        chmod go-rw /mnt/@/crypto_keyfile.bin
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${PARTROOT} /mnt/@/crypto_keyfile.bin --key-file -
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${PARTSWAP} /mnt/@/crypto_keyfile.bin --key-file -
    fi

    umount /mnt
    mount ${PARTBOOT} /mnt
    mkdir /mnt/efi
    umount /mnt
}

setup_aptinstall () {
    echo "deb http://deb.debian.org/debian bullseye main contrib"            > /etc/apt/sources.list
    # echo "deb http://deb.debian.org/debian buster-backports main contrib" >> /etc/apt/sources.list
    apt-get update --yes
    apt-get install --yes debootstrap curl
}

setup_apt () {
    cat <<'EOF' > /mnt/etc/apt/sources.list
deb http://deb.debian.org/debian bullseye main contrib
deb-src http://deb.debian.org/debian bullseye main contrib

deb http://security.debian.org/debian-security bullseye-security main contrib
deb-src http://security.debian.org/debian-security bullseye-security main contrib

deb http://deb.debian.org/debian bullseye-updates main contrib
deb-src http://deb.debian.org/debian bullseye-updates main contrib
EOF
    cat <<'EOF' > /mnt/etc/apt/sources.list.d/bullseye-backport.list
deb http://deb.debian.org/debian bullseye-backports main contrib
deb-src http://deb.debian.org/debian bullseye-backports main contrib
EOF
}

setup_nic () {
    for nic in `ls /sys/class/net` ; do
        ( echo "auto $nic"
          if [ "$nic" != "lo" ] ; then
              echo "iface $nic inet dhcp"
          else
              echo "iface $nic inet loopback"
          fi
        ) > /mnt/etc/network/interfaces.d/$nic
    done
}

setup_hostname () {
    echo $HOSTNAME > /mnt/etc/hostname
    ( echo "127.0.0.1	localhost" ; \
      echo "::1		localhost ip6-localhost ip6-loopback" ; \
      echo "ff02::1		ip6-allnodes" ; \
      echo "ff02::2		ip6-allrouters" ; \
      echo "127.0.1.1	$HOSTNAME" ; \
      ) > /mnt/etc/hosts
}

unpack_debian () {
    debootstrap bullseye /mnt
}

mount_partitions () {
    mount $ROOTPART /mnt -o subvol=@
    mount $ROOTPART /mnt/home -o subvol=@home
    mount ${PARTBOOT} /mnt/boot
    mount ${PARTUEFI} /mnt/boot/efi
}

rbind_systemdirs () {
    mount --rbind /dev  /mnt/dev
    mount --rbind /proc /mnt/proc
    mount --rbind /sys  /mnt/sys
    mount --rbind /run  /mnt/run
    mount --rbind /tmp  /mnt/tmp
}

config_grubip () {
    cp /etc/default/grub /tmp/
    sed -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'"ip=$IP::$GW:$MK"'"/g' /tmp/grub \
        > /etc/default/grub
}

config_grub () {
    # in some systems, in /etc/default/grub, a line like this could be required:
    apt-get install --yes net-tools efibootmgr
    IP=$(hostname -I|awk '{print $1}')
    MK=$(/sbin/ifconfig|awk '/'$IP'/{print $4}')
    GW=$(ip route|awk '/default/{print $3}')
    EFI_=$(efibootmgr -q && echo 1 || echo 0)
    if [ "$EFI_" == "0" ]; then
        apt-get install --yes grub-pc
    else
        apt-get install --yes grub-efi-amd64 shim-signed
    fi

    if [ "$ENCRYPT" == yes ] && [ "$TANGSERV" != "" ] ; then
        config_grubip
    fi
    
    if [ "$EFI_" == "0" ]; then
        # FOR BIOS:
        grub-install $DISK
    else
        # FOR UEFI:
	# --bootloader-id=debian
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck --no-floppy
    fi
}

config_fstab () {
    if [ "$ENCRYPT" == yes ] ; then
        ROOTDEV="$ROOTPART                   "
        SWAPDEV="$SWAPPART                   "
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

config_init () {
    if [ "$(dmidecode -s system-manufacturer)" == "QEMU" ] ; then
        apt-get install --yes qemu-guest-agent
    fi
    # os-prober is needed only on dual-boot systems:
    apt-get remove --yes --purge os-prober
    
    # printf "%s\n%s\n" "$KEY_" "$KEY_" | passwd root
    printf "%s\n%s\n${FULLNAME}\n\n\n\n\nY\n" "$KEY_" "$KEY_" | adduser $USERNAME
    usermod -aG sudo $USERNAME
    apt-get install --yes sudo
    apt-get install --yes btrfs-progs debconf-utils linux-image-`dpkg --print-architecture`
    echo "Installing extra packages"
    apt-get install --yes $DEBPACKS
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
                      -e s:'<HOSTNAME>':"$HOSTNAME":g \
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
    if [ "$ENCRYPT" == yes ] ; then
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
    if [ "$ENCRYPT" == yes ] ; then
        if [ "$TANGSERV" != "" ] || [ "$WITHTPM2" == "1" ] ; then
            config_decrypt_clevis
            config_clevis
            if [ "$TANGSERV" != "" ] ; then
                config_grubip
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
    if [ "$ENCRYPT" == yes ] ; then
        apt-get install --yes cryptsetup
        if [ "$TANGSERV" != "" ] || [ "$WITHTPM2" == "1" ] ; then
            apt-get install --yes clevis
            if [ "$WITHTPM2" == "1" ] ; then
                apt-get install --yes clevis-tpm2
            fi
        fi
    fi
}

config_aptcacher () {
    if [ "$APTCACHER" != "" ] ; then
        echo 'Acquire::http { Proxy "http://'${APTCACHER}':3142"; }' \
             > /etc/apt/apt.conf.d/01proxy
    fi
}

config_initpacks () {
    ln -sf /proc/self/mounts /etc/mtab
    apt-get update --yes
    apt-get dist-upgrade --yes
    ( echo "locales locales/locales_to_be_generated multiselect en_IE.UTF-8 UTF-8, en_US.UTF-8 UTF-8, nl_NL.UTF-8 UTF-8" ; \
      echo "locales	locales/default_environment_locale select en_US.UTF-8" ; \
      echo "tzdata tzdata/Areas        select Europe" ; \
      echo "tzdata tzdata/Zones/Europe select Amsterdam" ; \
      echo "tzdata tzdata/Zones/Etc    select UTC" ; \
      echo "console-setup console-setup/charmap47 select UTF-8" ; \
      echo "keyboard-configuration keyboard-configuration/layoutcode string us" ; \
      echo "keyboard-configuration keyboard-configuration/variant    select English (US)" ; \
      ) | debconf-set-selections -v
    apt-get install --yes locales console-setup
    dpkg-reconfigure locales tzdata keyboard-configuration console-setup -f noninteractive
}

config_suspend () {
    # 95% I have to disable this, even on non-server machines:
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
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

unmount_partitions () {
    umount -l -R /mnt
}

config_chroot () {
    cp $0 /mnt/tmp/
    chroot /mnt /tmp/deploy.sh do_chroot
}

all () {
    warn_confirm
    config_key
    config_aptcacher
    setup_aptinstall
    build_partitions
    mount_partitions
    unpack_debian
    setup_apt
    setup_hostname
    setup_nic
    rbind_systemdirs
    config_chroot
    unmount_partitions
}

if [ $# = 0 ] ; then
    all | tee deploy.out
else
    $*
fi

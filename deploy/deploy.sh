#!/bin/bash

. `dirname $0`/common.sh

# set -x

# 2021-05-03 by Edison Mera

# Script to automate deployment of Debian/Ubuntu in several scenarios

# Assumptions: this will be used in a VM of 32GB of storage, 8GB RAM, it should
# support UEFI, the root fs will be a btrfs encrypted via LUKS, password-less
# unlock via a key-file which is encrypted via clevis+(tang or tpm2), and
# password input via keyboard as failover.  We can not use dracut since is too
# much hastle, and proxmox is not compatible with it yet.

# Implementation guidelines:

# - Questions are allowed only at the beginning, and once settled, the installer
#   must run in a non-interactive way.

# Machine specific configuration:
USERNAME=admin
FULLNAME="Administrative Account"
DESTNAME=debian4
DISTRO=debian
VERSNAME=bullseye
# APT Cache Server, leave it empty to disable:
APTCACHER=10.8.0.1

# Specifies if the machine is encrypted:
ENCRYPT=yes
# TANG Server, leave it empty to disable:
# TANGSERV=10.8.0.2
# Use TPM, if available.  Leave empty for no tpm
TPMVERFILE=/sys/class/tpm/tpm0/tpm_version_major
TPMVERSION=`if [ -f ${TPMVERFILE} ] ; then cat ${TPMVERFILE} ; fi`

# Extra packages you want to install, leave empty for a small footprint
DEBPACKS="acl binutils build-essential openssh-server"
# DEBPACKS+=" emacs firefox-esr"
# Equivalent to live xfce4 installation + some tools
# DEBPACKS+=" xfce4 task-xfce-desktop"
# DEBPACKS+=" lxde task-lxde-desktop"
# DEBPACKS+=" cinnamon task-cinnamon-desktop"
# DEBPACKS+="acpid alsa-utils anacron fcitx libreoffice"

# Disk layout:

# Start at 3, similar to singboot without redefined bios and uefi partitons
# DISKLAYOUT=dualboot

# Start at 4
# DISKLAYOUT=dualboot4

DISKLAYOUT=singboot
# DISKLAYOUT=wipeout
# DISKLAYOUT=raid10

# Unit where you will install Debian, valid for those uni-disk layouts:
# DISK=/dev/mmcblk0
# DISK=/dev/nvme0n1
DISK=/dev/vda
# DISK=/dev/sda
# DISK=/dev/sdb

# Units for raid10:
DISK1=/dev/sda
DISK2=/dev/sdb
DISK3=/dev/sdc
DISK4=/dev/sdd

# UEFI partition size, empty for no uefi partition. Note that if is defined and
# UEFI is not supported, the partition is still created although not used.  If
# the system is UEFI and this is not defined, the system boot will be broken.

# UEFISIZE=+1G

# Boot partition size, empty for no separated boot partition
BOOTSIZE=+2G

# Root partition size, 0 for max available space
ROOTSIZE=0
# ROOTSIZE=+32G

# Swap partition size, placed at the end
SWAPSIZE=-4G

# Enable if you are attempting to continue an incomplete installation
# RESUMING=yes

ROOTDIR=${ROOTDIR:-/mnt}

export DEBIAN_FRONTEND=noninteractive
ASKPASS_='/lib/cryptsetup/askpass'

warn_confirm () {
    if [ "${RESUMING}" == "yes" ] ; then
        MESSAGE="This will attempt to resume a previous installation"
    else
        MESSAGE="This will destroy all data on your computer"
    fi
    YES_="$($ASKPASS_ "WARNING: ${MESSAGE}, are you sure? (Type uppercase yes):")"

    if [ "$YES_" != "YES" ]; then
        echo "Operation cancelled by the user"
        exit 1
    fi
}

skip_if_resuming () {
    if [ "${RESUMING}" != "yes" ] ; then
        $*
    fi
}

exec_once () {
    mkdir -p /var/lib/deploy
    if [ ! -f /var/lib/deploy/$1 ] ; then
        $*
        touch /var/lib/deploy/$1
    fi
}

exec_if_resuming () {
    if [ "${RESUMING}" == "yes" ] ; then
        $*
    fi
}

if_else_resuming () {
    if [ "${RESUMING}" == "yes" ] ; then
        $1
    else
        $2
    fi
}

make_biosuefipar () {
    skip_if_resuming do_make_biosuefipar $*
}

make_biospar () {    
    # BIOS booting:
    sgdisk -a1 -n${SUFFBIOS}:24K:+1000K -t${SUFFBIOS}:EF02 $1
}

make_uefipar () {
    # UEFI booting:
    sgdisk -n${UEFISUFF}:1M:${UEFISIZE} -t${UEFISUFF}:EF00 $1
    mkdosfs -F 32 -s 1 -n EFI ${1}`psep ${1}`${UEFISUFF}
}

do_make_biosuefipar () {
    # Partition your disk(s). This scheme works for both BIOS and UEFI, so that
    # we can switch without resizing partitions (which is a headache):
    make_biospar $*
    if_uefipart make_uefipar $*
}

make_partitions () {
    skip_if_resuming do_make_partitions $*
}

if_bootpart () {
    if [ "${BOOTSIZE}" != "" ] ; then
        $*
    fi
}

skip_if_bootpart () {
    if [ "${BOOTSIZE}" = "" ] ; then
        $*
    fi
}

if_uefipart () {
    if [ "${UEFISIZE}" != "" ] ; then
        $*
    fi
}

do_make_partitions () {
    # Boot patition:
    if_bootpart sgdisk -n${BOOTSUFF}:0:${BOOTSIZE} -t${BOOTSUFF}:8300 $1
    # SWAP partition (at the end):
    sgdisk     -n${SWAPSUFF}:${SWAPSIZE}:0 -t${SWAPSUFF}:8300 $1
    # Root partition:
    sgdisk     -n${ROOTSUFF}:0:${ROOTSIZE} -t${ROOTSUFF}:8300 $1
}

psep () {
    LASTCHDSK=${1: -1}
    if [ "${LASTCHDSK##[0-9]}" == "" ] ; then
        echo "p"
    fi
}

setenv_singdual () {
    PSEP=`psep ${DISK}`
    UEFIPART=${DISK}${PSEP}${UEFISUFF}
    BOOTPART=${DISK}${PSEP}${BOOTSUFF}
    ROOTPDEV=${DISK}${PSEP}${ROOTSUFF}
    SWAPPDEV=${DISK}${PSEP}${SWAPSUFF}
}

setenv_singboot () {
    SUFFBIOS=1
    UEFISUFF=2
    BOOTSUFF=3
    ROOTSUFF=4
    SWAPSUFF=5
    setenv_singdual
}

setenv_wipeout () {
    setenv_singboot
}

setenv_dualboot () {
    UEFISUFF=1
    BOOTSUFF=4
    ROOTSUFF=5
    SWAPSUFF=6
    setenv_singdual
}

setenv_dualboot4 () {
    UEFISUFF=1
    BOOTSUFF=3
    ROOTSUFF=4
    SWAPSUFF=5
    setenv_singdual
}

setenv_raid10 () {
    UEFISUFF=2
    BOOTSUFF=3
    ROOTSUFF=4
    SWAPSUFF=5

    DISKBOOT=/dev/md0
    DISKROOT=/dev/md1
    DISKSWAP=/dev/md2

    SUFFMD=1

    BOOTPART=${DISKBOOT}`psep ${DISKBOOT}`${SUFFMD}
    ROOTPDEV=${DISKROOT}`psep ${DISKROOT}`${SUFFMD}
    SWAPPDEV=${DISKSWAP}`psep ${DISKSWAP}`${SUFFMD}

    # Pick one, later you can sync the other copies
    UEFIPART=${DISK1}${PSEP}${UEFISUFF}

    PSEP1=`psep $DISK1`
    PSEP2=`psep $DISK2`
    PSEP3=`psep $DISK3`
    PSEP4=`psep $DISK4`
    
    BOOTPART1=${DISK1}${PSEP1}${BOOTSUFF}
    BOOTPART2=${DISK2}${PSEP2}${BOOTSUFF}
    BOOTPART3=${DISK3}${PSEP3}${BOOTSUFF}
    BOOTPART4=${DISK4}${PSEP4}${BOOTSUFF}
    
    ROOTPDEV1=${DISK1}${PSEP1}${ROOTSUFF}
    ROOTPDEV2=${DISK2}${PSEP2}${ROOTSUFF}
    ROOTPDEV3=${DISK3}${PSEP3}${ROOTSUFF}
    ROOTPDEV4=${DISK4}${PSEP4}${ROOTSUFF}
    
    SWAPPDEV1=${DISK1}${PSEP1}${SWAPSUFF}
    SWAPPDEV2=${DISK2}${PSEP2}${SWAPSUFF}
    SWAPPDEV3=${DISK3}${PSEP3}${SWAPSUFF}
    SWAPPDEV4=${DISK4}${PSEP4}${SWAPSUFF}
}

setenv_${DISKLAYOUT}

if [ "${ENCRYPT}" == yes ] ; then
    ROOTPART=/dev/mapper/crypt_root
    SWAPPART=/dev/mapper/crypt_swap
else
    ROOTPART=${ROOTPDEV}
    SWAPPART=${SWAPPDEV}
fi

singboot_partitions () {
    make_biosuefipar $DISK
    make_partitions $DISK
}

wipeout_partitions () {
    # First, wipeout the disk:
    skip_if_resuming sgdisk -o $DISK
    singboot_partitions $DISK
}

dualboot_partitions () {
    make_partitions ${DISK}
}

dualboot4_partitions () {
    make_partitions ${DISK}
}

reopen_raid10_partitions () {
    mdadm --stop --scan
    if_bootpart mdadm --assemble ${DISKBOOT} $BOOTPART1 $BOOTPART2 $BOOTPART3 $BOOTPART4
    mdadm --assemble ${DISKROOT} $ROOTPDEV1 $ROOTPDEV2 $ROOTPDEV3 $ROOTPDEV4
    mdadm --assemble ${DISKSWAP} $SWAPPDEV1 $SWAPPDEV2 $SWAPPDEV3 $SWAPPDEV4
}

raid10_partitions () {
    if_else_resuming \
        reopen_raid10_partitions \
        create_raid10_partitions
}

do_zerosb_bootparts () {
    for part in $* ; do
        mdadm --zero-superblock $part || true
    done
}

create_raid10_partitions () {
    mdadm --stop --scan
    sgdisk -o $DISK1
    sgdisk -o $DISK2
    sgdisk -o $DISK3
    sgdisk -o $DISK4

    partprobe

    do_make_biosuefipar $DISK1
    do_make_biosuefipar $DISK2
    do_make_biosuefipar $DISK3
    do_make_biosuefipar $DISK4

    do_make_partitions $DISK1
    do_make_partitions $DISK2
    do_make_partitions $DISK3
    do_make_partitions $DISK4

    mdadm --stop --scan

    if_bootpart do_zerosb_bootparts $BOOTPART1 $BOOTPART2 $BOOTPART3 $BOOTPART4

    do_zerosb_bootparts $ROOTPDEV1 $ROOTPDEV2 $ROOTPDEV3 $ROOTPDEV4 \
                        $SWAPPDEV1 $SWAPPDEV2 $SWAPPDEV3 $SWAPPDEV4
    
    partprobe

    if_bootpart mdadm --create ${DISKBOOT} --level raid1 --metadata=1.0 --raid-devices 4 --force $BOOTPART1 $BOOTPART2 $BOOTPART3 $BOOTPART4
    mdadm --create ${DISKROOT} --level raid10 --raid-devices 4 --force $ROOTPDEV1 $ROOTPDEV2 $ROOTPDEV3 $ROOTPDEV4
    mdadm --create ${DISKSWAP} --level raid0  --raid-devices 4 --force $SWAPPDEV1 $SWAPPDEV2 $SWAPPDEV3 $SWAPPDEV4
    
    sgdisk -n1:0:0 -t1:8300 $DISKBOOT
    sgdisk -n1:0:0 -t1:8300 $DISKROOT
    sgdisk -n1:0:0 -t1:8300 $DISKSWAP
}

open_partitions () {
    if [ "${ENCRYPT}" == yes ] ; then
        if [ "$KEY_" == "" ] ; then
            ask_key
        fi
        printf "%s" "$KEY_"|cryptsetup luksOpen --key-file - ${ROOTPDEV} crypt_root
        printf "%s" "$KEY_"|cryptsetup luksOpen --key-file - ${SWAPPDEV} crypt_swap
    fi
}

close_partitions () {
    if [ "${ENCRYPT}" == yes ] ; then
        cryptsetup luksClose crypt_root
        cryptsetup luksClose crypt_swap
    fi
}

crypt_partitions () {
    if [ "${ENCRYPT}" == yes ] ; then
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${ROOTPDEV}
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${SWAPPDEV}
    fi
}

build_partitions () {

    if [ "$DISKLAYOUT" == wipeout ] || [ "$DISKLAYOUT" == raid10 ] ; then
        FORCEEXT4="-F"
        FORCBTRFS="-f"
    fi

    if_bootpart mkfs.ext4  ${FORCEEXT4} -L boot ${BOOTPART}
    mkfs.btrfs ${FORCBTRFS} -L root ${ROOTPART}
    mkswap ${SWAPPART}

    mount ${ROOTPART} ${ROOTDIR}
    btrfs subvolume create ${ROOTDIR}/@
    mkdir ${ROOTDIR}/@/boot
    mkdir ${ROOTDIR}/@/home
    btrfs subvolume create ${ROOTDIR}/@home

    if [ "${ENCRYPT}" == yes ] ; then
        dd if=/dev/urandom bs=512 count=1 of=${ROOTDIR}/@/crypto_keyfile.bin
        chmod go-rw ${ROOTDIR}/@/crypto_keyfile.bin
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${ROOTPDEV} ${ROOTDIR}/@/crypto_keyfile.bin --key-file -
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${SWAPPDEV} ${ROOTDIR}/@/crypto_keyfile.bin --key-file -
    fi

    if_bootpart mount ${BOOTPART} ${ROOTDIR}/@/boot
    mkdir ${ROOTDIR}/@/boot/efi
    umount ${ROOTDIR}/@/boot
    umount ${ROOTDIR}
}

setup_aptinstall () {
    echo "deb http://deb.debian.org/debian ${VERSNAME} main contrib"         > /etc/apt/sources.list
    # echo "deb http://deb.debian.org/debian ${VERSNAME}-backports main contrib" >> /etc/apt/sources.list
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
    if_bootpart mount ${BOOTPART} ${ROOTDIR}/boot
    if_uefipart mount ${UEFIPART} ${ROOTDIR}/boot/efi
}

unmount_partitions () {
    if_uefipart umount -l ${ROOTDIR}/boot/efi
    if_bootpart umount -l ${ROOTDIR}/boot
    umount -l ${ROOTDIR}/home
    umount -l ${ROOTDIR}
}

config_grubip () {
    IP=$(hostname -I|awk '{print $1}')
    GW=$(ip route|awk '/default/{print $3}'|head -n1)
    cp /etc/default/grub /tmp/
    # in some systems, in /etc/default/grub, a line like this could be required:
    sed -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'"ip=$IP::$GW:$MK"'"/g' /tmp/grub \
        > /etc/default/grub
}

remove_grubip () {
    IP=$(hostname -I|awk '{print $1}')
    GW=$(ip route|awk '/default/{print $3}'|head -n1)
    cp /etc/default/grub /tmp/
    # in some systems, in /etc/default/grub, a line like this could be required:
    sed -e 's/GRUB_CMDLINE_LINUX="'"ip=$IP::$GW:$MK"'"/GRUB_CMDLINE_LINUX=""/g' /tmp/grub \
        > /etc/default/grub
}

config_grubenc () {
    # in some systems, in /etc/default/grub, a line like this could be required:
    if [ "`cat /etc/default/grub|grep GRUB_ENABLE_CRYPTODISK`" = "" ] ; then
        echo "GRUB_ENABLE_CRYPTODISK=y" >>/etc/default/grub
    else
        cp /etc/default/grub /tmp/
        sed -e 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=""/g' /tmp/grub \
            > /etc/default/grub
    fi
}

remove_grubenc () {
    # in some systems, in /etc/default/grub, a line like this could be required:
    cp /etc/default/grub /tmp/
    sed -e 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=""/g' /tmp/grub \
        > /etc/default/grub
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

    ( if_uefipart echo "UUID=$(blkid -s UUID -o value ${UEFIPART})                            /boot/efi vfat  defaults,noatime 0 2" ; \
      if_bootpart echo "UUID=$(blkid -s UUID -o value ${BOOTPART}) /boot     ext4  defaults,noatime 0 2" ; \
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

remove_clevis_tang () {
    rm -f /etc/initramfs-tools/hooks/clevis_tang
}

config_tpm_tools () {
    cat <<'EOF' > /etc/initramfs-tools/hooks/tpm_tools
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

copy_file script /lib/cryptsetup/scripts/decrypt_tpm
copy_exec /usr/bin/tpm_sealdata
copy_exec /usr/bin/tpm_unsealdata
copy_exec /usr/lib/x86_64-linux-gnu/libtpm_unseal.so.1
copy_exec /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1

# copy the daemon + config in the initrd 
copy_exec /usr/sbin/tcsd /sbin 
copy_exec /etc/tcsd.conf /etc 
 
# copy the necessary libraries 
cp -fP /lib/x86_64-linux-gnu/libns* ${DESTDIR}/lib/x86_64-linux-gnu/ 
 
# copy the tpm configuration 
mkdir -p "$DESTDIR/var/lib/tpm" 
cp /var/lib/tpm/* "$DESTDIR/var/lib/tpm/" 

#copy the files to read the NVRAM and to read the secret  
# copy_exec /usr/sbin/tpm_nvread /sbin/
# copy_exec /usr/sbin/tpm_nvinfo /sbin/
# copy_exec /sbin/getsecret.sh /sbin

cp /usr/sbin/tpm_* ${DESTDIR}/sbin

#create etc/passwd
groupid=`id -G tss`
userid=`id -u tss`
echo "root:x:0:0:root:/root:/bin/sh" >  ${DESTDIR}/etc/passwd
echo "tss:x:$userid:$groupid::/var/lib/tpm:/bin/false" >> ${DESTDIR}/etc/passwd

#create etc/hosts
echo "127.0.0.1 localhost\n::1     localhost ip6-localhost ip6-loopback\nff02::1 ip6-allnodes\nff02::2 ip6-allrouters\n" > ${DESTDIR}/etc/hosts

#create etc/group
echo "root:x:0:" > ${DESTDIR}/etc/group
echo "tss:x:$groupid:" >>  ${DESTDIR}/etc/group

/usr/bin/tpm_sealdata -i /crypto_keyfile.bin -o ${DESTDIR}/autounlock.key -z

EOF
    chmod a+x /etc/initramfs-tools/hooks/tpm_tools
}

remove_tpm_tools () {
    rm -f /etc/initramfs-tools/hooks/tpm_tools
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

remove_clevis_tpm2 () {
    rm -f /etc/initramfs-tools/hooks/clevis_tpm2
}

config_tpm_tis () {
    # Determine wether the module tpm_tis needs to be added to initramfs-tools modules
    if [ "`lsmod|grep tpm`" != "" ] ; then
        sed -e s:"# tpm_tis":"tpm_tis":g < /etc/initramfs-tools/modules > /tmp/modules
        if [ "`cat /tmp/modules|grep tpm_tis`" == "" ] ; then
            echo "tpm_tis" > /tmp/modules
        fi
        mv /tmp/modules /etc/initramfs-tools/modules
    fi
}

remove_tpm_tis () {
    sed -e s:"# tpm_tis":"tpm_tis":g < /etc/initramfs-tools/modules > /tmp/modules
    sed -e s:"tpm_tis":"# tpm_tis":g < /tmp/modules > /etc/initramfs-tools/modules
}

config_clevis () {
    cat <<'EOF' > /etc/initramfs-tools/hooks/clevis
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

remove_clevis () {
    rm -f /etc/initramfs-tools/hooks/clevis
}

config_decrypt_clevis () {
    # Note: since I didn't manage to encrypt a luks drive via clevis, my next
    # approach is to encrypt the decryption key in the initramfs via clevis, so
    # that it will be safe to keep it in the initrd file.

    cat <<'EOF' > /lib/cryptsetup/scripts/decrypt_clevis
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

remove_decrypt_clevis () {
    rm -f /lib/cryptsetup/scripts/decrypt_clevis
}

# $ASKPASS_ "raising lo" > /dev/null

config_decrypt_tpm () {
    cat <<'EOF' > /lib/cryptsetup/scripts/decrypt_tpm
#!/bin/sh

ASKPASS_='/lib/cryptsetup/askpass'
PROMPT_="${CRYPTTAB_NAME}'s password: "

chown tss:tss /dev/tpm0
chmod 660 /dev/tpm0

ip address add 127.0.0.1/8 dev lo
ip link set lo up

if [ -f /usr/sbin/tcsd ] ; then
    /usr/sbin/tcsd
fi

if /usr/bin/tpm_unsealdata -i $1 -z ; then
    exit 0
fi

$ASKPASS_ "$PROMPT_"
EOF
    chmod a+x /lib/cryptsetup/scripts/decrypt_tpm
}

remove_decrypt_tpm () {
    rm -f /lib/cryptsetup/scripts/decrypt_tpm
}

config_network () {
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

remove_network () {
    rm -f /etc/initramfs-tools/scripts/local-top/network
}

config_noresume () {
    echo "RESUME=none" > /etc/initramfs-tools/conf.d/noresume.conf
}

config_crypttab () {
    if [ "${ENCRYPT}" == yes ] ; then
        if [ "$TANGSERV" != "" ] || [ "$TPMVERSION" == "2" ] ; then
            UNLOCKFILE="/autounlock.key"
            UNLOCKOPTS=",keyscript=decrypt_clevis"
        elif [ "$TPMVERSION" == "1" ] ; then
            UNLOCKFILE="/autounlock.key"
            UNLOCKOPTS=",keyscript=decrypt_tpm"
        else
            UNLOCKFILE="none               "
            UNLOCKOPTS=""
        fi
        if [ -f /etc/crypttab ] ; then
            cp /etc/crypttab /etc/crypttab-
        fi
        ( echo "crypt_root             UUID=$(blkid -s UUID -o value ${ROOTPDEV}) ${UNLOCKFILE} luks,discard,initramfs${UNLOCKOPTS}" ; \
          echo "crypt_swap             UUID=$(blkid -s UUID -o value ${SWAPPDEV}) /crypto_keyfile.bin luks"
        ) > /etc/crypttab
    fi
}

config_encryption () {
    if [ "${ENCRYPT}" == yes ] ; then
        
        skip_if_bootpart config_grubenc
        
        if [ "$TANGSERV" != "" ] # || [ "$TPMVERSION" == "1" ]
        then
            config_grubip
            config_network
        else
            remove_grubip
            remove_network
        fi
        if [ "$TANGSERV" != "" ] || [ "$TPMVERSION" == "2" ] ; then
            config_decrypt_clevis
            config_clevis
        else
            remove_decrypt_clevis
            remove_clevis
        fi
        if [ "$TANGSERV" != "" ] ; then
            config_clevis_tang
        else
            remove_clevis_tang
        fi
        if [ "$TPMVERSION" == "1" ] || [ "$TPMVERSION" == "2" ] ; then
            config_tpm_tis
        else
            remove_tpm_tis
        fi
        if [ "$TPMVERSION" == "1" ] ; then
            config_decrypt_tpm
            config_tpm_tools
        else
            remove_decrypt_tpm
            remove_tpm_tools
        fi
        if [ "$TPMVERSION" == "2" ] ; then
            config_clevis_tpm2
        else
            remove_clevis_tpm2
        fi
    else
        skip_if_bootpart remove_grubenc
    fi
}

inspkg_encryption () {
    if [ "${ENCRYPT}" == yes ] ; then
        ENCPACKS=cryptsetup
        if [ "$TANGSERV" != "" ] || [ "$TPMVERSION" == "2" ] ; then
            ENCPACKS+=" clevis"
            if [ "$TPMVERSION" == "2" ] ; then
                ENCPACKS+=" clevis-tpm2"
            fi
        fi
        if [ "$TPMVERSION" == "1" ] ; then
            ENCPACKS+=" tpm-tools"
        fi
        apt-get install --yes ${ENCPACKS}
        if [ "$TPMVERSION" == "1" ] ; then
            /usr/sbin/tcsd
            /usr/sbin/tpm_takeownership -y -z \
                || ( echo "WARNING: tpm failure, continuing without TPM, check BIOS settings" ; \
                     TPMVERSION="" )
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
    config_noresume
    config_crypttab
    config_suspend
    update-grub
    config_init
    config_admin
    update-initramfs -c -k all
}

DEPLOYDIR=${ROOTDIR}/home/${USERNAME}/deploy

config_chroot () {
    export EFI_=$(efibootmgr -q > /dev/null 2>&1 && echo 1 || echo 0)
    if [ "`realpath $0`" != "${DEPLOYDIR}/deploy.sh" ] ; then
        mkdir -p ${DEPLOYDIR}
        cp deploy.sh common.sh ${DEPLOYDIR}/
    fi
}

run_chroot () {
    chroot ${ROOTDIR} $*
}

show_settings () {
    echo TPMVERSION=${TPMVERSION}
    echo ENCRYPT=${ENCRYPT}
    echo DISK=${DISK}
    if [ "${BOOTSIZE}" = "" ] && [ "$ENCRYPT" = yes ] ; then
    fi
}

wipeout () {
    ROOTDIR=/mnt
    show_settings
    warn_confirm
    if_else_resuming \
        ask_key \
        set_key
    config_aptcacher
    setup_aptinstall
    ${DISKLAYOUT}_partitions
    skip_if_resuming \
        crypt_partitions
    open_partitions
    skip_if_resuming \
        build_partitions
    mount_partitions
    exec_once unpack_distro
    setup_apt
    setup_hostname
    setup_nic
    bind_dirs
    config_chroot
    run_chroot /home/${USERNAME}/deploy/deploy.sh do_chroot
    unbind_dirs
    unmount_partitions
    close_partitions
}

rescue () {
    RESUMING=yes
    ask_key
    config_aptcacher
    setup_aptinstall
    ${DISKLAYOUT}_partitions
    open_partitions
    mount_partitions
    bind_dirs
    config_chroot
    run_chroot
    unbind_dirs
    unmount_partitions
    close_partitions
}

rescue_live () {
    setup_aptinstall
    rescue
}

if [ $# = 0 ] ; then
    wipeout
else
    $*
fi

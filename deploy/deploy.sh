#!/bin/bash

. `dirname $0`/common.sh

# set -x

# 2021-05-03 by Edison Mera

# Script to automate deployment of Debian/Ubuntu in several scenarios

# Machine specific configuration:
USERNAME=admin
FULLNAME="Administrative Account"
DESTNAME=dedison2

# Distributon.
DISTRO=debian
# DISTRO=ubuntu

# Debian versions
# VERSNAME=bullseye
VERSNAME=bookworm

# Ubuntu versions
# VERSNAME=focal
# VERSNAME=jammy

# Specifies wether you want to install the full proxmox or only the kernel plus
# the boot utils.  Note: you must choose PROXMOX=boot if you want to use zfs.
# Leave it emtpy to skip proxmox installation.

# PROXMOX=
# PROXMOX=full
PROXMOX=boot

# APT Cache Server, leave it empty to disable:
APTCACHER=10.8.0.1
# APTCACHER=192.168.1.6

# Specifies if the machine is encrypted.  In an enterprise environment always
# choose luks, since zfs only encrypts the file content but not the structure.
# For better performance, use zfs.  Note that swap is always encrypted with
# luks.

# WARNING: If you use zfs, it requires that at least one partition be encrypted
# with luks, so that the key is unsealed before the zpool key be loaded, since
# they share the same password file and I didn't try too hard to remove such
# dependency.  In any case, the luks partition can be the swap, which must be
# defined out of the pool.

# ENCRYPT=
ENCRYPT=zfs
# ENCRYPT=luks

# Enable compression
COMPRESSION=yes

# TANG Server, leave it empty to disable:
# TANGSERV=10.8.0.2
# Use TPM, if available.  Leave empty for no tpm
TPMVERFILE=/sys/class/tpm/tpm0/tpm_version_major
TPMVERSION=`if [ -f ${TPMVERFILE} ] ; then cat ${TPMVERFILE} ; fi`

# Use Dropbear SSH to provide the password to decrypt the machine
# UNLOCK_SSH=1

# Copy here the authorized public key to be used to login SSH
AUTH_KEY=id_rsa.pub

# Extra packages you want to install, leave empty for a small footprint
DEBPACKS="acl binutils build-essential openssh-server"
# DEBPACKS+=" emacs firefox-esr gparted mtools"
# Equivalent to live xfce4 installation + some tools
# DEBPACKS+=" xfce4 task-xfce-desktop"
# DEBPACKS+=" lxde task-lxde-desktop"
# DEBPACKS+=" cinnamon task-cinnamon-desktop"
# DEBPACKS+=" acpid alsa-utils anacron fcitx libreoffice"

# Disk layout:
DISKLAYOUT=singboot
# DISKLAYOUT=raid0
# DISKLAYOUT=raid1
# DISKLAYOUT=raid10

# Start at 3, similar to singboot without redefined bios and uefi partitons
# DISKLAYOUT=dualboot

# Start at 4
# DISKLAYOUT=dualboot4

# Specifies if you want to wipe out existing partions, if no then trying to
# overwrite partitions will cause a failure.
WIPEOUT=yes

# UEFI partition size. It is going to be created if the system supports UEFI or
# you are going to use the proxmox boot tool (PROXMOX=boot), otherwise will be
# ignored and a 1k bios_grub partition will be created.
UEFISIZE=+1G

# Boot partition size, empty for no separated boot partition. Compulsory if no
# zfs and the system doesn't support UEFI
# BOOTSIZE=+2G

# boot partition file system to be used
# BOOTFS=ext4
# BOOTFS=btrfs
BOOTFS=zfs

# Root partition size, 0 for max available space, minimum ~20GB
ROOTSIZE=0
# ROOTSIZE=+32G
# ROOTSIZE=+64G

# root partition file system to be used
# BOOTFS=ext4
# ROOTFS=btrfs
ROOTFS=zfs

# Swap partition size, placed at the end, empty for no swap, it is recommended
# to be equal to the available RAM memory
SWAPSIZE=-8G
# SWAPSIZE=-16G

# Unit(s) where you will install Debian
# DISKS=/dev/mmcblk0
# DISKS=/dev/nvme0n1
# DISKS=/dev/vda
DISKS=/dev/sda
# DISKS=/dev/sdb
# Units for raid1/raid0:
# DISKS="/dev/vda /dev/vdb"
# Units for raid10:
# DISKS="/dev/sda /dev/sdb /dev/sdc /dev/sdd"
# DISKS="/dev/vda /dev/vdb /dev/vdc /dev/vdd"

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
    sgdisk -a1 -n${BIOSSUFF}:24K:+1000K -t${BIOSSUFF}:EF02 $1
}

make_uefipar () {
    # UEFI booting:
    sgdisk -n${UEFISUFF}:1M:${UEFISIZE} -t${UEFISUFF}:EF00 $1
    # NOTE: Required even for proxmox, don't oversmart this script ;)
    mkdosfs -F 32 -s 1 -n EFI ${1}`psep ${1}`${UEFISUFF}
}

do_make_biosuefipar () {
    # Partition your disk(s). This scheme works for both BIOS and UEFI, so that
    # we can switch without resizing partitions (which is a headache):
    skip_if_uefi \
        make_biospar $*
    if_uefipar \
        make_uefipar $*
}

make_partitions () {
    skip_if_resuming do_make_partitions $*
}

if_bootpart () {
    if [ "${BOOTSIZE}" != "" ] ; then
        $*
    fi
}

if_swappart () {
    if [ "${SWAPSIZE}" != "" ] ; then
        $*
    fi
}

skip_if_bootpart () {
    if [ "${BOOTSIZE}" = "" ] ; then
        $*
    fi
}

skip_if_proxmox () {
    if [ "${PROXMOX}" == "" ] ; then
        $*
    fi
}

if_proxmox () {
    if [ "${PROXMOX}" != "" ] ; then
        $*
    fi
}

if_else_proxmox () {
    if [ "${PROXMOX}" != "" ] ; then
        $1
    else
        $2
    fi
}

skip_if_bootfs_zfs () {
    if [ "${BOOTFS}" != "zfs" ] ; then
        $*
    fi
}

if_uefipar () {
    if [ -d /sys/firmware/efi ] || [ "${PROXMOX}" != "" ] ; then
        $*
    fi
}

if_uefi () {
    if [ -d /sys/firmware/efi ] ; then
        $*
    fi
}

skip_if_uefi () {
    if [ ! -d /sys/firmware/efi ] ; then
        $*
    fi
}

if_else_uefi () {
    if [ -d /sys/firmware/efi ] ; then
        $1
    else
        $2
    fi
}

do_make_partitions () {
    # Boot patition:
    if_bootpart \
        sgdisk -n${BOOTSUFF}:0:${BOOTSIZE} -t${BOOTSUFF}:8300 $1
    # SWAP partition (at the end):
    if_swappart \
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

if_raid () {
    if [ "${DISKLAYOUT}" == raid1 ] || [ "${DISKLAYOUT}" == raid10 ] ; then
        $*
    fi
}

setenv_commdual () {
    UEFIPARTS=""
    ROOTPDEVS=""
    BOOTPARTS=""
    for DISK in ${DISKS} ; do
        PSEP=`psep $DISK`
        # Pick one, later you can sync the other copies
        UEFIPART="${DISK}${PSEP}${UEFISUFF}"
        ROOTPDEV="${DISK}${PSEP}${ROOTSUFF}"
        UEFIPARTS+=" ${UEFIPART}"
        ROOTPDEVS+=" ${ROOTPDEV}"
        if [ "${BOOTSIZE}" != "" ] ; then
            BOOTPART="${DISK}${PSEP}${BOOTSUFF}"
            BOOTPARTS+=" ${BOOTPART}"
        fi
    done

    if_raid \
        if_bootpart \
        if_boot_ext4 \
        setenv_bootext4

    if_swappart \
        setenv_swap
}

inc_count () {
    COUNT=$((${COUNT}+1))
}

bios_suff () {
    BIOSSUFF=${COUNT}
}

set_bios_suff () {
    skip_if_uefi bios_suff
    skip_if_uefi inc_count
}

uefi_suff () {
    UEFISUFF=${COUNT}
}

set_uefi_suff () {
    if_uefipar uefi_suff
    if_uefipar inc_count
}

boot_suff () {
    BOOTSUFF=${COUNT}
}

set_boot_suff () {
    if_bootpart boot_suff
    if_bootpart inc_count
}

root_suff () {
    ROOTSUFF=${COUNT}
}

set_root_suff () {
    root_suff
    inc_count
}

swap_suff () {
    SWAPSUFF=${COUNT}
}

set_swap_suff () {
    if_swappart swap_suff
    if_swappart inc_count
}

setenv_dualboot () {
    COUNT=1
    set_uefi_suff
    inc_count
    inc_count
    set_boot_suff
    set_root_suff
    set_swap_suff
    setenv_commdual
}

setenv_dualboot4 () {
    COUNT=1
    set_uefi_suff
    inc_count
    set_boot_suff
    set_root_suff
    set_swap_suff
    setenv_commdual
}

if_boot_ext4 () {
    if [ "${BOOTFS}" = ext4 ] ; then
        $*
    fi
}

if_boot_btrfs () {
    if [ "${BOOTFS}" = btrfs ] ; then
        $*
    fi
}

setenv_bootext4 () {
    BOOTDISK=/dev/md0
    SUFFMD=1
    BOOTPART=${BOOTDISK}`psep ${BOOTDISK}`${SUFFMD}
    BOOTPARTS=${BOOTPART}
}

setenv_swap () {
    SWAPPDEVS=""
    for DISK in ${DISKS} ; do
        SWAPPDEVS+=" ${DISK}`psep ${DISK}`${SWAPSUFF}"
    done
}

setenv_common () {
    COUNT=1
    set_bios_suff
    set_uefi_suff
    set_boot_suff
    set_root_suff
    set_swap_suff
    setenv_commdual
}

setenv_singboot () {
    setenv_common
}

setenv_raid0 () {
    setenv_common
}

setenv_raid1 () {
    setenv_common
}

setenv_raid10 () {
    setenv_common
}

setenv_${DISKLAYOUT}

forall_rootpdevs () {
    IDX=" "
    for PDEV in ${ROOTPDEVS} ; do
        $*
        IDX=$((${IDX}+1))
    done
}

forall_swappdevs () {
    IDX=" "
    for PDEV in ${SWAPPDEVS} ; do
        $*
        IDX=$((${IDX}+1))
    done
}

collect_rootpart () {
    ROOTPARTS+=" /dev/mapper/crypt_root${IDX}"
}

collect_swappart () {
    SWAPPARTS+=" /dev/mapper/crypt_swap${IDX}"
}

if_encrypt () {
    if [ "${ENCRYPT}" != "" ] ; then
        $*
    fi
}

if_encrypt_luks () {
    if [ "${ENCRYPT}" == luks ] ; then
        $*
    fi
}

if_encrypt_zfs () {
    if [ "${ENCRYPT}" == zfs ] ; then
        $*
    fi
}

if_else_encrypt () {
    if [ "${ENCRYPT}" != "" ] ; then
        $1
    else
        $2
    fi
}

if_else_encrypt_luks () {
    if [ "${ENCRYPT}" == luks ] ; then
        $1
    else
        $2
    fi
}

root_parts_crypt () {
    ROOTPARTS=
    forall_rootpdevs collect_rootpart
}

root_parts () {
    ROOTPARTS=${ROOTPDEVS}
}

swap_parts_crypt () {
    SWAPPARTS=
    forall_swappdevs collect_swappart
}

swap_part () {
    SWAPPARTS=${SWAPPDEVS}
}

if_else_encrypt_luks \
    root_parts_crypt \
    root_parts

if_else_encrypt \
    swap_parts_crypt \
    swap_parts

first () {
    echo $1
}

num_args () {
    echo $#
}

ROOTPART="`first ${ROOTPARTS}`"

create_partitions_singboot () {
    create_partitions_common
}

create_partitions_dualboot () {
    for DISK in ${DISKS} ; do
        make_partitions ${DISK}
    done
}

create_partitions_dualboot4 () {
    for DISK in ${DISKS} ; do
        make_partitions ${DISK}
    done
}

reopen_partitions_raid () {
    mdadm --stop --scan
    sleep 1
    mdadm --assemble ${BOOTDISK} ${BOOTPARTS}
}

reopen_partitions () {
    if_raid \
        if_bootpart \
        if_boot_ext4 \
        reopen_partitions_raid
}

num_elems () {
    NUM_ELEMS=0
    for DISK in ${DISKS} ; do
        NUM_ELEMS=$((${NUM_ELEMS}+1))
    done
}

do_bootparts () {
    LEVEL=$1
    shift
    NDEVS=`num_elems ${DISKS}`
    mdadm --stop --scan
    for part in $* ; do
        mdadm --zero-superblock $part || true
    done
    partprobe
    sleep 1
    mdadm --create ${BOOTDISK} --level ${LEVEL} --metadata=1.0 --raid-devices ${NDEVS} --force $*
    sgdisk -n1:0:0 -t1:8300 ${BOOTDISK}
}

create_partitions_common () {
    if [ "${WIPEOUT}" == yes ] ; then
        # First, wipeout the disks:
        for DISK in ${DISKS} ; do
            skip_if_resuming sgdisk -o $DISK
        done
    fi

    partprobe
    sleep 1
    for DISK in ${DISKS} ; do
        make_biosuefipar $DISK
        make_partitions $DISK
    done
}

create_partitions_raid () {
    if_bootpart \
        if_boot_ext4 \
        mdadm --stop --scan

    create_partitions_common
    if_bootpart \
        if_boot_ext4 \
        do_bootparts ${DISKLAYOUT} ${BOOTPARTS}
}

create_partitions_raid1 () {
    create_partitions_raid
}

create_partitions_raid0 () {
    create_partitions_raid
}

create_partitions_raid10 () {
    create_partitions_raid
}

open_rootpart () {
    printf "%s" "$KEY_"|cryptsetup luksOpen --key-file - ${PDEV} crypt_root${IDX}
}

open_swappart () {
    printf "%s" "$KEY_"|cryptsetup luksOpen --key-file - ${PDEV} crypt_swap${IDX}
}

open_partitions () {
    if [ "$KEY_" == "" ] ; then
        ask_key
    fi
    if_encrypt_luks \
        forall_rootpdevs open_rootpart
    if_encrypt \
        forall_swappdevs open_swappart
}

close_rootpart () {
    cryptsetup luksClose crypt_root${IDX}
}

close_swappart () {
    cryptsetup luksClose crypt_swap${IDX}
}

close_partitions () {
    if_encrypt_luks \
        forall_rootpdevs \
        close_rootpart
    forall_swappdevs \
        close_swappart
}

crypt_partitions () {
    for PDEV in $* ; do
        printf "%s" "$KEY_"|cryptsetup luksFormat --key-file - ${PDEV}
    done
}

build_bootpart_btrfs () {
    mkfs.btrfs ${FORCBTRFS} -L boot ${MKFSBTRFS} ${BOOTPARTS}
    mount_bpartitions_btrfs
}

build_bootpart_ext4 () {
    mkfs.ext4 ${FORCEEXT4} -L boot ${BOOTPARTS}
    mount_bpartitions_ext4
}

zfs_layout () {
    if [ "${DISKLAYOUT}" == raid1 ] ; then
        echo mirror $*
    elif [ "${DISKLAYOUT}" == raid10 ] ; then
        zfs_raid10_layout $*
    else
        echo $*
    fi
}

zfs_raid10_layout () {
    N=0
    for ELEM in $* ; do
        if [ "$((${N}%2))" == 0 ] ; then
            echo mirror
        fi
        echo ${ELEM}
        N=$((${N}+1))
    done
}

if [ "$WIPEOUT" == yes ] ; then
    FORCEEXT4="-F"
    FORCEZFS="-f"
    FORCBTRFS="-f"
fi

if [ "${COMPRESSION}" == yes ] ; then
    COMPZFS="-O compression=on"
    COMPBTRFS="compress,"
fi

build_bootpart_zfs () {
    if [ "${VERSNAME}" == bullseye ] ; then
        ZFSOPTS="\
        -o feature@async_destroy=enabled \
        -o feature@bookmarks=enabled \
        -o feature@embedded_data=enabled \
        -o feature@empty_bpobj=enabled \
        -o feature@enabled_txg=enabled \
        -o feature@extensible_dataset=enabled \
        -o feature@filesystem_limits=enabled \
        -o feature@hole_birth=enabled \
        -o feature@large_blocks=enabled \
        -o feature@livelist=enabled \
        -o feature@lz4_compress=enabled \
        -o feature@spacemap_histogram=enabled \
        -o feature@zpool_checkpoint=enabled"
    else
        ZFSOPTS="-o compatibility=grub2"
    fi
    zpool create ${FORCEZFS} \
          -o ashift=12 \
          -o autotrim=on \
          -o cachefile=/etc/zfs/zpool.cache \
          ${ZFSOPTS} \
          -O devices=off \
          -O acltype=posixacl -O xattr=sa \
          ${COMPZFS} \
          -O normalization=formD \
          -O relatime=on \
          -O canmount=off -O mountpoint=none -R ${ROOTDIR} \
          bpool `zfs_layout ${BOOTPARTS}`
    zfs create -o canmount=on -o mountpoint=/boot bpool/BOOT
}

build_rootpart_btrfs () {
    mkfs.btrfs ${FORCBTRFS} -L root ${MKFSBTRFS} ${ROOTPARTS}

    mount ${ROOTPART} ${ROOTDIR}
    btrfs subvolume create ${ROOTDIR}/@
    mkdir -p ${ROOTDIR}/@/boot
    mkdir -p ${ROOTDIR}/@/home
    btrfs subvolume create ${ROOTDIR}/@home
    umount -l ${ROOTDIR}
    mount_rpartitions_btrfs
}

build_rootpart_ext4 () {
    mkfs.ext4 ${FORCEEXT4} -L root ${ROOTPART}
    mount_rpartitions_ext4
}

config_encryption_zfs () {
    zfs change-key -o keyformat=passphrase -o keylocation=file:///crypto_keyfile.bin rpool
}

set_encrypt_zfs () {
    ENCRZFS="-O encryption=on -O keyformat=passphrase -O keylocation=prompt"
}

load_key_zfs () {
    printf "%s" "$KEY_" | zfs load-key -L prompt -a
}

build_rootpart_zfs () {
    if_encrypt_zfs \
        set_encrypt_zfs
    
    printf "%s" "$KEY_" | \
        zpool create ${FORCEZFS} \
              -o ashift=12 \
              -o autotrim=on \
              -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
              ${COMPZFS} \
              ${ENCRZFS} \
              -O normalization=formD \
              -O relatime=on \
              -O canmount=off -O mountpoint=none -R ${ROOTDIR} \
              rpool `zfs_layout ${ROOTPARTS}`

    zfs create -o canmount=on  -o mountpoint=/    rpool/ROOT
    zfs create                                    rpool/ROOT/home
    zfs create -o canmount=off                    rpool/ROOT/usr
    zfs create                                    rpool/ROOT/usr/local
    zfs create -o canmount=off                    rpool/ROOT/var
    zfs create                                    rpool/ROOT/var/lib
    zfs create                                    rpool/ROOT/var/lib/apt
    zfs create                                    rpool/ROOT/var/lib/dpkg
    zfs create                                    rpool/ROOT/var/lib/AccountsService
    zfs create                                    rpool/ROOT/var/lib/NetworkManager
    zfs create                                    rpool/ROOT/var/log
    zfs create                                    rpool/ROOT/var/spool
    if [ "${DISTRO}" == ubuntu ] ; then
        zfs create                                rpool/ROOT/var/snap
    fi
    skip_if_bootpart zfs create                   rpool/ROOT/boot
}

set_btrfs_opts () {
    MKFSBTRFS="-m ${DISKLAYOUT} -d ${DISKLAYOUT}"
}

build_partitions () {

    if_raid set_btrfs_opts
    
    build_rootpart_${ROOTFS}

    if_bootpart \
        build_bootpart_${BOOTFS}

    mount_epartitions

    for SWAPPART in ${SWAPPARTS} ; do
        mkswap ${SWAPPART}
    done
}

create_keyfile_luks () {
    dd if=/dev/urandom bs=512 count=1 of=${ROOTDIR}/crypto_keyfile.bin
    chmod go-rw ${ROOTDIR}/crypto_keyfile.bin
}

create_keyfile_zfs () {
    # since zfs doesn`t support multiple keys, we reuse the password to create the
    # decryption file
    printf "%s" "$KEY_" > ${ROOTDIR}/crypto_keyfile.bin
    chmod go-rw ${ROOTDIR}/crypto_keyfile.bin
}

encrypt_partitions () {
    for PDEV in $* ; do
        printf "%s" "$KEY_"|cryptsetup luksAddKey ${PDEV} ${ROOTDIR}/crypto_keyfile.bin --key-file -
    done
}

setup_aptinstall () {
    setup_nonfree
    if [ "${DISTRO}" != ubuntu ] ; then
        rm -f /etc/apt/sources.list.d/ceph.list
        cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                          -e s:'<NONFREE>':"${NONFREE}":g \
                          > /etc/apt/sources.list
deb http://deb.debian.org/debian/ <VERSNAME> main contrib <NONFREE>
deb-src http://deb.debian.org/debian/ <VERSNAME> main contrib <NONFREE>
# deb [trusted=yes] file:/run/live/medium bookwork main <NONFREE>
EOF
    fi
    # echo "deb http://deb.debian.org/debian ${VERSNAME}-backports main contrib" >> /etc/apt/sources.list
    apt-get update --yes
    INSPACKS="debootstrap curl net-tools efibootmgr"
    if [ "${ROOTFS}" == zfs ] ; then
        INSPACKS+=" zfsutils-linux"
    fi
    apt-get install --yes ${INSPACKS}
}

config_nic () {
    mkdir -p /etc/network/interfaces.d
    for nic in `ls /sys/class/net` ; do
        ( echo "auto $nic"
          if [ "$nic" != "lo" ] ; then
              echo "iface $nic inet dhcp"
          else
              echo "iface $nic inet loopback"
          fi
        ) > /etc/network/interfaces.d/$nic
    done
}

config_hostname () {
    echo $DESTNAME > /etc/hostname
    ( echo "127.0.0.1	localhost" ; \
      echo "::1		localhost ip6-localhost ip6-loopback" ; \
      echo "ff02::1		ip6-allnodes" ; \
      echo "ff02::2		ip6-allrouters" ; \
      echo "127.0.1.1	$DESTNAME" ; \
      ) > /etc/hosts
}

mount_uefi () {
    mkdir -p ${ROOTDIR}/boot/efi
    mount ${UEFIPART} ${ROOTDIR}/boot/efi
}

mount_bpartitions () {
    mkdir -p ${ROOTDIR}/boot
    mount ${BOOTPART} ${ROOTDIR}/boot
}

mount_epartitions () {
    if_uefi \
        skip_if_proxmox \
        mount_uefi
}

mount_bpartitions_btrfs () {
    mount_bpartitions
}

mount_bpartitions_ext4 () {
    mount_bpartitions
}

mount_bpartitions_zfs () {
    zpool import bpool -f -R ${ROOTDIR}
}

mount_rpartitions_btrfs () {
    mount ${ROOTPART} ${ROOTDIR} -o subvol=@
    mount ${ROOTPART} ${ROOTDIR}/home -o subvol=@home
}

mount_rpartitions_ext4 () {
    mount ${ROOTPART} ${ROOTDIR}
}

mount_rpartitions_zfs () {
    zpool import rpool -f -R ${ROOTDIR}
    if_encrypt_zfs \
        load_key_zfs
    zfs mount -a
}

unmount_bpartitions () {
    umount -l ${ROOTDIR}/boot
}

unmount_epartitions () {
    if_uefi \
        skip_if_proxmox \
        umount -l ${ROOTDIR}/boot/efi
}

unmount_bpartitions_btrfs () {
    unmount_bpartitions
}

unmount_bpartitions_ext4 () {
    unmount_bpartitions
}

unmount_bpartitions_zfs () {
    zpool export bpool
}

unmount_rpartitions_btrfs () {
    umount -l ${ROOTDIR}/home
    umount -l ${ROOTDIR}
}

unmount_rpartitions_ext4 () {
    umount -l ${ROOTDIR}
}

unmount_rpartitions_zfs () {
    zpool export rpool
}

mount_partitions () {
    mount_rpartitions_${ROOTFS}
    if_bootpart \
        mount_bpartitions_${BOOTFS}
    mount_epartitions
}

unmount_partitions () {
    unmount_epartitions
    if_bootpart \
        unmount_bpartitions_${BOOTFS}
    unmount_rpartitions_${ROOTFS}
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

config_boot_efi () {
    # FOR UEFI:
    apt-get install --yes grub-efi-amd64 shim-signed
    # --bootloader-id=debian
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck --no-floppy
    apt-get --yes autoremove
}

config_boot () {
    if [ "$EFI_" == "0" ]; then
        # FOR BIOS:
        apt-get install --yes grub-pc
        grub-install $DISK
    else
        skip_if_proxmox \
            config_boot_efi
    fi
}

set_fsroot_dev_crypt () {
    ROOTDEV="${ROOTPART}                  "
}

set_fsroot_dev () {
    ROOTDEV="UUID=$(blkid -s UUID -o value ${ROOTPART})"
}

set_fsswap_dev_crypt () {
    SWAPDEV="${SWAPPART}                   "
}
set_fsswap_dev () {
    SWAPDEV="UUID=$(blkid -s UUID -o value ${SWAPPART})"
}

dump_fstab () {
    if_uefi \
        skip_if_proxmox \
        echo "UUID=$(blkid -s UUID -o value ${UEFIPART}) /boot/efi vfat  defaults,noatime 0 2"
    
    if_bootpart \
        skip_if_bootfs_zfs \
        echo "UUID=$(blkid -s UUID -o value ${BOOTPART}) /boot     ${BOOTFS}  defaults,noatime 0 2"

    if_else_encrypt_luks \
        set_fsroot_dev_crypt \
        set_fsroot_dev

    if [ ${ROOTFS} == "btrfs" ] ; then
        echo "$ROOTDEV /         btrfs     subvol=@,defaults,noatime,${COMPBTRFS}space_cache=v2,autodefrag 0 1"
        echo "$ROOTDEV /home     btrfs subvol=@home,defaults,noatime,${COMPBTRFS}space_cache=v2,autodefrag 0 2"
    elif  [ ${ROOTFS} == "ext4" ] ; then
        echo "$ROOTDEV /         ext4     defaults,noatime 0 1"
    fi

    for SWAPPART in ${SWAPPARTS} ; do
        if_else_encrypt \
            set_fsswap_dev_crypt \
            set_fsswap_dev
        echo "$SWAPDEV none      swap  sw,pri=1 0 0"
    done
}

config_fstab () {
    dump_fstab > /etc/fstab
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
( clevis encrypt tang '{"url":"http://<TANGSERV>","adv":"/tmp/adv.jws"}' < /crypto_keyfile.bin > ${DESTDIR}/autounlock.key ) || rm -f ${DESTDIR}/autounlock.key

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

( /usr/bin/tpm_sealdata -i /crypto_keyfile.bin -o ${DESTDIR}/autounlock.key -z ) ||  || rm -f ${DESTDIR}/autounlock.key

EOF
    chmod a+x /etc/initramfs-tools/hooks/tpm_tools
}

remove_tpm_tools () {
    rm -f /etc/initramfs-tools/hooks/tpm_tools
}

config_clevis_tpm2 () {
    cat <<'EOF' | sed -e s:'<PCR_BANK>':"$PCR_BANK":g \
	> /etc/initramfs-tools/hooks/clevis_tpm2
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
copy_exec /usr/bin/tpm2_pcrread
copy_exec /usr/bin/tpm2_createprimary
copy_exec /usr/bin/tpm2_load
copy_exec /usr/bin/tpm2_unseal
copy_exec /usr/bin/tpm2_createpolicy
copy_exec /usr/bin/tpm2_create
copy_exec /usr/bin/tpm2_flushcontext
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0.0.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-mssim.so.0
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-mssim.so.0.0.0

# for file in `ls /usr/bin/tpm2_*` ; do
#     copy_exec $file
# done

( clevis encrypt tpm2 '{"key":"rsa","pcr_bank":"<PCR_BANK>","pcr_ids":"7"}' < /crypto_keyfile.bin > ${DESTDIR}/autounlock.key ) || rm -f ${DESTDIR}/autounlock.key

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

decrypt_clevis () {
    ASKPASS_='/lib/cryptsetup/askpass'
    PROMPT_="${CRYPTTAB_NAME}'s password: "

    if test -f $1 && /usr/bin/clevis decrypt < $1 ; then
        exit 0
    fi

    $ASKPASS_ "$PROMPT_"
}

decrypt_clevis $1 | tee /crypto_keyfile.bin

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

if test -f $1 && /usr/bin/tpm_unsealdata -i $1 -z ; then
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

dump_root_entry () {
    echo "crypt_root${IDX}            UUID=$(blkid -s UUID -o value ${PDEV}) ${UNLOCKFILE} luks,discard${UNLOCKOPTS}"
}

# dump_swap_entry () {
#     echo "crypt_swap${IDX}            UUID=$(blkid -s UUID -o value ${PDEV}) /crypto_keyfile.bin luks"
# }

dump_swap_entry () {
    echo "crypt_swap${IDX}            UUID=$(blkid -s UUID -o value ${PDEV}) ${UNLOCKFILE} luks,discard${UNLOCKOPTS}"
}

dump_crypttab () {
    if [ "$TANGSERV" != "" ] || [ "$TPMVERSION" == "2" ] ; then
        UNLOCKFILE="/autounlock.key"
        UNLOCKOPTS=",initramfs,keyscript=decrypt_clevis"
    elif [ "$TPMVERSION" == "1" ] ; then
        UNLOCKFILE="/autounlock.key"
        UNLOCKOPTS=",initramfs,keyscript=decrypt_tpm"
    elif [ "${UNLOCK_SSH}" == "1" ] ; then
        UNLOCKFILE="none               "
        UNLOCKOPTS=",initramfs"
    elif [ "`num_args ${ROOTPDEVS}`" != 1 ] ; then
        UNLOCKFILE="root               "
        UNLOCKOPTS=",initramfs,keyscript=decrypt_keyctl"
    else
        UNLOCKFILE="none               "
        UNLOCKOPTS=",initramfs"
    fi
    if_encrypt_luks \
        forall_rootpdevs \
        dump_root_entry
    forall_swappdevs \
        dump_swap_entry
}

config_crypttab () {
    if [ -f /etc/crypttab ] ; then
        cp /etc/crypttab /etc/crypttab-
    fi
    dump_crypttab > /etc/crypttab
}

config_encryption () {
    skip_if_bootpart \
        skip_if_proxmox \
        config_grubenc
    
    if [ "$TANGSERV" != "" ] # || [ "$TPMVERSION" == "1" ]
    then
        skip_if_proxmox \
            config_grubip
        config_network
    else
        skip_if_proxmox \
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
}

remove_encryption () {
    skip_if_bootpart \
        skip_if_proxmox \
        remove_grubenc
}

warn_tpm_failure () {
    echo "WARNING: tpm failure, continuing without TPM, try './deploy.sh fix_tpm' after reboot" 1>&2
}

recheck_tpm1 () {
    /usr/sbin/tcsd
    /usr/sbin/tpm_takeownership -y -z > /dev/null \
        && echo 1 || warn_tpm_failure
}

recheck_tpm2 () {
    echo | clevis encrypt tpm2 '{"key":"rsa","pcr_bank":"'${PCR_BANK}'","pcr_ids":"7"}' > /dev/null \
        && echo 2 || warn_tpm_failure
}

get_pcr_bank () {
    if [ "`/usr/bin/tpm2_pcrread sha256:7|grep '7 : '`" == "" ] ; then
	echo sha1
    else
	echo sha256
    fi
}

inspkg_encryption () {
    ENCPACKS="cryptsetup cryptsetup-initramfs"
    if [ "$TANGSERV" != "" ] || [ "$TPMVERSION" == "2" ] ; then
        ENCPACKS+=" clevis"
        if [ "$TPMVERSION" == "2" ] ; then
            ENCPACKS+=" clevis-tpm2"
        fi
    fi
    if [ "$TPMVERSION" == "1" ] ; then
        ENCPACKS+=" tpm-tools"
    fi
    apt-get install --yes ${ENCPACKS} || true
}

config_pcr_bank () {
    if [ "$TPMVERSION" == "2" ] ; then
        PCR_BANK=`get_pcr_bank`
    fi
}

recheck_tpmversion () {
    if [ "$TPMVERSION" == "1" ] ; then
        TPMVERSION=`recheck_tpm1`
    fi
    if [ "$TPMVERSION" == "2" ] ; then
        # tpm2_clear will remove all TPM keys, but it will make it work --EMM
        tpm2_clear
        TPMVERSION=`recheck_tpm2`
    fi
}

DEPLOYDIR=${ROOTDIR}/home/${USERNAME}/deploy

config_chroot () {
    export EFI_=$(efibootmgr -q > /dev/null 2>&1 && echo 1 || echo 0)
    if [ "`realpath $0`" != "${DEPLOYDIR}/deploy.sh" ] ; then
        mkdir -p ${DEPLOYDIR}
        if [ -f "${AUTH_KEY}" ] ; then
            cp "${AUTH_KEY}" ${DEPLOYDIR}/
        fi
        cp deploy.sh common.sh ${DEPLOYDIR}/
    fi
}

run_chroot () {
    chroot ${ROOTDIR} $*
}

show_settings () {
    echo TPMVERSION=${TPMVERSION}
    echo ENCRYPT=${ENCRYPT}
    echo DISKS=${DISKS}
    echo BIOSSUFF=${BIOSSUFF}
    echo UEFISUFF=${UEFISUFF}
    echo BOOTSUFF=${BOOTSUFF}
    echo ROOTSUFF=${ROOTSUFF}
    echo SWAPSUFF=${SWAPSUFF}
    echo BOOTPARTS=${BOOTPARTS}
    echo ROOTPDEVS=${ROOTPDEVS}
    echo ROOTPARTS=${ROOTPARTS}
    echo "Boot Mode: "`if_else_uefi "echo UEFI" "echo BIOS"`
}

config_kernel_cmdline () {
    echo "boot=zfs root=ZFS=rpool/ROOT rw" > /etc/kernel/cmdline
}

update_boot_proxmox () {
    if_zfs config_kernel_cmdline
    rm -f /etc/kernel/proxmox-boot-uuids
    # proxmox-boot-tool clean # this will fail, don't use during installation
    proxmox-boot-tool init ${UEFIPART}
}

update_boot () {
    if_else_proxmox \
        update_boot_proxmox \
        update-grub
}

config_zfs_bpool () {
    systemctl enable zfs-import-bpool.service
}

# config_zfs_rpool () {
#     systemctl enable zfs-load-key.service
# }

inspkg_dropbear () {
    if [ "${UNLOCK_SSH}" == "1" ] ; then
        apt-get install --yes dropbear-initramfs || true
    fi
}

openssh_to_dropbear () {
    cp -f /etc/dropbear/initramfs/dropbear_${1}_host_key /etc/dropbear/initramfs/dropbear_${1}_host_key.bak
    /usr/lib/dropbear/dropbearconvert \
        openssh dropbear /etc/ssh/ssh_host_${1}_key \
        /etc/dropbear/initramfs/dropbear_${1}_host_key
}

config_dropbear () {
    if [ "${UNLOCK_SSH}" == "1" ] ; then
        cp -f /etc/dropbear/initramfs/dropbear.conf /etc/dropbear/initramfs/dropbear.conf.bak
        cat /etc/dropbear/initramfs/dropbear.conf.bak | \
            sed \
                -e s:"#DROPBEAR_OPTIONS=.*":'DROPBEAR_OPTIONS="-p 22 -c cryptroot-unlock"':g \
                > /etc/dropbear/initramfs/dropbear.conf
        openssh_to_dropbear rsa
        openssh_to_dropbear ed25519
        openssh_to_dropbear ecdsa
        
        ( cp -f ${AUTH_KEY} /etc/dropbear/initramfs/authorized_keys && \
              chmod 0600 /etc/dropbear/initramfs/authorized_keys ) || true
    fi
}

chroot_install () {
    config_hostname
    config_nic
    config_admin
    config_aptcacher
    config_instpacks
    if_bootpart \
        if_boot_ext4 \
        if_raid \
        apt-get install --yes mdadm
    config_fstab
    if_encrypt \
        inspkg_encryption
    config_pcr_bank
    if_else_encrypt \
        config_encryption \
        remove_encryption
    if_encrypt_zfs \
        config_encryption_zfs
    inspkg_dropbear
    config_dropbear
    if_encrypt \
        config_crypttab
    if_encrypt \
        recheck_tpmversion
    config_noresume
    config_suspend
    if_zfs \
        if_bootpart \
        config_zfs_bpool
    # if_zfs \
    #     if_encrypt_zfs \
    #     config_zfs_rpool
    config_boot
    update_boot
    apt update
    apt --yes full-upgrade
    update-initramfs -c -k all
}

chroot_restore () {
    config_fstab
    config_boot
    if_encrypt \
        inspkg_encryption
    config_pcr_bank
    if_else_encrypt \
        config_encryption \
        remove_encryption
    if_encrypt \
        config_crypttab
    update_boot
    apt update
    apt --yes full-upgrade
    update-initramfs -c -k all
}

fix_tpm () {
    if_encrypt \
        inspkg_encryption
    config_pcr_bank
    if_else_encrypt \
        config_encryption \
        remove_encryption
    config_crypttab
    update-initramfs -c -k all
}

check_prereq () {
    apt update
    apt install --yes mokutil
    if [ "`mokutil --sb-state`" == "SecureBoot enabled" ] \
           && [ "${DISTRO}" == debian ] \
           && [ "`uname -r|grep pve`" == "" ] ; then
        echo "ERROR: Installing a zfs file system with SecureBoot enabled is not supported"
        exit 1
    fi
}

prepare_partitions () {
    if [ "${DISTRO}" != ubuntu ] ; then
        rm -f /etc/apt/sources.list.d/ceph.list
    fi
    apt update
    if_zfs check_prereq
    apt install --yes cryptsetup
    show_settings
    warn_confirm
    if_else_resuming \
        ask_key \
        set_key
    config_aptcacher
    setup_aptinstall
    if_else_resuming \
        reopen_partitions \
        create_partitions_${DISKLAYOUT}
    skip_if_resuming \
        if_encrypt_luks \
        crypt_partitions ${ROOTPDEVS}
    skip_if_resuming \
        if_encrypt \
        crypt_partitions ${SWAPPDEVS}
    open_partitions
    if_else_resuming \
        mount_partitions \
        build_partitions
}

cp_zpool_cache () {
    if [ -f /etc/zfs/zpool.cache ] ; then
        mkdir -p ${ROOTDIR}/etc/zfs
        cp /etc/zfs/zpool.cache ${ROOTDIR}/etc/zfs/zpool.cache
    fi
}

setup_zfs_bpool () {
    mkdir -p ${ROOTDIR}/etc/systemd/system
    cat <<'EOF' > ${ROOTDIR}/etc/systemd/system/zfs-import-bpool.service
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none bpool
# Work-around to preserve zpool cache:
ExecStartPre=-/bin/mv /etc/zfs/zpool.cache /etc/zfs/preboot_zpool.cache
ExecStartPost=-/bin/mv /etc/zfs/preboot_zpool.cache /etc/zfs/zpool.cache

[Install]
WantedBy=zfs-import.target
EOF
}

# setup_zfs_rpool () {
#     mkdir -p ${ROOTDIR}/etc/systemd/system
    
#     cat <<'EOF' > ${ROOTDIR}/usr/bin/autounlock_zfs
# #!/bin/bash

# decrypt_clevis () {
#     ASKPASS_='/lib/cryptsetup/askpass'
#     PROMPT_="${CRYPTTAB_NAME}'s password: "

#     if test -f $1 && /usr/bin/clevis decrypt < $1 ; then
#         exit 0
#     fi

#     $ASKPASS_ "$PROMPT_"
# }

# decrypt_clevis /autounlock.key | /sbin/zfs load-key -L prompt -a
# EOF
    
#     chmod a+x ${ROOTDIR}/usr/bin/autounlock_zfs
    
#     cat <<'EOF' > ${ROOTDIR}/etc/systemd/system/zfs-load-key.service
# [Unit]
# Description=Load encryption keys
# DefaultDependencies=no
# After=zfs-import.target
# Before=zfs-mount.service

# [Service]
# Type=oneshot
# RemainAfterExit=yes
# ExecStart=/usr/bin/autounlock_zfs
# StandardInput=tty-force

# [Install]
# WantedBy=zfs-mount.service
# EOF
# }

# jose jwe enc -p -I decrypted.txt

install_encryption () {
    if_encrypt_luks \
        create_keyfile_luks
    if_encrypt_zfs \
        create_keyfile_zfs
    if_encrypt_luks \
        encrypt_partitions ${ROOTPDEVS}
    if_encrypt \
        encrypt_partitions ${SWAPPDEVS}
}

install () {
    prepare_partitions
    exec_once \
        unpack_distro
    setup_apt
    skip_if_resuming \
        install_encryption
    bind_dirs
    config_chroot
    if_zfs cp_zpool_cache
    if_zfs \
        if_bootpart \
        setup_zfs_bpool
    # if_zfs \
    #     if_encrypt_zfs \
    #     setup_zfs_rpool
    run_chroot /home/${USERNAME}/deploy/deploy.sh chroot_install
    unbind_dirs
    unmount_partitions
    close_partitions
}

if_live () {
    if [ -d /cdrom/dists/${VERSNAME} ] ; then
        $*
    fi
}

rescue () {
    RESUMING=yes
    if_live \
        setup_aptinstall
    apt update
    apt install --yes cryptsetup
    ask_key
    config_aptcacher
    open_partitions
    mount_partitions
    bind_dirs
    # config_chroot
    run_chroot
    unbind_dirs
    unmount_partitions
    close_partitions
}

restore_pool () {
    POOL=$1
    shift
    BACKUPSRC=${POOL}/${2}
    shift
    # Remove the snapshot if it exist:
    ( ssh ${BACKUPSRV} zfs destroy  -R ${BACKUPSRC} || true )
    # Create the snapshot to get the latest changes:
    ssh ${BACKUPSRV} zfs snapshot -r ${BACKUPSRC}
    SIZE="`ssh ${BACKUPSRV} zfs send -nvPc -R ${BACKUPSRC} 2>/dev/null | grep size| awk '{print $2}'`"
    ssh ${BACKUPSRV} zfs send -c -R ${BACKUPSRC} | pv -reps ${SIZE} | zfs recv -d -F rpool
}

# EXAMPLE of parameters to restore a machine from a backup/clone, adapt them as needed:
restore () {
    prepare_partitions
    apt-get install --yes pv
    # WARNING: SNAPSHOT is temporary, it will be destroyed
    SNAPSHOT=__deploy_restsnap__
    # SERVER name
    BACKUPSRV=debian3
    restore_pool rpool ROOT/${DESTNAME}@${SNAPSHOT}
    restore_pool bpool BOOT/${DESTNAME}@${SNAPSHOT}
    skip_if_resuming \
        if_encrypt_luks \
        encrypt_partitions ${ROOTPDEVS}
    skip_if_resuming \
        if_encrypt \
        encrypt_partitions ${SWAPPDEVS}
    bind_dirs
    config_chroot
    run_chroot /home/${USERNAME}/deploy/deploy.sh chroot_restore
    if_zfs cp_zpool_cache
    unbind_dirs
    unmount_partitions
    close_partitions
}

if [ $# = 0 ] ; then
    install
else
    $*
fi

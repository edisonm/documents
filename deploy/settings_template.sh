# Machine specific configuration:
USERNAME=admin
FULLNAME="Administrative Account"
DESTNAME=debian1

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
# APTCACHER=192.168.1.6
APTCACHER=10.8.0.1

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
# ENCRYPT=zfs
ENCRYPT=luks

# Enable compression
# COMPRESSION=
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
# ntp is compulsory for services that require precise date/time (i.e., AD)

DEBPACKS="ntp acl binutils build-essential openssh-server emacs"
# DEBPACKS+=" firefox-esr gparted mtools"
# Equivalent to live xfce4 installation + some tools
# DEBPACKS+=" xfce4 task-xfce-desktop"
# DEBPACKS+=" lxde task-lxde-desktop"
# DEBPACKS+=" cinnamon task-cinnamon-desktop"
# DEBPACKS+=" acpid alsa-utils anacron fcitx libreoffice"

# Disk layout:
DISKLAYOUT=singboot

# several raid layouts:
# DISKLAYOUT=raid0
# DISKLAYOUT=raid1
# DISKLAYOUT=raid10
# DISKLAYOUT=raidz
# DISKLAYOUT=raidz2
# DISKLAYOUT=raidz3

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
BOOTSIZE=+1G

# boot partition file system to be used
# BOOTFS=ext4
# BOOTFS=btrfs
BOOTFS=zfs

# Root partition size, 0 for max available space, minimum ~20GB
# ROOTSIZE=+32G
# ROOTSIZE=+32G
ROOTSIZE=+64G

# root partition file system to be used
# ROOTFS=ext4
# ROOTFS=btrfs
ROOTFS=zfs

# Swap partition size, placed at the end, empty for no swap, it is recommended
# to be equal to the available RAM memory
# SWAPSIZE=-8G
# SWAPSIZE=+32G
SWAPSIZE=

# SWAP_AT_THE_END=1

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
# DISKS="/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1"

# Enable if you are attempting to continue an incomplete installation
# RESUMING=yes

ROOTDIR=${ROOTDIR:-/mnt}

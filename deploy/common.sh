#!/bin/bash

set -e

set_key () {
    echo "The master passphrase is used as failover decryption method and admin user password"
    export KEY_="$($ASKPASS_ "New password:")"
    CONFIRM_="$($ASKPASS_ "Retype new password:")"
    if [ "${KEY_}" != "${CONFIRM_}" ] ; then
        echo "ERROR: Confirmation didn't match, aborting"
        exit 1
    fi
}

ask_key () {
    echo "Input the master passphrase you used before"
    export KEY_="$($ASKPASS_ "Password:")"
}

bind_dirs () {
    # Against some advices on Internet, --rbind must not be used, otherwise you
    # are forced to restart the machine after unbinding these directories, which
    # is problematic in production machines
    mount --bind /dev  ${ROOTDIR}/dev
    mount --bind /proc ${ROOTDIR}/proc
    mount --bind /sys  ${ROOTDIR}/sys
    if [ -d /sys/firmware/efi/efivars ] ; then
        mount --bind /sys/firmware/efi/efivars ${ROOTDIR}/sys/firmware/efi/efivars
    fi
    mount --bind /run  ${ROOTDIR}/run
    mount --bind /tmp  ${ROOTDIR}/tmp
}

unbind_dirs () {
    umount ${ROOTDIR}/dev
    umount ${ROOTDIR}/proc
    if [ -d /sys/firmware/efi/efivars ] ; then
        umount ${ROOTDIR}/sys/firmware/efi/efivars
    fi
    umount ${ROOTDIR}/sys
    umount ${ROOTDIR}/run
    umount ${ROOTDIR}/tmp
}

config_aptcacher () {
    if [ "$APTCACHER" != "" ] ; then
        mkdir -p ${1}/etc/apt/apt.conf.d/
        echo 'Acquire::http { Proxy "http://'${APTCACHER}':3142"; }' \
             > ${1}/etc/apt/apt.conf.d/01proxy
    fi
}

setup_apt () {
    if [ "${VERSNAME}" == "bookworm" ] ; then
        NONFREE="non-free-firmware"
    else
        NONFREE="non-free"
    fi
    setup_apt_${DISTRO}
}

setup_apt_debian () {
    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      -e s:'<NONFREE>':"${NONFREE}":g \
                      > ${ROOTDIR}/etc/apt/sources.list
deb http://deb.debian.org/debian <VERSNAME> main contrib <NONFREE>
deb-src http://deb.debian.org/debian <VERSNAME> main contrib <NONFREE>

deb http://security.debian.org/debian-security <VERSNAME>-security main contrib <NONFREE>
deb-src http://security.debian.org/debian-security <VERSNAME>-security main contrib <NONFREE>

deb http://deb.debian.org/debian <VERSNAME>-updates main contrib <NONFREE>
deb-src http://deb.debian.org/debian <VERSNAME>-updates main contrib <NONFREE>
EOF

    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      -e s:'<NONFREE>':"${NONFREE}":g \
                      > ${ROOTDIR}/etc/apt/sources.list.d/${VERSNAME}-backport.list
deb http://deb.debian.org/debian <VERSNAME>-backports main contrib <NONFREE>
deb-src http://deb.debian.org/debian <VERSNAME>-backports main contrib <NONFREE>
EOF
}

setup_apt_ubuntu () {
    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      > ${ROOTDIR}/etc/apt/sources.list
deb     http://archive.ubuntu.com/ubuntu <VERSNAME> main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu <VERSNAME> main restricted universe multiverse

deb     http://archive.ubuntu.com/ubuntu <VERSNAME>-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu <VERSNAME>-updates main restricted universe multiverse

deb     http://archive.ubuntu.com/ubuntu <VERSNAME>-security main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu <VERSNAME>-security main restricted universe multiverse
EOF
}

setup_apt_proxmox () {
    setup_apt_debian
    
    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      > ${ROOTDIR}/etc/apt/sources.list.d/${VERSNAME}-pve-install-repo.list
deb [arch=amd64] http://download.proxmox.com/debian/pve <VERSNAME> pve-no-subscription
EOF
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O ${ROOTDIR}/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
}

config_admin () {
    ( printf "%s\n%s\n${FULLNAME}\n\n\n\n\nY\n" "$KEY_" "$KEY_" | adduser $USERNAME ) || true
    usermod -aG sudo $USERNAME
    # printf "%s\n%s\n" "$KEY_" "$KEY_" | passwd root
}

config_init () {
    INIPACKS=""
    if [ "$(dmidecode -s system-manufacturer)" == "QEMU" ] ; then
        INIPACKS+=" qemu-guest-agent"
    fi
    # os-prober is needed only on dual-boot systems:
    apt-get remove --yes --purge os-prober
    INIPACKS+=" sudo btrfs-progs"
    if [ "$DISTRO" == "debian" ] ; then
        INIPACKS+=" debconf-utils linux-image-`dpkg --print-architecture`"
    elif  [ "$DISTRO" == "proxmox" ] ; then
        INIPACKS+=" debconf-utils pve-kernel-6.2"
        if [ "$PROXMOX" == "full" ] ; then
            INIPACKS+=" proxmox-ve postfix open-iscsi chrony zfs-initramfs"
        else
            INIPACKS+=" zfsutils-linux zfs-zed zfs-initramfs"
        fi
    elif [ "$DISTRO" == "ubuntu" ] ; then
        INIPACKS+=" debconf-i18n linux-image-generic"
    fi
    echo "Installing basic packages"
    apt-get install --yes $INIPACKS
    echo "Installing extra packages"
    apt-get install --yes $DEBPACKS
}

config_suspend () {
    # 95% I have to disable this, even on non-server machines:
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
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
    apt-get install --yes locales console-setup initramfs-tools
    if [ "${DISTRO}" == debian ] || [ "${DISTRO}" == proxmox ] ; then
        dpkg-reconfigure locales tzdata keyboard-configuration console-setup -f noninteractive
        if [ "${DISTRO}" == proxmox ] ; then
            apt-get install --yes proxmox-kernel-helper systemd-boot
        fi
    elif [ "${DISTRO}" == ubuntu ] ; then
        dpkg-reconfigure locales tzdata keyboard-configuration console-setup
    fi
    
}

unpack_distro () {
    debootstrap ${VERSNAME} ${ROOTDIR}
}

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
    mount --bind /sys/firmware/efi/efivars ${ROOTDIR}/sys/firmware/efi/efivars
    mount --bind /run  ${ROOTDIR}/run
    mount --bind /tmp  ${ROOTDIR}/tmp
}

unbind_dirs () {
    umount ${ROOTDIR}/dev
    umount ${ROOTDIR}/proc
    umount ${ROOTDIR}/sys/firmware/efi/efivars
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
    setup_apt_${DISTRO}
}

setup_apt_debian () {
    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      > ${ROOTDIR}/etc/apt/sources.list
deb http://deb.debian.org/debian <VERSNAME> main contrib
deb-src http://deb.debian.org/debian <VERSNAME> main contrib

deb http://security.debian.org/debian-security <VERSNAME>-security main contrib
deb-src http://security.debian.org/debian-security <VERSNAME>-security main contrib

deb http://deb.debian.org/debian <VERSNAME>-updates main contrib
deb-src http://deb.debian.org/debian <VERSNAME>-updates main contrib
EOF

    cat <<'EOF' | sed -e s:'<VERSNAME>':"${VERSNAME}":g \
                      > ${ROOTDIR}/etc/apt/sources.list.d/${VERSNAME}-backport.list
deb http://deb.debian.org/debian <VERSNAME>-backports main contrib
deb-src http://deb.debian.org/debian <VERSNAME>-backports main contrib
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

config_admin () {
    ( printf "%s\n%s\n${FULLNAME}\n\n\n\n\nY\n" "$KEY_" "$KEY_" | adduser $USERNAME ) || true
    usermod -aG sudo $USERNAME
    # printf "%s\n%s\n" "$KEY_" "$KEY_" | passwd root
}

config_init () {
    if [ "$(dmidecode -s system-manufacturer)" == "QEMU" ] ; then
        apt-get install --yes qemu-guest-agent
    fi
    # os-prober is needed only on dual-boot systems:
    apt-get remove --yes --purge os-prober
    apt-get install --yes sudo btrfs-progs
    if [ "$DISTRO" == "debian" ] ; then
        apt-get install --yes debconf-utils linux-image-`dpkg --print-architecture`
    elif [ "$DISTRO" == "ubuntu" ] ; then
        apt-get install --yes debconf-i18n linux-image-generic
    fi
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
    apt-get install --yes locales console-setup
    if [ "${DISTRO}" == debian ] ; then
        dpkg-reconfigure locales tzdata keyboard-configuration console-setup -f noninteractive
    elif [ "${DISTRO}" == ubuntu ] ; then
        dpkg-reconfigure locales tzdata keyboard-configuration console-setup
    fi
    apt-get install --yes mdadm
}

unpack_distro () {
    debootstrap ${VERSNAME} ${ROOTDIR}
}

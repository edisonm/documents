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
    mount --rbind /dev  ${ROOTDIR}/dev
    mount --rbind /proc ${ROOTDIR}/proc
    mount --rbind /sys  ${ROOTDIR}/sys
    mount --rbind /run  ${ROOTDIR}/run
    mount --rbind /tmp  ${ROOTDIR}/tmp
}

unbind_dirs () {
    umount -l ${ROOTDIR}/dev
    umount -l ${ROOTDIR}/proc
    umount -l ${ROOTDIR}/sys
    umount -l ${ROOTDIR}/run
    umount -l ${ROOTDIR}/tmp
}

config_aptcacher () {
    if [ "$APTCACHER" != "" ] ; then
        echo 'Acquire::http { Proxy "http://'${APTCACHER}':3142"; }' \
             > ${1}/etc/apt/apt.conf.d/01proxy
    fi
}

setup_apt () {
    cat <<'EOF' > ${ROOTDIR}/etc/apt/sources.list
deb http://deb.debian.org/debian bullseye main contrib
deb-src http://deb.debian.org/debian bullseye main contrib

deb http://security.debian.org/debian-security bullseye-security main contrib
deb-src http://security.debian.org/debian-security bullseye-security main contrib

deb http://deb.debian.org/debian bullseye-updates main contrib
deb-src http://deb.debian.org/debian bullseye-updates main contrib
EOF
    cat <<'EOF' > ${ROOTDIR}/etc/apt/sources.list.d/bullseye-backport.list
deb http://deb.debian.org/debian bullseye-backports main contrib
deb-src http://deb.debian.org/debian bullseye-backports main contrib
EOF
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
    dpkg-reconfigure locales tzdata keyboard-configuration console-setup -f noninteractive
    apt-get install --yes mdadm
}

unpack_debian () {
    debootstrap bullseye ${ROOTDIR}
}

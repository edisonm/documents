#!/bin/bash

. `dirname $0`/common.sh

USERNAME=admin
FULLNAME="Administrative Account"
DISTRO=ubuntu
VERSNAME=focal
DESTNAME=${VERSNAME}
# APT Cache Server, leave it empty to disable:
APTCACHER=192.168.11.6
# Kludge: hardwiring the DNS sever in order to get the hostname from there
DNSSERVER=192.168.11.6
NADDRESS='192.168.11'
CLIENTIP=${NADDRESS}'.*'
SERVERIPS=`hostname -I`
SERVERIP=`( for i in ${SERVERIPS} ; do echo ${i} ; done ) | grep ${NADDRESS}`
BASEDIR=/srv/nfs4/pxe/${DESTNAME}
ROOTDIR=${BASEDIR}/root
ROOTMODE=ro

# Don't make this complicated, we just hardwire TFTPROOT:
# TFTPROOT=`grep TFTP_DIRECTORY /etc/default/tftpd-hpa|sed 's/TFTP_DIRECTORY=\"\(.*\)\"/\1/g'`
TFTPROOT=/srv/tftp
TFTPDIR=${TFTPROOT}/${DESTNAME}

pxeserver () {
    
    if [ -d ${ROOTDIR}/etc/apt/sources.list.d ] ; then
        FIRST=0
    else
        FIRST=1
    fi

    apt install -y debootstrap pxelinux nfs-kernel-server tftpd-hpa

    mkdir -p ${ROOTDIR}/etc/apt/sources.list.d ${BASEDIR}/home \
          ${ROOTDIR}/home ${ROOTDIR}/boot ${TFTPDIR}/boot
    setup_apt
    config_aptcacher ${ROOTDIR}
    config_vmlinuz
    
    if [ "${FIRST}" == 1 ] ; then
        mount_partitions
        unpack_distro
        bind_dirs
        config_chroot /tmp/pxeserver.sh do_chroot_pxe
        unbind_dirs
        unmount_partitions
    fi
    
    config_fstab_pxe
    config_overlay
    setup_pxe
    cleanup_guest_files
    systemctl restart nfs-kernel-server
}

rescue () {
    mount_partitions
    bind_dirs
    config_chroot
    unbind_dirs
    unmount_partitions
}

cleanup_guest_files () {
    rm -f ${ROOTDIR}/etc/hostname ${ROOTDIR}/etc/hosts ${ROOTDIR}/etc/network/interfaces.d/*
}

config_chroot () {
    cp pxeserver.sh common.sh ${ROOTDIR}/tmp/
    chroot ${ROOTDIR} $*
}

mount_partitions () {
    mount --bind ${BASEDIR}/home ${ROOTDIR}/home
    mount --bind ${TFTPDIR}/boot ${ROOTDIR}/boot
}

unmount_partitions () {
    umount -l ${ROOTDIR}/home
    umount -l ${ROOTDIR}/boot
}

setup_pxe () {
    mkdir -p /etc/exports.d \
          ${TFTPDIR}/boot \
          ${TFTPDIR}/pxelinux.cfg
    
    ln -f /usr/lib/PXELINUX/pxelinux.0               ${TFTPDIR}/pxelinux.0
    ln -f /usr/lib/syslinux/modules/bios/ldlinux.c32 ${TFTPDIR}/ldlinux.c32
    ln -f /usr/lib/syslinux/modules/bios/menu.c32    ${TFTPDIR}/menu.c32
    ln -f /usr/lib/syslinux/modules/bios/libutil.c32 ${TFTPDIR}/libutil.c32

    chown tftp:tftp -R ${TFTPDIR}
    chmod go+rX     -R ${TFTPDIR}
    
    RELEASE="$(echo `lsb_release -irs`)"
    
    ( echo "${TFTPDIR}/boot ${CLIENTIP}(${ROOTMODE},async,no_subtree_check,no_root_squash,no_all_squash)" ; \
      echo "${ROOTDIR} ${CLIENTIP}(${ROOTMODE},async,no_subtree_check,no_root_squash,no_all_squash)" ; \
      echo "${BASEDIR}/home ${CLIENTIP}(rw,async,no_subtree_check)" ) \
        > /etc/exports.d/${DESTNAME}.exports
    
    cat <<'EOF' | sed -e s:'<DESTNAME>':"${DESTNAME}":g \
                      -e s:'<RELEASE>':"${RELEASE}":g \
                      -e s:'<SERVERIP>':"${SERVERIP}":g \
                      -e s:'<ROOTDIR>':"${ROOTDIR}":g \
                      -e s:'<ROOTMODE>':"${ROOTMODE}":g \
                      > ${TFTPDIR}/pxelinux.cfg/default
DEFAULT menu.c32
TIMEOUT 50
ONTIMEOUT RELEASE
PROMPT 0

MENU TITLE  PXE Server <DESTNAME>
NOESCAPE 1
ALLOWOPTIONS 1
PROMPT 0

menu color border       37;44 #ffffffff #00000000 std
menu background         37;44
menu color screen       37;44
menu color title	* #FFFFFFFF *
menu color border	* #00000000 #00000000 none
menu color sel		* #ffffffff #76a1d0ff *
menu color hotsel	1;7;37;44 #ffffffff #76a1d0ff *
menu color tabmsg	37;44
menu color help		37;44 #ffdddd00 #00000000 none
# XXX When adjusting vshift, take care that rows is set to a small
# enough value so any possible menu will fit on the screen,
# rather than falling off the bottom.
menu vshift 3
# menu vshift 4
# menu rows 14
# # The help line must be at least one line from the bottom.
# menu helpmsgrow 14
# # The command line must be at least one line from the help line.
# menu cmdlinerow 16
# menu timeoutrow 16
# menu tabmsgrow 18
menu tabmsg Press ENTER to boot or TAB to edit a menu entry

NOESCAPE 1

LABEL RELEASE
MENU LABEL <RELEASE>
KERNEL boot/vmlinuz
APPEND ip=dhcp root=/dev/nfs nfsroot=<SERVERIP>:<ROOTDIR> <ROOTMODE> initrd=boot/initrd.img raid=noautodetect quiet splash ipv6.disable=1

MENU BEGIN Advanced options for <RELEASE>
MENU TITLE Advanced options for <RELEASE>
EOF

    LABEL=1
    for VERSION in `cd ${TFTPDIR}/boot;ls vmlinuz-*|sed -e s:vmlinuz-::g|sort -r` ; do
        cat <<'EOF' | sed -e s:'<DESTNAME>':"${DESTNAME}":g \
                          -e s:'<RELEASE>':"${RELEASE}":g \
                          -e s:'<SERVERIP>':"${SERVERIP}":g \
                          -e s:'<ROOTDIR>':"${ROOTDIR}":g \
                          -e s:'<ROOTMODE>':"${ROOTMODE}":g \
                          -e s:'<VERSION>':"${VERSION}":g \
                          -e s:'<LABEL>':"${LABEL}":g \
                          >> ${TFTPDIR}/pxelinux.cfg/default

LABEL <LABEL>
MENU LABEL Linux <VERSION>
KERNEL boot/vmlinuz-<VERSION>
APPEND ip=dhcp root=/dev/nfs nfsroot=<SERVERIP>:<ROOTDIR> <ROOTMODE> initrd=boot/initrd.img-<VERSION> raid=noautodetect quiet splash ipv6.disable=1

LABEL <LABEL>r
MENU LABEL Linux <VERSION> (recovery mode)
KERNEL boot/vmlinuz-<VERSION>
APPEND ip=dhcp root=/dev/nfs nfsroot=<SERVERIP>:<ROOTDIR> <ROOTMODE> single initrd=boot/initrd.img-<VERSION> raid=noautodetect quiet splash ipv6.disable=1

EOF
        LABEL=$(($LABEL+1))
    done
    echo "MENU END" >> ${TFTPDIR}/pxelinux.cfg/default
}

OVERDIR=/usr/local/ovrfs

config_overlay () {
    # Source: https://github.com/hansrune/domoticz-contrib/blob/master/utils/mount_overlay
    mkdir -p ${ROOTDIR}/usr/local/bin
    cat <<'EOF' | sed -e s:'<OVERDIR>':"${OVERDIR}":g \
                      -e s:'<DNSSERVER>':"${DNSSERVER}":g \
                      > ${ROOTDIR}/usr/local/bin/ovrfs
#!/bin/sh

OVERDIR=<OVERDIR>
DIR="$1"

[ -z "${DIR}" ] && exit 1
#
# ro must be the first mount option for root .....
#

ROOT_MOUNT=$( awk '$2=="/" { print substr($4,1,2) }' /proc/mounts )

if [ "$ROOT_MOUNT" = "ro" ] ; then
    /bin/mount -t tmpfs tmpfs ${OVERDIR}${DIR}
    /bin/mkdir -p ${OVERDIR}${DIR}/upper
    /bin/mkdir -p ${OVERDIR}${DIR}/work
    OPTS="-o lowerdir=${DIR},upperdir=${OVERDIR}${DIR}/upper,workdir=${OVERDIR}${DIR}/work"
    /bin/mount -t overlay ${OPTS} overlay ${DIR}
fi

if [ "${DIR}" = "/etc" ] ; then
    # As soon as /etc is writable, fix hostname and nic:
    setup_hostname () {
	ipaddr=`hostname -I`
	fqdn=`host ${ipaddr} <DNSSERVER>|awk '{print $5}'|sed -e s/.$//g`
	hostname=${fqdn%%.*}
	echo ${hostname} > /etc/hostname
	( echo "127.0.0.1	localhost" ; \
	  echo "::1		localhost ip6-localhost ip6-loopback" ; \
	  echo "ff02::1		ip6-allnodes" ; \
	  echo "ff02::2		ip6-allrouters" ; \
	  echo "${ipaddr} ${fqdn} ${hostname}" ; \
	  ) > /etc/hosts
    }
    setup_nic () {
	for nic in `ls /sys/class/net` ; do
            ( echo "auto-hotplug $nic"
              if [ "$nic" != "lo" ] ; then
		  echo "iface $nic inet dhcp"
              else
		  echo "iface $nic inet loopback"
              fi
            ) > /etc/network/interfaces.d/$nic
	done
    }

    setup_hostname
    setup_nic
fi
EOF
    chmod a+rx ${ROOTDIR}/usr/local/bin/ovrfs
}

config_fstab_pxe () {
    ( echo "/dev/nfs                    /     nfs   tcp,nolock      0  0" ; \
      echo "tmpfs                       /tmp  tmpfs nodev,nosuid    0  0" ; \
      echo "ovrfs                       /etc  fuse  nofail,defaults 0  0" ; \
      echo "ovrfs                       /var  fuse  nofail,defaults 0  0" ; \
      echo "${SERVERIP}:${TFTPDIR}/boot /boot nfs   ${ROOTMODE},tcp,nolock   0  0" ; \
      echo "${SERVERIP}:${BASEDIR}/home /home nfs   rw,tcp,nolock   0  0" ; \
      ) > ${ROOTDIR}/etc/fstab
    mkdir -p ${ROOTDIR}${OVERDIR}/etc ${ROOTDIR}${OVERDIR}/var
}

do_chroot_pxe () {
    config_initpacks
    apt-get install --yes nfs-common fuse lsof bind9-host
    # apt-get --yes purge connman
    # apt-get --yes autoremove
    config_suspend
    config_init
    update-initramfs -c -k all
}

config_vmlinuz () {
    mkdir -p ${ROOTDIR}/etc/initramfs-tools/hooks
    cat <<'EOF' > ${ROOTDIR}/etc/initramfs-tools/hooks/vmlinuz
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

ln -sf vmlinuz-${version} /boot/vmlinuz
ln -sf initrd.img-${version} /boot/initrd.img

EOF
    chmod a+x ${ROOTDIR}/etc/initramfs-tools/hooks/vmlinuz
}

if [ $# = 0 ] ; then
    pxeserver
else
    $*
fi

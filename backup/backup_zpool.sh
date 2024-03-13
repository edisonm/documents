
snapshot_zpool () {
    snapshot=${send_pool}${send_zfs}@${snprefix}${currsnap}
    if [ "`${send_ssh} zfs list -pHt snapshot -o name ${snapshot} 2>/dev/null`" = "" ] ; then
	dryer ${send_ssh} zfs snapshot -r ${snapshot}
    fi
}

destroy_snapshot_zpool () {
    ssh_snap="`ssh_host ${1}`"
    snapshot="${2}${4}@${5}"
    if [ "`${ssh_snap} zfs list -pHt snapshot -o name ${snapshot} 2>/dev/null`" != "" ]; then
        dryer ${ssh_snap} zfs destroy ${dropopts} ${snapshot}
    fi
}

sendsnap0_zpool () {
    ${send_ssh} zfs list -Ht snapshot -o name ${send_zpoolfs} 2>/dev/null | \
        sed -e "s:${send_zpoolfs}@::g" | sort -u
}

recvsnap0_zpool () {
    ${recv_ssh} zfs list -Ht snapshot -o name ${recv_zpoolfs}${send_zfs} 2>/dev/null | \
        sed -e "s:${recv_zpoolfs}${send_zfs}@::g" | sort -u
}

zfs_prev_zpool () {
    # currsnap=`$send_ssh zfs list -Ht snapshot -o name ${send_zpoolfs}|sed -e "s:${send_zpoolfs}@::g"|tail -n1`
    send_zpoolfss="`${send_ssh} zfs list -r -Ho name ${send_zpool}${send_zfs}`"
    if [ "${send_unfold}" != "" ] || ( [ "${prevsnap}" != "" ] && [ `requires_unfold ${prevcmd}` = 1 ] ) ; then
        # echo "Note: unfolding -R since some incrementals are incomplete"
        for send_zpoolfs in ${send_zpoolfss} ; do
            send_zfs=${send_zpoolfs##${send_zpool}}
            prevsnap=`prevsnap ${prevcmd}`
            sendopts="-R"
	    dropopts=""
            $*
        done
    else
        sendopts="-R"
	dropopts="-r"
        $*
    fi
}

backup_zpool () {
    has_recv_zpoolfs="`${recv_ssh} zfs list -Ho name ${recv_zpoolfs} 2>/dev/null`" || true
    if [ "${has_recv_zpoolfs}" = "" ] ; then
        dryer ${recv_ssh} zfs create ${recv_zpoolfs} -o mountpoint=none
        # TBD: add '-o keyformat=passphrase -o keylocation=file:///crypto_keyfile.bin' if encrypted
    fi
    snapshot_size=`snapshot_size`
    ( dryern $send_ssh zfs send -c ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} \
          | dryerpn pv -reps ${snapshot_size} \
          | dryerp ${recv_ssh} zfs recv -d -F ${recv_zpoolfs} ) || true
    if [ "`${recv_ssh} zfs get -H -o value canmount ${recv_zpoolfs}${send_zfs}`" = on ] ; then
	dryer ${recv_ssh} zfs set canmount=noauto ${recv_zpoolfs}${send_zfs}
    fi
}

set_sendopts_zpool () {
    sendopts="${sendopts} -I ${send_zpoolfs}@${snprefix}${prevsnap}"
}

forall_mediapools_zpool () {
    while IFS=';' read -r media_pool ; do
        $* < /dev/null
    done < <(${media_ssh} zpool list -Ho name)
}

if_removable_media_zpool () {
    if [ "`${media_ssh} zpool status ${media_pool}\
         |grep crbackup_\
         |awk '{print $1}'|sed -e s:'crbackup_'::g`" != "" ] ; then
        $*
    fi
}

recv_size_zpool () {
    ${recv_ssh} zpool list -Hp ${recv_zpool} -o free
}

recv_volumes_zpool () {
    ${recv_ssh} zpool status ${recv_pools[${recv_hostpool}]} \
        | grep crbackup_|awk '{print $1}' \
        | sed -e s:'crbackup_'::g
}

media_export_zpool () {
    dryer ${media_ssh} zpool export ${media_pool}
}

source_mount_zpool () {
    true
}

source_umount_zpool () {
    true
}

snapshot_size_zpool () {
    size="`$send_ssh zfs send -nvPc ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} 2>/dev/null | grep size | awk '{print $2}'`"
    if [ "${size}" = "" ] ; then
	echo 0
    else
	echo ${size}
    fi
}

show_import_volume_zpool () {
    if [ "`echo $*|grep ${volume}`" != "" ] ; then
	echo ${2}
    fi
}

media_import_volume_zpool () {
    imppool=${1}
    ${media_ssh} zpool import -N ${imppool} -R /mnt/${imppool}
}

get_media_import_line_zpool () {
    echo `${media_ssh} zpool import 2>/dev/null`|sed 's/.pool:/\npool:/g'
}

cache_command () {
    command="$1"
    cache_file="$2"
    time_out="$3"
    if [ -f ${cache_file} ] && [ $(( `date +%s` - `stat -L --format %Y ${cache_file} ` < ${time_out} )) = 1 ] ; then
        # if [ "`stat -L --format %s ${cached_data}`" = "0" ] ; then
        #     ${command}|tee ${cache_file}
        # else
	#     cat ${cache_file}
        # fi
	cat ${cache_file}
    else
        ${command}|tee ${cache_file}
    fi
}

media_import_line_zpool () {
    # cache command results for 1 day. Note: it turns out cache_command is not handy, commented out --EMM
    # cache_command get_media_import_line_zpool data/cache_${mediahost}_milz.dat "60*60*24"
    get_media_import_line_zpool data/cache_${mediahost}_milz.dat "60*60*24"
}

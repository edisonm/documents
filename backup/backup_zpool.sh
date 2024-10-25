
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
        send_unfolded=1
        for send_zpoolfs in ${send_zpoolfss} ; do
            prevsnap=`prevsnap ${prevcmd}`
            sendopts="-R"
	    dropopts=""
            send_zfs=${send_zpoolfs##${send_zpool}} $*
        done
    else
        send_unfolded=0
        sendopts="-R"
        dropopts="-r"
        $*
    fi
}

zfs_create_rec () {
    has_recv_zpoolfs="`${recv_ssh} zfs list -Ho name ${1} 2>/dev/null`" || true
    if [ "${has_recv_zpoolfs}" = "" ] ; then
        zfs_create_rec "`dirname ${1}`"
        dryer ${recv_ssh} zfs create ${1} -o mountpoint=none
        # TBD: add '-o keyformat=passphrase -o keylocation=file:///crypto_keyfile.bin' if encrypted
    fi
}

snapshot_size_zpool () {
    size="`$send_ssh zfs send -nvPc ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} 2>/dev/null | grep size | awk '{print $2}'`"
    if [ "${size}" = "" ] ; then
	echo 0
    else
	echo ${size}
    fi
}

backup_zpool () {
    zfs_create_rec "${recv_zpoolfs}"
    ( ( dryern ${send_ssh} zfs send -c ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} \
          | dryerpn pv -reps ${snapshot_size} \
          | dryerp ${recv_ssh} zfs recv -d -F ${recv_zpoolfs} ) || true )
}

# enable in Debian 12:
zfssetopts="-u"

offmount_zpool () {
    send_canmount_value="`${send_ssh} zfs get -H -o value canmount ${send_zpoolfs} 2>/dev/null`"
    recv_canmount_value="`${recv_ssh} zfs get -H -o value canmount ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"

    if [ "${recv_canmount_value}" != "" ] ; then # if the recv exists
	if [ "${send_canmount_value}" != "-" ] ; then
            if [ "${recv_canmount_value}" != "off" ] ; then
		dryer ${recv_ssh} zfs set ${zfssetopts} canmount=off ${recv_zpoolfs}${send_zfs}
            fi
	fi
	send_mountpoint_source="`${send_ssh} zfs get -H -o source mountpoint ${send_zpoolfs} | awk '{print $1}' 2>/dev/null`"
	if [ "${send_mountpoint_source}" = local ] || [ "${send_mountpoint_source}" = received ] ; then
	    send_mountpoint_value="`${send_ssh} zfs get -H -o value mountpoint ${send_zpoolfs} 2>/dev/null`"
	    if [ "${send_mountpoint_value}" != none ] ; then
		mountpoint="/${send_host}${send_mountpoint_value}"
		recv_mountpoint_value="`${recv_ssh} zfs get -H -o value mountpoint ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
		if [ "${recv_mountpoint_value}" != "/mnt/${recv_zpool}${mountpoint}" ] ; then
		    dryer ${recv_ssh} zfs set ${zfssetopts} mountpoint=${mountpoint} ${recv_zpoolfs}${send_zfs}
		fi
	    fi
	elif [ "${send_mountpoint_source}" = inherited ] ; then
            recv_mountpoint_source="`${recv_ssh} zfs get -H -o source mountpoint ${recv_zpoolfs}${send_zfs} | awk '{print $1}' 2>/dev/null || true`"
            if [ "${send_mountpoint_source}" != "${recv_mountpoint_source}" ] ; then
		dryer ${recv_ssh} zfs inherit mountpoint ${recv_zpoolfs}${send_zfs}
            fi
	elif [ "${send_mountpoint_source}" = "-" ] ; then
            # mountpoint doesn't apply
            true
	else
            # unhandled situation, just print the command to see what happened
            echo "# ${recv_host} zfs send_mountpoint_source=${send_mountpoint_source} ${recv_zpoolfs}${send_zfs}"
	fi
    fi
}

info_dir=__bak_info__

bak_info_zpool () {
    has_meta_info_fs="`${media_ssh} zfs list -Ho name ${media_pool}/${info_dir} 2>/dev/null || true`"
    if [ "${has_meta_info_fs}" = "" ] ; then
        dryer ${media_ssh} zfs create ${media_pool}/${info_dir} -o canmount=on -o mountpoint=/${info_dir}
    else
        dryer ${media_ssh} rm -f "/mnt/${media_pool}/${info_dir}/fixmount_*.sh"
    fi
}

fixmount_zpool () {
    send_canmount_value="`${send_ssh} zfs get -H -o value canmount ${send_zpoolfs} 2>/dev/null`"
    recv_canmount_value="`${recv_ssh} zfs get -H -o value canmount ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
    fixmount_file="/mnt/${recv_zpool}/${info_dir}/fixmount_${send_host}.sh"
    always_recv_ssh="`always_ssh_host ${recv_host}`"
    if [ "${send_canmount_value}" != "${recv_canmount_value}" ] ; then
	dryer "${always_recv_ssh} echo zfs set ${zfssetopts} canmount=${send_canmount_value} ${recv_zpoolfs}${send_zfs} >> ${fixmount_file}"
    fi
    send_mountpoint_source="`${send_ssh} zfs get -H -o source mountpoint ${send_zpoolfs} 2>/dev/null`"
    recv_mountpoint_source="`${recv_ssh} zfs get -H -o source mountpoint ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
    if [ "${send_mountpoint_source}" != "${recv_mountpoint_source}" ] ; then
        if [ "${send_mountpoint_source}" = inherited ] ; then
            dryer "${always_recv_ssh} echo zfs inherit mountpoint ${recv_zpoolfs}${send_zfs} >> ${fixmount_file}"
        else
            send_mountpoint_value="`${send_ssh} zfs get -H -o value mountpoint ${send_zpoolfs} 2>/dev/null`"
            recv_mountpoint_value="`${recv_ssh} zfs get -H -o value mountpoint ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
            if [ "${send_mountpoint_value}" != "${recv_mountpoint_value}" ] ; then
                dryer "${always_recv_ssh} echo zfs set ${zfssetopts} mountpoint=${send_mountpoint_value} ${recv_zpoolfs}${send_zfs} >> ${fixmount_file}"
            fi
        fi
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

source_mount_zpool () {
    true
}

source_umount_zpool () {
    true
}

show_import_volume_zpool () {
    if [ "`echo $*|grep ${volume}`" != "" ] ; then
	echo ${2}
    fi
}

forall_cache () {
    for cache_type in log cache ; do
        for cache in ${caches[${mediahost},${media_pool},${cache_type}]} ; do
            $*
        done
    done
}

media_delvol_zpool () {
    forall_cache \
        media_delvol_zpool_cache
}

media_delvol_zpool_cache () {
    if ${media_ssh} zpool status ${media_pool} | grep -q ${cache} ; then
        dryer ${media_ssh} zpool remove ${media_pool} crbackup_${cache}
    fi
}

media_export_zpool () {
    dryer ${media_ssh} zpool export ${media_pool}
}

media_import_volume_zpool () {
    # Note: for some reason -N doesn't work properly
    ${media_ssh} zpool import -N ${media_pool} -R /mnt/${media_pool}
}

media_addvol_zpool () {
    forall_cache \
        media_addvol_zpool_cache
}

media_addvol_zpool_cache () {
    if ! ( ${media_ssh} zpool status ${media_pool} | grep -q ${cache} ) ; then
        dryer ${media_ssh} zpool add ${media_pool} ${cache_type} crbackup_${cache}
    fi
}

get_media_import_line_zpool () {
    zopts="`for device in $(ls /dev/mapper|grep crbackup_) ; do echo -d /dev/mapper/${device} ; done`"
    echo `${media_ssh} zpool import ${zopts} 2>/dev/null`|sed 's/.pool:/\npool:/g'
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

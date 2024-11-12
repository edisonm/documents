info_dir=crbackup

snapshot_zpool () {
    snapshot=${send_pool}${send_zfs}@${snprefix}${currsnap}
    if [ "`${send_ssh} zfs list -pHt snapshot -o name ${snapshot} 2>/dev/null`" = "" ] ; then
	dryer ${send_ssh} zfs snapshot -r ${snapshot}
    fi
}

zfs_destroy () {
    ssh_snap="`ssh_host ${1}`"
    if [ "`${ssh_snap} zfs list -pHt snapshot -o name ${2} 2>/dev/null`" != "" ]; then
        ${ssh_snap} zfs destroy ${dropopts} ${2}
    fi
}

destroy_snapshot_zpool () {
    snapshot="${2}${4}@${5}"
    dryer zfs_destroy ${1} "${snapshot}"
}

sendsnap0_zpool () {
    ${send_ssh} zfs list -Ht snapshot -o name ${send_zpoolfs} 2>/dev/null | \
        sed -e "s:${send_zpoolfs}@::g" | sort -u
}

recvsnap0_zpool () {
    recvsnap0_zpool_${recv_fmt}
}

recvsnap0_zpool_clone () {
    ${recv_ssh} zfs list -Ht snapshot -o name ${recv_zpoolfs}${send_zfs} 2>/dev/null | \
        sed -e "s:${recv_zpoolfs}${send_zfs}@::g" | sort -u
}

recvsnap0_zpool_zdump () {
    ${recv_ssh} ls -p /mnt/${recv_pool}/crbackup${recv_zfs}${send_zfs} 2>/dev/null | grep -v /$ | \
        sed -e 's:.*_\(.*\)\.raw:'${snprefix}'\1:g'
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

snapshot_size_zpool () {
    size="`$send_ssh zfs send -nvPc ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} 2>/dev/null | grep size | awk '{print $2}'`"
    if [ "${size}" = "" ] ; then
	echo 0
    else
	echo ${size}
    fi
}

zfs_create_rec_clone () {
    has_recv_zpoolfs="`${recv_ssh} zfs list -Ho name ${1} 2>/dev/null`" || true
    if [ "${has_recv_zpoolfs}" = "" ] ; then
        zfs_create_rec_clone "`dirname ${1}`"
        dryer ${recv_ssh} zfs create -o mountpoint=none ${1}
        # TBD: add '-o keyformat=passphrase -o keylocation=file:///crypto_keyfile.bin' if encrypted
    fi
}

zfs_create_clone () {
    zfs_create_rec_clone ${recv_zpoolfs}
}

zfs_create_zdump () {
    has_recv_zpoolfs="`${recv_ssh} zfs list -Ho name ${recv_zpool}/BACK 2>/dev/null`" || true
    if [ "${has_recv_zpoolfs}" = "" ] ; then
        dryer ${recv_ssh} zfs create -o mountpoint=/crbackup -o canmount=on ${recv_zpool}/BACK
    fi
    dryer ${recv_ssh} mkdir -p /mnt/${recv_zpool}/crbackup${recv_zfs}${send_zfs}
}

backup_zpool_clone () {
    zfs_create_${recv_fmt}
    ( dryern ${send_ssh} zfs send -c ${sendopts} ${send_zpoolfs}@${snprefix}${currsnap} \
          | dryerpn pv -reps ${snapshot_size} \
          | dryerp ${recv_ssh} zfs recv -d -F ${recv_zpoolfs} ) || true
}

backup_zpool_zdump () {
    zfs_create_${recv_fmt}
    if [ "${send_unfolded}" = 0 ] ; then
        for send_zpoolfs in ${send_zpoolfss} ; do
            send_zfs=${send_zpoolfs##${send_zpool}} backup_zpool_zdump_1
        done
    else
        backup_zpool_zdump_1
    fi
}

backup_zpool_zdump_1 () {
    recv_dir="/mnt/${recv_zpool}/crbackup${recv_zfs}${send_zfs}"
    ${recv_ssh} mkdir -p ${recv_dir}
    backup_zpool_zdump_full `sendsnap`
}

backup_zpool_zdump_full () {
    backup_zpool_zdump_file_1 ${1}
    snapshot1=${1}
    shift
    for snapshot2 in $* ; do
        if [ $((${snapshot2}<=${currsnap})) = 1 ] ; then
            backup_zpool_zdump_file_2 ${snapshot1} ${snapshot2}
        fi
        snapshot1=${snapshot2}
    done
}

# Commented out since for incremental backups, we have to check all the
# snapshots in case an incremental backup needs to be rebuild due to the
# deletion of an intermediate snapshot:

# backup_zpool_zdump_incr () {
#     prevsnap=`prevsnap ${prevcmd}`
#     for snapshot2 in $* ; do
#         if [ $(((${prevsnap}<${snapshot2})&&(${snapshot2}<=${currsnap}))) = 1 ] ; then
#             backup_zpool_zdump_file_2 ${snapshot1} ${snapshot2}
#         fi
#         snapshot1=${snapshot2}
#     done
# }

# WARNING: Don't change prefixes full/incr, they are tweaked so that full
# appears first, before incr when using ls to get the raw files, which is
# required by the restore_job script to work properly.

backup_zpool_zdump_file_1 () {
    recv_file="${recv_dir}/full_${1}.raw"
    if ! ${recv_ssh} test -f ${recv_file} ; then
        snapshot_size="`snapshot_size_zpool_1 ${1}`"
        nodry echo "# Saving ${recv_file} (`byteconv ${snapshot_size}`)"
        ( ( dryern ${send_ssh} zfs send -c ${send_zpoolfs}@${snprefix}${1} \
                | dryerpn pv -reps ${snapshot_size} \
                | dryerp ${recv_ssh} "( cat > ${recv_file}-partial ) && mv ${recv_file}-partial ${recv_file}" ) \
              && dryer ${recv_ssh} "rm -f ${recv_dir}/full_*.raw-cleanup ${recv_dir}/incr_*_${1}.raw-cleanup" \
            ) || true
    fi
}

backup_zpool_zdump_file_2 () {
    recv_file="${recv_dir}/incr_${1}_${2}.raw"
    if ! ${recv_ssh} test -f ${recv_file} ; then
        snapshot_size="`snapshot_size_zpool_2 ${1} ${2}`"
        nodry echo "# Saving ${recv_file} (`byteconv ${snapshot_size}`)"
        ( ( dryern ${send_ssh} zfs send -c -I \
                   ${send_zpoolfs}@${snprefix}${1} \
                   ${send_zpoolfs}@${snprefix}${2} \
                | dryerpn pv -reps ${snapshot_size} \
                | dryerp ${recv_ssh} "( cat > ${recv_file}-partial ) && mv ${recv_file}-partial ${recv_file}" ) \
              && dryer ${recv_ssh} "rm -f ${recv_dir}/full_*.raw-cleanup ${recv_dir}/incr_*_${1}.raw-cleanup" \
            ) || true
    fi
}

snapshot_size_zpool_1 () {
    size="`${send_ssh} zfs send -nvPc ${send_zpoolfs}@${snprefix}${1} 2>/dev/null | grep size | awk '{print $2}'`"
    if [ "${size}" = "" ] ; then
	echo 0
    else
	echo ${size}
    fi
}

snapshot_size_zpool_2 () {
    size="`${send_ssh} zfs send -nvPc -I ${send_zpoolfs}@${snprefix}${1} ${send_zpoolfs}@${snprefix}${2} 2>/dev/null | grep size | awk '{print $2}'`"
    if [ "${size}" = "" ] ; then
	echo 0
    else
	echo ${size}
    fi
}

backup_restore_sh_zpool () {
    nodry echo "restore_job ${send_zpool} ${recv_zfs} ${send_zfs}" \
        | nodry ${recv_ssh} "cat >> /mnt/${recv_zpool}/crbackup/restore.sh"
}

zfssetopts="-u"

offmount_zpool_zdump () {
    true
}

offmount_zpool_clone () {
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

bak_info_zpool_zdump () {
    true
}

bak_info_zpool_clone () {
    has_meta_info_fs="`${media_ssh} zfs list -Ho name ${media_pool}/${info_dir} 2>/dev/null || true`"
    if [ "${has_meta_info_fs}" = "" ] ; then
        dryer ${media_ssh} zfs create ${media_pool}/${info_dir} -o canmount=on -o mountpoint=/${info_dir}
    else
        dryer ${media_ssh} rm -f "/mnt/${media_pool}/${info_dir}/fixmount_"'*'".sh"
    fi
}

fixmount_zpool_zdump () {
    true
}

fixmount_zpool_clone () {
    send_canmount_value="`${send_ssh} zfs get -H -o value canmount ${send_zpoolfs} 2>/dev/null`"
    recv_canmount_value="`${recv_ssh} zfs get -H -o value canmount ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
    fixmount_file="/mnt/${recv_zpool}/${info_dir}/fixmount_${send_host}.sh"
    if [ "${send_canmount_value}" != "${recv_canmount_value}" ] ; then
        nodry echo "zfs set ${zfssetopts} canmount=${send_canmount_value} ${recv_zpoolfs}${send_zfs}" \
	    | nodry "${recv_ssh} cat >> ${fixmount_file}"
    fi
    send_mountpoint_source="`${send_ssh} zfs get -H -o source mountpoint ${send_zpoolfs} 2>/dev/null`"
    recv_mountpoint_source="`${recv_ssh} zfs get -H -o source mountpoint ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
    if [ "${send_mountpoint_source}" != "${recv_mountpoint_source}" ] ; then
        if [ "${send_mountpoint_source}" = inherited ] ; then
            nodry echo "echo zfs inherit mountpoint ${recv_zpoolfs}${send_zfs}" \
                | nodry "${recv_ssh} cat >> ${fixmount_file}"
        else
            send_mountpoint_value="`${send_ssh} zfs get -H -o value mountpoint ${send_zpoolfs} 2>/dev/null`"
            recv_mountpoint_value="`${recv_ssh} zfs get -H -o value mountpoint ${recv_zpoolfs}${send_zfs} 2>/dev/null || true`"
            if [ "${send_mountpoint_value}" != "${recv_mountpoint_value}" ] ; then
                nodry echo "zfs set ${zfssetopts} mountpoint=${send_mountpoint_value} ${recv_zpoolfs}${send_zfs}" \
                    | nodry "${recv_ssh} cat >> ${fixmount_file}"
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
        recv_fmt=`recv_fmt ${media_pool}`
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
    ${media_ssh} zpool import -f ${media_pool} -R /mnt/${media_pool}
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
    zopts="`for device in $(${media_ssh} ls /dev/mapper|grep crbackup_) ; do echo -d /dev/mapper/${device} ; done`"
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

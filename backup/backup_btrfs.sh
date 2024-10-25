
list_bvols () {
    ${1} lsblk -o fstype,label,uuid,mountpoint|grep 'btrfs'
}

b_volpath () {
    while read -r fstype_ label uuid_ mountpoint ; do
        if [ "${2}" = "${label}" ] && ( [ "${3}" = "${uuid_}" ] || [ "${3}" = "" ] ) ; then
            echo ${mountpoint}
        fi
    done < <(list_bvols "${1}")
}

snapshot_btrfs () {
    # TODO: rename send_zfs to send_fs
    svoldir=`b_volpath "${send_ssh}" "${send_pool}" "${send_uuid}"`
    snapsub=".snapshot/${snprefix}${currsnap}"
    snapdir="${svoldir}${send_zfs}/.snapshot"
    if [ "`${send_ssh} btrfs subvolume list -o ${snapdir} 2>/dev/null|grep ${snapsub}`" = "" ] ; then
        dryer ${send_ssh} mkdir -p ${snapdir}
        dryer ${send_ssh} btrfs subvolume snapshot -r ${svoldir}${send_zfs} ${svoldir}${send_zfs}/${snapsub}
    fi
}

destroy_snapshot_btrfs () {
    ssh_snap="`ssh_host ${1}`"
    snap_pool="${2}"
    snap_uuid="${3}"
    snap_zfs="${4}"
    snapshot="${5}"
    svoldir=`b_volpath "${ssh_snap}" "${snap_pool}" "${snap_uuid}"`${snap_zfs}
    snapdir="${svoldir}/.snapshot"
    snapsub=".snapshot/${snapshot}"
    if [ "`${send_ssh} btrfs subvolume list -o ${snapdir} 2>/dev/null|grep ${snapsub}`" != "" ] ; then
        dryer ${ssh_snap} btrfs subvolume delete ${svoldir}/${snapsub}
    fi
}

sendsnap0_btrfs () {
    svoldir="`b_volpath "${send_ssh}" "${send_pool}" "${send_uuid}"`"
    snapdir="${svoldir}${send_zfs}/.snapshot"
    ${send_ssh} btrfs subvolume list -o ${snapdir} 2>/dev/null \
        | awk '{print "/"$9}' | grep "${send_zfs}/.snapshot/" | \
        sed -e "s:${send_zfs}/.snapshot/::g" | sort -u
}

recvsnap0_btrfs () {
    svoldir="`b_volpath "${recv_ssh}" "${recv_zpool}" "${recv_uuid}"`"
    snapdir="${svoldir}${recv_zfs}${send_zfs}/.snapshot"
    ${recv_ssh} btrfs subvolume list -o ${snapdir} 2>/dev/null \
        | awk '{print "/"$9}' | grep "${recv_zfs}${send_zfs}/.snapshot/" | \
        sed -e "s:${recv_zfs}${send_zfs}/.snapshot/::g" | sort -u
}

zfs_prev_btrfs () {
    sendopts=""
    $*
}

backup_btrfs () {
    svoldir="`b_volpath "${recv_ssh}" "${recv_zpool}" "${recv_uuid}"`${recv_zfs}"
    # echo snapdir=${snapdir} 1>&2
    # echo cond="`recvsnap0|grep ${currsnap}`" 1>&2
    if [ "${baktype}" = full ] ; then
        dryer ${recv_ssh} mkdir -p `dirname ${svoldir}${send_zfs}`
        dryer ${recv_ssh} btrfs subvolume create ${svoldir}${send_zfs} || true
        dryer ${recv_ssh} mkdir -p ${svoldir}${send_zfs}/.snapshot
        sendsnaps=`sendsnap`
    else
        sendsnaps=`fromsnap sendsnap ${prevsnap}`
    fi
    snapprefix=`b_volpath "${send_ssh}" "${send_pool}" "${send_uuid}"`${send_zfs}/.snapshot/${snprefix}
    psendsnap1=""
    for sendsnap in ${sendsnaps} ; do
        psendsnap=${snapprefix}${sendsnap}
        snapshot_size=`snapshot_size "${psendsnap1}" "${psendsnap}"`
        if [ "${psendsnap1}" = "" ] ; then
            if [ "${baktype}" = full ] ; then
                ( dryern $send_ssh btrfs send ${psendsnap} \
                      | dryerpn pv -reps ${snapshot_size} \
                      | dryerp ${recv_ssh} btrfs receive ${svoldir}${send_zfs}/.snapshot ) || true
            fi
        else
            ( dryern $send_ssh btrfs send -c ${psendsnap1} ${psendsnap} \
                  | dryerpn pv -reps ${snapshot_size} \
                  | dryerp ${recv_ssh} btrfs receive ${svoldir}${send_zfs}/.snapshot ) || true
        fi
        psendsnap1=${psendsnap}
    done
}

set_sendopts_btrfs () {
    sendopts="-c"
}

forall_mediapools_btrfs () {
    while read -r fstype_ media_pool path uuid ; do
        $* < /dev/null
    done < <(${media_ssh} lsblk -o fstype,label,path,uuid|grep btrfs)
}

match_volume () {
    for match in $* ; do
        if [ "`echo ${match}|grep ${volume}`" != "" ] ; then
            echo ${volume}
        fi
    done
}

if_removable_media_btrfs () {
    if [ "`forall_volumes match_volume ${path} ${uuid}`" != "" ] ; then
        $*
    fi
}

recv_size_btrfs () {
    svoldir="`b_volpath "${recv_ssh}" "${recv_zpool}" "${recv_uuid}"`"
    ${recv_ssh} df -B1 --output=avail ${svoldir}|sed 1d
}

recv_volume_btrfs () {
    if [ "${media_pool}" = "${recv_pools[${recv_hostpool}]}" ] ; then
        forall_volumes \
            match_volume ${path} ${uuid}
    fi
}

recv_volumes_btrfs () {
    forall_mediahosts \
        forall_mediapools_btrfs \
        recv_volume_btrfs
}

source_mount_btrfs () {
    while read -r fstype_ label uuid mountpoint ; do
        if [ "$mountpoint" != "/mnt/btrfs/${label}" ] \
               && [ "${send_pool}" = "${label}" ] ; then
            ${send_ssh} mkdir -p /mnt/btrfs/${label}
            ${send_ssh} mount UUID=$uuid /mnt/btrfs/${label}
        fi
    done < <(list_bvols "${send_ssh}")
}

source_umount_btrfs () {
    while read -r fstype_ label uuid mountpoint ; do
        if [ "$mountpoint" = "/mnt/btrfs/${label}" ] \
               && [ "${2}" = "${label}" ] ; then
            dryer ${send_ssh} umount /mnt/btrfs/${label}
            dryer ${send_ssh} rmdir  /mnt/btrfs/${label}
        fi
    done < <(list_bvols "${1}")
}

media_export_btrfs () {
    source_umount_btrfs "${media_ssh}" "${media_pool}"
}

snapshot_size_btrfs () {
    echo 0
}

show_import_volume_btrfs () {
    label=${2}
    uuid=${3}
    mountpoint=${4}
    if [ "${volume}" = "${uuid}" ] ; then
        if [ "${mountpoint}" = "" ] ; then
	    echo ${label} ${uuid}
	fi
    fi
}
media_import_volume_btrfs () {
    label=${1}
    uuid=${2}
    ${media_ssh} mkdir -p /mnt/btrfs/${label}
    ${media_ssh} mount UUID=${uuid} /mnt/btrfs/${label}
}

media_addvol_btrfs () {
    true
}

media_import_line_btrfs () {
    list_bvols "${media_ssh}"
}

media_umount_btrfs () {
    while read -r fstype label uuid mountpoint ; do
        if [ "$mountpoint" = "/mnt/btrfs/${label}" ] ; then
            dryer ${media_ssh} umount /mnt/btrfs/${label}
            dryer ${media_ssh} rmdir /mnt/btrfs/${label}
        fi
    done < <(list_bvols "${media_ssh}")
}

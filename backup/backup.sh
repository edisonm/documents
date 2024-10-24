#!/bin/bash

set -e

LC_NUMERIC=C

#   Script for automated backups via zfs and btrfs

#   Author:        Edison Mera
#   E-mail:        mail@edisonm.com
#   Copyright (C):  2021, Process  Design Center,  Breda, The  Netherlands.  All
#   rights reserved.

#   Redistribution  and  use  in  source  and  binary  forms,  with  or  without
#   modification, are permitted provided that the following conditions are met:

#   1. Redistributions  of source code  must retain the above  copyright notice,
#      this list of conditions and the following disclaimer.

#   2. Redistributions in binary form must reproduce the above copyright notice,
#      this list of conditions and the following disclaimer in the documentation
#      and/or other materials provided with the distribution.

#   THIS SOFTWARE IS PROVIDED BY THE  COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#   AND ANY  EXPRESS OR IMPLIED WARRANTIES,  INCLUDING, BUT NOT LIMITED  TO, THE
#   IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR  A PARTICULAR PURPOSE
#   ARE DISCLAIMED.   IN NO EVENT SHALL  THE COPYRIGHT OWNER OR  CONTRIBUTORS BE
#   LIABLE  FOR  ANY  DIRECT,   INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
#   CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT  LIMITED  TO,  PROCUREMENT  OF
#   SUBSTITUTE GOODS  OR SERVICES; LOSS  OF USE,  DATA, OR PROFITS;  OR BUSINESS
#   INTERRUPTION)  HOWEVER CAUSED  AND ON  ANY THEORY  OF LIABILITY,  WHETHER IN
#   CONTRACT,  STRICT LIABILITY,  OR  TORT (INCLUDING  NEGLIGENCE OR  OTHERWISE)
#   ARISING IN ANY WAY  OUT OF THE USE OF THIS SOFTWARE, EVEN  IF ADVISED OF THE
#   POSSIBILITY OF SUCH DAMAGE.

# The file ./settings_`hostname`.sh must define the next configuration parameters:
#
# - A variable called volumes which contains a list of the UUID of all the
#   luks encrypted backup meda
#
# - A variable called backjobs that returns a list of semi-colon delimited rows
#   with the next columns:
#
#   send_host;backend;send_pool;send_zfs;recv_host;recv_pool;recv_zfs
#
#   Where:
#
#   send_host: hostname where the sender resides. Empty means localhost.
#
#   backend: specifies the filesystem type, can be zpool (stable) or btrfs (in development)
#
#   send_pool: sender zpool. Empty means is a removable media.
#
#   send_zfs: path of the sender zfs filesystem
#
#   recv_host: hostname where the receiver will reside. Empty means localhost
#
#   recv_pool: receiver zpool. Empty means is a removable media
#
#   recv_zfs: path of the receiver zfs filesystem. If empty and
#   send_host is not empty, then /send_host/send_pool will be used
#
#   Note that we can not reuse the same target path (target_zfs),
#   otherwise each backjob will overwrite the previous one.

# - Optionally, a variable called dropsnaps, which lists the snapshots to be
#   deleted in the next execution of the script.

#   Suggestion: To speed up ssh you should consider to setup your ~/.ssh/config
#   to use ControlMaster and ControlPath, for example:

# Host myhostname
#      ...
#      ControlMaster auto
#      ControlPath ~/.ssh/master-%r%h:%p
#      ControlPersist 30

. ./settings_`hostname`.sh
. ./common.sh

hostname=${hostname:-`hostname`}

. ./backup_zpool.sh
. ./backup_btrfs.sh

# max_frequency=daily
# max_frequency=minute
max_frequency=hourly

# Snapshots with this prefix will be handled by this script:
snprefix=_bak_

# max one snapshot per day:
if [ "$max_frequency" = daily ] ; then
    currsnap=${currsnap:-"`date +%y%m%d`"}
fi

# max one snapshot per hour:
if [ "$max_frequency" = hourly ] ; then
    currsnap=${currsnap:-"`date +%y%m%d%H`"}
fi

# max one snapshot per minute (not recommended for production):
if [ "$max_frequency" = minute ] ; then
    currsnap=${currsnap:-"`date +%y%m%d%H%M`"}
fi

match_backup_snapshot_daily () {
    awk 'match($0,/^'"${snprefix}"'[0-9][0-9](0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])$/){print $0}'
}

match_backup_snapshot_hourly () {
    awk 'match($0,/^'"${snprefix}"'[0-9][0-9](0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])([0-1][0-9]|2[0-3])$/){print $0}'
}

match_backup_snapshot_minute () {
    awk 'match($0,/^'"${snprefix}"'[0-9][0-9](0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])([0-1][0-9]|2[0-3])[0-5][0-9]$/){print $0}'
}

match_backup_snapshot () {
    match_backup_snapshot_${max_frequency} $*
}

ssh_host () {
    if [ "$1" != "" ] \
           && [ "$1" != "${hostname}" ] \
           && [ "$1" != localhost ] ; then
        echo "ssh $1"
    fi
}

# always use ssh, to avoid odd behaviors
always_ssh_host () {
    if [ "$1" = "" ] ; then
        echo "ssh ${hostname}"
    else
        echo "ssh $1"
    fi
}

list_backjobs () {
    for backjobrow in ${backjobs} ; do
        echo "${backjobrow}"
    done
}

list_volumes () {
    for volumerow in ${volumes} ; do
        echo ${volumerow}
    done
}

list_caches () {
    for cache in ${caches[*]} ; do
        echo ${cache}
    done
}

test_backjobs_loop () {
    echo send_host=${send_host} \
         send_pool=${send_pool} \
         send_zpool=${send_zpool} \
         send_zfs=${send_zfs} \
         recv_host=${recv_host} \
         recv_pool=${recv_pool} \
         recv_zpool=${recv_zpool} \
         recv_zfs=${recv_zfs}
}

test_backjobs () {
    forall_backjobs \
        forall_recv \
        test_backjobs_loop
}

avail_ssh () {
    do_ssh=`ssh_host ${1}`
    ${do_ssh} echo 1 2>/dev/null < /dev/null || echo 0
}

forall_backjobs () {
    recv_host=""
    while IFS=';' read -r send_host fstype send_pool_uuid send_zfs recv_host recv_pool_uuid recv_zfs_ ; do
        send_pool=${send_pool_uuid%@*}
        temp_uuid=${send_pool_uuid##${send_pool}}
        send_uuid=${temp_uuid##@}
        send_zpool=${send_pool}
        send_zpoolfs=${send_zpool}${send_zfs}
        send_host=${send_host}
        send_ssh="`ssh_host ${send_host}`"
        recv_pool=${recv_pool_uuid%@*}
        temp_uuid=${recv_pool_uuid##${recv_pool}}
        recv_uuid=${temp_uuid##@}
	
	if [ "${recv_zfs_}" = "" ] && [ "${send_host}" != "" ] && [ "${send_host}" != "localhost" ]; then
	    recv_zfs="/${send_host}/${send_pool}"
	fi
	
        if [ "`avail_ssh ${send_host}`" = 1 ] ; then
            $* < /dev/null
        fi
    done < <(list_backjobs)
}

media_host_pool () {
    echo ${mediahost}:${media_pool}
}

media_host_pools () {
    fstype=${1}
    forall_mediahosts \
        forall_medias \
        media_host_pool
}

declare -A media_host_pools

forall_recv () {
    if [ "${recv_pool}" = "" ] || [ "${recv_host}" = "" ] ; then
        media_host_pools[${fstype}]="${media_host_pools[${fstype}]:-`media_host_pools ${fstype}`}"
        for recv_host_pool in ${media_host_pools[${fstype}]} ; do
            recv_host=${recv_host_pool%:*}
	    recv_pool=${recv_host_pool##*:}
            recv_zpool=${recv_host_pool##*:}
            recv_zpoolfs=${recv_zpool}${recv_zfs}
            recv_ssh="`ssh_host ${recv_host}`"
            if [ "`avail_ssh ${recv_host}`" = 1 ] ; then
                $* < /dev/null
            fi
        done
    else
        recv_zpool=${recv_pool}
	recv_zpoolfs=${recv_zpool}${recv_zfs}
        recv_ssh="`ssh_host ${recv_host}`"
        if [ "`avail_ssh ${recv_host}`" = 1 ] ; then
            $* < /dev/null
        fi
    fi
}

forall_volumes () {
    while IFS=';' read -r volume ; do
        $* < /dev/null
    done < <(list_volumes)
}

forall_caches () {
    while IFS=';' read -r volume ; do
        $* < /dev/null
    done < <(list_caches)
}

online_mediahosts () {
    for mediahostrow in ${mediahosts} ; do
        mh_ssh="`ssh_host ${mediahostrow}`"
        ${mh_ssh} echo ${mediahostrow} 2>/dev/null || true
    done
}

mediahosts=`online_mediahosts`

list_mediahosts () {
    for mediahostrow in ${mediahosts} ; do
        echo ${mediahostrow}
    done
}

test_mediahost () {
    echo mediahost=${mediahost:-localhost}
}

forall_zjobs () {
    forall_backjobs \
        forall_recv \
        zfs_prev \
        listsnap $*
}

forall_mediahosts () {
    while IFS=';' read -r mediahost ; do
        media_ssh="`ssh_host ${mediahost}`"
        if [ "`avail_ssh ${mediahost}`" = 1 ] ; then
            $* < /dev/null
        fi
    done < <(list_mediahosts)
}

forall_fstype () {
    for fstype in btrfs zpool ; do
        $*
    done
}

forall_medias () {
    forall_mediapools_${fstype} \
        if_removable_media_${fstype} $*
}

snapshot () {
    snapshot_${fstype}
}

snapshots_help () {
    cat <<EOF
$0 snapshots
Creates snapshots on the source file systems

EOF
}

snapshots () {
    forall_backjobs \
        snapshot
}

destroy_snapshot () {
    destroy_snapshot_${fstype} "$@"
}

destroy_send_dropsnap () {
    for dropsnap in $* ; do
        destroy_snapshot "${send_host}" "${send_zpool}" "${send_uuid}" "${send_zfs}" "${snprefix}${dropsnap}"
    done
}

destroy_recv_dropsnap () {
    for dropsnap in $* ; do
        destroy_snapshot "${recv_host}" "${recv_zpool}" "${recv_uuid}" "${recv_zfs}${send_zfs}" "${snprefix}${dropsnap}"
    done
}

dropsnaps () {
    dropsnaps=${dropsnaps:-${1}}
    # Note: duplicated calls are handled by destroy_snapshot, so don't try to
    # optimize this here
    dropopts="-r"
    forall_backjobs \
        destroy_send_dropsnap ${dropsnaps}

    forall_backjobs \
        forall_recv \
        destroy_recv_dropsnap ${dropsnaps}
}

exec_smartretp () {
    if [ "${smartretp}" = 1 ] ; then
        forall_backjobs \
            destroy_send_recv_smartretp
    fi
}

destroy_send_recv_smartretp () {
    prev_unfold=${send_unfold}
    send_unfold=1
    zfs_prev \
        sendsnap \
        destroy_send_smartretp

    forall_recv \
        destroy_recv_smartretp
    send_unfold=${prev_unfold}
}

destroy_recv_smartretp () {
    # Next command means: don't delete prevsnap, currsnap, and last 2
    recvsnap="`recvsnap|head -n -2`"
    # Next command means: don't delete last 2 dropables
    recv_dropsnaps=`smartretp "${recvsnap}"|head -n -2`
    destroy_recv_dropsnap ${recv_dropsnaps} ${dropsnaps}
}

destroy_send_smartretp () {
    sendsnap="`sendsnap|head -n -2`"
    send_dropsnaps=`smartretp "${sendsnap}"|head -n -2`
    destroy_send_dropsnap ${send_dropsnaps} ${dropsnaps}
}

sendsnap () {
    sendsnap0|match_backup_snapshot|sed -e s/${snprefix}//g|sort -u
}

sendsnap0 () {
    sendsnap0_${fstype}
}

recvsnap () {
    recvsnap0|match_backup_snapshot|sed -e s/${snprefix}//g|sort -u
}

recvsnap0 () {
    # redefine send_zfs in case send_zpoolfs has been redefined
    send_zfs=${send_zpoolfs##${send_zpool}}
    recvsnap0_${fstype}
}

addprefix () {
    prefix=$1
    shift
    for elem in $*; do
        echo ${prefix}${elem}
    done
}

listsnap () {
    comm -12 <(sendsnap) <(recvsnap)
}

prevsnap () {
    prevsnap=""
    for snapshot in `$1` ; do
        if [ $((${snapshot}<${currsnap})) = 1 ] ; then
            prevsnap=${snapshot}
        fi
    done
    echo $prevsnap
}

between () {
    snapshots=`$1`
    lowersnap=$2
    uppersnap=$3
    for snapshot in ${snapshots} ; do
        if [ $((${lowersnap}<=${snapshot##${snprefix}})) = 1 ] \
               && [ $((${snapshot##${snprefix}}<=${uppersnap})) = 1 ] ; then
            echo ${snapshot}
        fi
    done
}

fromsnap () {
    snapshots=`$1`
    lowersnap=$2
    for snapshot in ${snapshots} ; do
        if [ $((${lowersnap##${snprefix}}<=${snapshot##${snprefix}})) = 1 ] ; then
            echo ${snapshot}
        fi
    done
}

snapshot_size () {
    snapshot_size_${fstype}
}

zfs_prev () {
    send_zpoolfs=${send_zpool}${send_zfs}
    prevcmd="$1"
    shift
    prevsnap=`prevsnap ${prevcmd}`
    zfs_prev_${fstype} $*
}

zfs_wrapr () {
    # hasprevs="`${recv_ssh} zfs list -Ho name ${recv_zpoolfs}${send_zfs}@${prevsnap}`"
    # echo hasprevs="`recvsnap|grep "${prevsnap}"`" 1>&2
    # echo prevsnap="${prevsnap}" 1>&2
    if [ "${prevsnap}" = "" ] || [ "`recvsnap|grep "${prevsnap}"`" = "" ] ; then
        action="# first full backup ${currsnap}"
        baktype=full
    else
        action="# incremental backup ${prevsnap}-${currsnap}"
        set_sendopts_${fstype}
        baktype=incr
    fi
    $*
}

requires_unfold () {
    unfold=0
    for send_zpoolfs in ${send_zpoolfss} ; do
        case $1 in
            listsnap)
                if [ "`sendsnap|grep ${prevsnap}`" = "" ] \
                       || [ "`recvsnap|grep ${prevsnap}`" = "" ] ; then
                    unfold=1
                fi
            ;;
            *)
                if [ "`${1}|grep ${prevsnap}`" = "" ] ; then
                    unfold=1
                fi
            ;;
        esac
    done
    echo $unfold
}

skip_eq_sendrecv () {
    if [ "${send_host}:${send_zpoolfs}" != "${recv_host}:${recv_zpoolfs}${send_zfs}" ] ; then
        $*
    fi
}

update_fields () {
    field1="${send_host}:${send_zpoolfs}"
    field1_maxw=$((${field1_maxw}>${#field1}?${field1_maxw}:${#field1}))
}

declare -A send_recv
declare -A width
declare -A recv_size

update_size () {
    recv_size[${recv_hostpool}]=`recv_size`
    if [ "${send_host}:${send_zpoolfs}" != "${recv_host}:${recv_zpoolfs}${send_zfs}" ] ; then
        send_recv[${send_hostpoolfs},${recv_hostpool}]="`snapshot_size`"
    else
        send_recv[${send_hostpoolfs},${recv_hostpool}]="-"
    fi
    update_fields
}

recv_size () {
    recv_size_${fstype}
}

repeatc () {
    for ((i=0;i<$1;i++)) ; do
        printf "%s" $2
    done
}

lmax () {
    echo $((${#1}>${#2}?${#1}:${#2}))
}

set_send_hostpoolsfs () {
    send_hostpoolfs="${send_host}:${send_zpoolfs}"
    send_hosts[${send_hostpoolfs}]=${send_host}
    send_poolsfs[${send_hostpoolfs}]=${send_zpoolfs}
    $*
}

declare -A units
units[0]=""
units[1]="K"
units[2]="M"
units[3]="G"
units[4]="T"
units[5]="E"

byteconv_rec () {
    value=$1
    vunit=$2
    if [ $((${value}>1024000)) != 0 ] && [ ${vunit} != 6 ] ; then
        vunit=$((${vunit}+1))
        value=$(((${value}+512)/1024))
        byteconv_rec $value $vunit
    else
        ipart=$((${value}/1000))
        fpart=`printf "%03g" $((${value}%1000))`
        printf "%.3g%s\n" ${ipart}.${fpart} ${units[${vunit}]}
    fi
}

byteconv () {
    if [ "${1}" != "" ] ; then
        byteconv_rec $((${1}*1000)) 0
    fi
}

statistics () {
    total_size=0
    field1_maxw=6
    
    unset recv_hosts
    declare -A recv_hosts
    unset recv_pools
    declare -A recv_pools
    unset recv_fstype
    declare -A recv_fstype
    unset rsnapshots
    declare -A rsnapshots
    unset recv_stot
    declare -A recv_stot
    unset width
    declare -A width
    unset send_hosts
    declare -A send_hosts
    unset send_poolsfs
    declare -A send_poolsfs
    
    forall_zjobs \
        zfs_wrapr \
        set_send_hostpoolsfs \
        set_recv_hostpools \
        update_size

    printf "%-*s" ${field1_maxw} "Source"
    
    for recv_hostpool in ${!recv_hosts[*]} ; do
        width[${recv_hostpool}]=`lmax ${recv_size[${recv_hostpool}]} ${recv_hostpool}`
        printf " %*s" ${width[${recv_hostpool}]} ${recv_hostpool}
        recv_stot[${recv_hostpool}]=0
    done
    printf "\n"

    printf "%s" `repeatc ${field1_maxw} -`
    
    for recv_hostpool in ${!recv_hosts[*]} ; do
        printf " %s" `repeatc ${width[${recv_hostpool}]} -`
    done
    printf "\n"

    send_total=0
    for send_hostpoolfs in ${!send_hosts[*]} ; do
        printf "%-*s" ${field1_maxw} ${send_hostpoolfs}
        for recv_hostpool in ${!recv_hosts[*]} ; do
            printf " %*s" ${width[${recv_hostpool}]} "`byteconv ${send_recv[${send_hostpoolfs},${recv_hostpool}]}`"
            if [ "${send_recv[${send_hostpoolfs},${recv_hostpool}]}" != "-" ] ; then
                recv_stot[${recv_hostpool}]=$((${send_recv[${send_hostpoolfs},${recv_hostpool}]}+${recv_stot[${recv_hostpool}]}))
            fi
        done
        printf "\n"
    done

    printf "%s" `repeatc ${field1_maxw} -`
    
    for recv_hostpool in ${!recv_hosts[*]} ; do
        printf " %s" `repeatc ${width[${recv_hostpool}]} -`
    done
    printf "\n"

    printf "%-*s" ${field1_maxw} "Total"
    for recv_hostpool in ${!recv_hosts[*]} ; do
        printf " %*s" ${width[${recv_hostpool}]} "`byteconv ${recv_stot[${recv_hostpool}]}`"
    done
    printf "\n"

    overflow=0
    printf "%-*s" ${field1_maxw} "Free"
    for recv_hostpool in ${!recv_hosts[*]} ; do
        printf " %*s" ${width[${recv_hostpool}]} "`byteconv ${recv_size[${recv_hostpool}]}`"
        overflow=$((${overflow} || (${recv_stot[${recv_hostpool}]} > ${recv_size[${recv_hostpool}]})))
    done
    printf "\n"

    if [ ${overflow} != 0 ] ; then
        recv_err=""
        printf "%-*s" ${field1_maxw} "ERROR"
        for recv_hostpool in ${!recv_hosts[*]} ; do
            if [ $((${recv_stot[${recv_hostpool}]} > ${recv_size[${recv_hostpool}]})) != 0 ] ; then
                msg="KO"
                recv_err="${recv_err} ${recv_hostpool}"
            else
                msg="OK"
            fi
            printf " %*s" "${width[${recv_hostpool}]}" "${msg}"
        done
        printf "\n"
        echo "ERROR: Data to be copied will not fit on:$recv_err"
        if [ "${dryrun}" = 0 ] ; then
            exit 1
        fi
    fi
    printf "\n"
    # List the pools to see the current status
    forall_mediahosts \
        zpool_list
    printf "\n"
}

zpool_list () {
    echo "Volumes on ${mediahost}"
    echo "zpool:"
    ( ${media_ssh} zpool list ) || true
    echo "btrfs:"
    ( ${media_ssh} lsblk -f|grep -v zd|grep btrfs ) || true
}

backup () {
    if [ "`recvsnap|grep ${currsnap}`" = "" ] ; then
        snapshot_size=`snapshot_size`
        echo "$action ${send_host}:${send_zpoolfs} to ${recv_host}:${recv_zpoolfs} (`byteconv ${snapshot_size}`)"
        backup_${fstype}
	if [ "${send_unfolded}" = 0 ] ; then
	    for send_zpoolfs in ${send_zpoolfss} ; do
		# prevsnap=`prevsnap ${prevcmd}`
		# sendopts="-R"
		# dropopts=""
		send_zfs=${send_zpoolfs##${send_zpool}} offmount_${fstype}
            done
	else
	    offmount_${fstype}
	fi
    fi
}

backups () {
    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        backup
}

offmount () {
    offmount_${fstype}
}

offmounts () {
    prev_unfold=${send_unfold}
    send_unfold=1
    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        offmount
    send_unfold=${prev_unfold}
}

fixmount () {
    fixmount_${fstype}
}

bak_info () {
    bak_info_${fstype}
}

bak_infos () {
    forall_fstype \
        forall_mediahosts \
        forall_medias \
        bak_info
}

fixmounts () {
    prev_unfold=${send_unfold}
    send_unfold=1
    rm -f data/fixmount_*.sh
    
    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        fixmount
    send_unfold=${prev_unfold}
}

lambda () {
    cmd=$*
    $cmd
}

crypt_open () {
    if [ "`${media_ssh} lsblk -o fstype,uuid|grep crypto_LUKS|awk '{print $2}'|grep ${volume}`" = "${volume}" ] \
           && ! ( ${media_ssh} test -e /dev/mapper/crbackup_${volume} ) ; then
        cat /crypto_keyfile.bin | \
            ${media_ssh} cryptsetup luksOpen UUID=$volume crbackup_${volume} --key-file -
    fi
}

connect_help () {
    cat <<EOF
$0 connect
Decrypt the medias and open the zfs pools that they contain

EOF
}

connect () {
    forall_mediahosts \
        connect_medias
    forall_backjobs \
        source_mount
}

connect_medias () {
    forall_volumes \
        crypt_open
    forall_caches \
        crypt_open
    forall_fstype \
        media_import
}

mark_already_imported () {
    if [ "${filtered}" = "${media_pool}" ] ; then
        already_imported=1
    fi
}

media_import () {
    while read -r line ; do
	while read -r filtered ; do
	    already_imported=0
	    forall_mediapools_${fstype} mark_already_imported
	    if [ "${already_imported}" = 0 ] ; then
                media_pool=${filtered}
		media_import_volume_${fstype}
	    fi
	done < <(forall_volumes show_import_volume_${fstype} ${line}|sort -u)
    done < <(media_import_line_${fstype})
    
    forall_mediapools_${fstype} media_addvol_${fstype}
}

source_mount () {
    source_mount_${fstype}
}

source_umount () {
    source_umount_${fstype} "${send_ssh}" "${send_pool}"
}

crypt_close () {
    if ${media_ssh} test -e /dev/mapper/crbackup_${volume} ; then
        dryer ${media_ssh} cryptsetup luksClose crbackup_${volume}
    fi
}

disconnect () {
    forall_mediahosts \
        disconnect_medias
    forall_backjobs \
        source_umount
}

disconnect_medias () {
    media_umount_btrfs
    forall_fstype \
        forall_medias \
        media_export
    forall_volumes \
        crypt_close
    forall_caches \
        crypt_close
}

media_export () {
    media_delvol_${fstype}
    media_export_${fstype}
}

set_recv_hostpools () {
    recv_hostpool="${recv_host}:${recv_zpool}"
    recv_hosts[${recv_hostpool}]=${recv_host}
    recv_pools[${recv_hostpool}]=${recv_zpool}
    recv_fstype[${recv_hostpool}]=${fstype}
    $*
}

update_log () {
    rsnapshots[${recv_hostpool}]="`( for rsnapshot in ${rsnapshots[${recv_hostpool}]} ; do \
                                       echo ${rsnapshot} ; \
                                     done ; recvsnap ) | sort -u`"
}

recv_volumes () {
    recv_volumes_${fstype}
}

backup_log () {
    zrin=0
    unset recv_hosts
    declare -A recv_hosts
    unset recv_pools
    declare -A recv_pools
    unset recv_fstype
    declare -A recv_fstype
    unset rsnapshots
    declare -A rsnapshots
    forall_zjobs \
        set_recv_hostpools \
        update_log
    for recv_hostpool in ${!recv_hosts[*]} ; do
        recv_ssh=`ssh_host ${recv_hosts[${recv_hostpool}]}`
        recv_zpool=${recv_pools[${recv_hostpool}]}
        fstype=${recv_fstype[${recv_hostpool}]}
        for volume in `recv_volumes` ; do
            echo "${recv_hosts[${recv_hostpool}]}:${recv_pools[${recv_hostpool}]}" > data/${volume}.dat
        done
        hostpool_file=data/${recv_hosts[${recv_hostpool}]}_${recv_pools[${recv_hostpool}]}.dat
        rm -f ${hostpool_file}
        touch ${hostpool_file}
        for rsnapshot in ${rsnapshots[${recv_hostpool}]} ; do
            echo ${rsnapshot} >> ${hostpool_file}
        done
    done
}

fixed_host_pool () {
    if [ "${recv_pool}" != "" ] && [ "${recv_host}" != "" ] ; then
        echo ${recv_host}:${recv_pool}
    fi
}

volume_host_pools () {
    forall_volumes \
        volume_host_pool
}

fixed_host_pools () {
    forall_backjobs \
        fixed_host_pool
}

recv_host_pools () {
    volume_host_pools
    fixed_host_pools
}

volume_host_pool () {
    if [ -f data/${volume}.dat ] ; then
        cat data/${volume}.dat
    fi
}

send_snapshots () {
    forall_backjobs \
        zfs_prev sendsnap sendsnap
}

# received collects all, including past snapshots (from data/*.dat), which is
# more comprehensive than just recv_snapshots ()

received_snapshots () {
    while IFS=':' read -r recv_host recv_pool ; do
        if [ -f data/${recv_host}_${recv_pool}.dat ] ; then
            cat data/${recv_host}_${recv_pool}.dat | match_backup_snapshot
        fi
    done < <(recv_host_pools|sort -u)
}

# recv_snapshots () {
#     forall_zjobs \
#         recvsnap
# }

declare -A send_snapshots

update_send_pool () {
    if [ "${send_pool}" != "" ] ; then
        send_snapshots["${send_host}:${send_zpoolfs}"]="`sendsnap`"
    fi
}

show_history_help () {
    cat <<EOF
$0 show_history
Shows previous backups done, including offline removable medias

EOF
}

last () {
    shift $(($#-1))
    echo $1
}

show_history () {
    zsid=0
    forall_backjobs \
        zfs_prev sendsnap \
        update_send_pool
    
    printf "No|Sources\n--+-------\n"
    zsid=0
    send_hostpoolfss=`for w in ${!send_snapshots[*]} ; do echo $w; done|sort -u`
    for send_hostpoolfs in ${send_hostpoolfss} ; do
        printf "%2s|%s\n" "${zsid}" "${send_hostpoolfs}"
	zsid=$((${zsid}+1))
    done
    zsin=${zsid}
    recv_host_pools="`recv_host_pools|sort -u`"
    zrid=0
    printf "\nNo|Targets\n--+-------\n"
    for recv_host_pool in $recv_host_pools ; do
        printf "%2s|%s\n" "${zrid}" "${recv_host_pool}"
        zrid=$((${zrid}+1))
    done
    zrin=${zrid}

    printf "\n%-*s|" `lmax snapshot ${currsnap}` "Snapshot"
    printf "%-*s" "$((2*$zsin-1))" "Srcs"
    printf "|"
    printf "%s\n" "Targets"
    
    printf "%-*s|" `lmax Snapshot ${currsnap}` "[${snprefix}]"

    for ((zsid=0;zsid<$((${zsin}-1));zsid++)) ; do
        printf "%-2s" "${zsid}"
    done
    printf "%-1s|" $((${zsin}-1))
    
    for ((zrid=0;zrid<$((${zrin}-1));zrid++)) ; do
        printf "%-2s" "${zrid}"
    done
    printf "%1s\n" $((${zrin}-1))

    printf "%-8s" "--------"
    for ((zsid=0;zsid<$((${zsin}+${zrin}));zsid++)) ; do
        printf "%s" "+-"
    done
    
    printf "\n"
    for curr_snapshot in `(send_snapshots;received_snapshots)|sort -u` ; do
        printf "%-*s|" `lmax snapshot ${currsnap}` ${curr_snapshot##${snprefix}}
	last_send_hostpoolfs="`last ${send_hostpoolfss}`"
        for send_hostpoolfs in ${send_hostpoolfss} ; do
            if [ "`for snapshot in ${send_snapshots[${send_hostpoolfs}]} ; do \
                       echo ${snapshot} ; \
                   done \
                 | grep ${curr_snapshot}`" != "" ] ; then
                volume_stat="X"
                for dropsnap in ${send_dropsnaps} ${dropsnaps} ; do
                    if [ "${dropsnap}" = "${curr_snapshot}" ] ; then
                        volume_stat="D"
                    fi
                done
            else
                volume_stat="-"
            fi
	    if [ "${last_send_hostpoolfs}" = "${send_hostpoolfs}" ] ; then
		printf "%-1s" "${volume_stat}"
	    else
		printf "%-2s" "${volume_stat}"
	    fi
        done
        printf "|"
	last_recv_host_pool="`last ${recv_host_pools}`"
        for recv_host_pool in ${recv_host_pools} ; do
            recv_host=${recv_host_pool%:*}
            recv_pool=${recv_host_pool##*:}
            if [ "`cat data/${recv_host}_${recv_pool}.dat|grep "${curr_snapshot}"`" != "" ] ; then
                volume_stat="X"
                for dropsnap in ${recv_dropsnaps} ${dropsnaps} ; do
                    if [ "${dropsnap}" = "${curr_snapshot}" ] ; then
                        volume_stat="D"
                    fi
                done
            else
                volume_stat="-"
            fi
	    if [ "${last_recv_host_pool}" = "${recv_host_pool}" ] ; then
		printf "%-1s" "${volume_stat}"
	    else
		printf "%-2s" "${volume_stat}"
	    fi
        done
        printf "\n"
    done
    printf "\n"
    echo "Note: X=present, D=to be deleted, -=not present"
    printf "\n"
}

dryrun () {
    olddry=$dryrun
    dryrun=1
    echo "Note: dryrun, execute the next command to do the real stuff:"
    echo $0 $*
    echo
    main $*
    dryrun=$olddry
}

echorun () {
    olddry=$dryrun
    dryrun=2
    main $*
    dryrun=$olddry
}

hotrun () {
    olddry=$dryrun
    dryrun=0
    main $*
    dryrun=$olddry
}

do_send_snapshot () {
    for snapshot in `sendsnap` ; do
        zpoolfs=${send_zpoolfs}
        snap_ssh="${send_ssh}"
        $*
    done
}

do_recv_snapshot () {
    for snapshot in `recvsnap` ; do
        zpoolfs=${recv_zpoolfs}${send_zfs}
        snap_ssh="${recv_ssh}"
        $*
    done
}

forall_snapshots () {
    forall_backjobs \
        zfs_prev sendsnap \
        do_send_snapshot $*
    forall_backjobs \
        forall_recv \
        zfs_prev recvsnap \
        do_recv_snapshot $*
}

rename_snapshot_to_hourly () {
    dryer ${snap_ssh} zfs rename -r ${zpoolfs}@${snprefix}${snapshot} ${snprefix}${snapshot}00
}

move_daily_to_hourly () {
    forall_snapshots \
        rename_snapshot_to_hourly
}

migrate_snapshot () {
    dryer ${snap_ssh} zfs rename -r ${zpoolfs}@${snprefix}${snapshot} ${cuprefix}${snapshot}00
}

migrate_snapshots () {
    cuprefix=${snprefix}
    snprefix=""
    max_frequency=daily
    currsnap="`date +%y%m%d`"
    forall_snapshots \
        migrate_snapshot
}

add_prefix_snapshot () {
    dryer ${snap_ssh} zfs rename -r ${zpoolfs}@${snprefix}${snapshot} ${1}${snapshot}
}

del_prefix_snapshot () {
    dryer ${snap_ssh} zfs rename -r ${zpoolfs}@${snprefix}${snapshot} ${snapshot##${1}}
}

add_prefix_snapshots () {
    forall_snapshots \
        add_prefix_snapshot $*
}

del_prefix_snapshots () {
    forall_snapshots \
        del_prefix_snapshot $*
}

dump_snapshot () {
    echo ${snapshot}
}

dump_snapshots () {
    forall_snapshots \
        dump_snapshot \
        | grep -v ${currsnap} \
        | sort -u
}

declare -A per_h
declare -A per_d
declare -A per_w
declare -A per_m
declare -A per_y

# 1 backup per hour  for 1 day,
# 1 backup per day   for 1 week,
# 1 backup per week  for 1 month,
# 1 backup per month for 1 year,
# 1 backup per year forever

smartretp () {
    curr_timestamp=`date '+%s'`
    for snapshot in $1 ; do
        # yymmddHHMM
        yy=${snapshot%[0-9][0-9][0-9][0-9][0-9][0-9]}
        mmddHH=${snapshot##[0-9][0-9]}
        mm=${mmddHH%[0-9][0-9][0-9][0-9]}
        ddHH=${mmddHH##[0-9][0-9]}
        dd=${ddHH%[0-9][0-9]}
        HH=${ddHH##[0-9][0-9]}
        timestamp="$yy-$mm-$dd $HH:00:00"
        WW=`date -d"${timestamp}" '+%W'`
        age=$((${curr_timestamp}-`date -d"${timestamp}" '+%s'`))
        if [ $((${age} < 60*60*24)) = 1 ] ; then
            if [ "${per_h[${HH}]}" != "" ] ; then
                echo ${snapshot}
            else
                per_h[${HH}]=${snapshot}
            fi
        elif [ $((${age} < 60*60*24*7)) = 1 ] ; then
            if [ "${per_d[${dd}]}" != "" ] ; then
                echo ${snapshot}
            else
                per_d[${dd}]=${snapshot}
            fi
        elif [ $((${age} < 60*60*24*31)) = 1 ] ; then
            if [ "${per_w[${WW}]}" != "" ] ; then
                echo ${snapshot}
            else
                per_w[${WW}]=${snapshot}
            fi
        elif [ $((${age} < 60*60*24*366)) = 1 ] ; then
            if [ "${per_m[${mm}]}" != "" ] ; then
                echo ${snapshot}
            else
                per_m[${mm}]=${snapshot}
            fi
        else
            if [ "${per_y[${yy}]}" != "" ] ; then
                echo ${snapshot}
            else
                per_y[${yy}]=${snapshot}
            fi
        fi
    done
}

waitsecs () {
    printf "waiting to end ..."
    for ((i=$1;i>0;i--)) ; do printf " %d" $i ; sleep 1 ; done; echo
}


all_help () {
    cat <<EOF
$0 all
Creates or updates an existing backup

EOF
}

all () {
    echo "# Backup began at `date`"
    echo "# Connecting"
    connect
    echo "# Taking snapshots to get statistics right"
    hotrun snapshots
    echo "# Applying retention policy"
    exec_smartretp
    echo "# Creating backups"
    backups
    # set canmount=off to avoid filesystems compiting for the same mountpoint:
    # offmounts # note: offmounts integrated in backups to avoid unmount problems
    echo "# Saving restore scripts"
    # generate bak_info dirs in the backup media:
    bak_infos
    # generate fixmount_*.sh to restore the attributes of the filesystem:
    fixmounts
    echo "# Logging backup"
    backup_log
    echo "# Preparing reports"
    show_history
    statistics
    echo "# Disconnecting"
    disconnect
    # dryrun=1 disconnect
    # echo "Note: You must run ./backup.sh disconnect before to remove the media."
    echo "# Backup ended at `date`"
}

help_help () {
    cat <<EOF

$0
Will show this help and dry run the [all] option.  That will create a snapshot
in the sender filesytems, shows a summary and the zfs commands that will be
executed

EOF
}

help () {
    help_help
    all_help
    connect_help
    snapshots_help
    show_history_help
}

main () {
    if [ "$*" = "" ] ; then
        dryrun all
    else
	$*
    fi
}

main $*

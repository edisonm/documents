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

# ssh_host () {
#     if [ "$1" != "" ] \
#            && [ "$1" != "${hostname}" ] \
#            && [ "$1" != localhost ] ; then
#         echo "ssh $1"
#     fi
# }

# always use ssh, to avoid odd behaviors
ssh_host () {
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
        zfs_prev \
        sendsnap \
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
            $* < /dev/null || true
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

recv_fmt () {
    recv_fmt=clone
    for media_recv_fmt in ${recvformats} ; do
        if [ "${1}:zdump" = "${media_recv_fmt}" ] ; then
            recv_fmt=zdump
        fi
    done
    echo ${recv_fmt}
}

forall_recv () {
    if [ "${recv_pool}" = "" ] || [ "${recv_host}" = "" ] ; then
        media_host_pools[${fstype}]="${media_host_pools[${fstype}]:-`media_host_pools ${fstype}`}"
        for recv_host_pool in ${media_host_pools[${fstype}]} ; do
            recv_host=${recv_host_pool%:*}
	    recv_pool=${recv_host_pool##*:}
            recv_zpool=${recv_pool}
            recv_fmt=`recv_fmt ${recv_zpool}`
            recv_zpoolfs=${recv_zpool}${recv_zfs}
            recv_ssh="`ssh_host ${recv_host}`"
            if [ "`avail_ssh ${recv_host}`" = 1 ] ; then
                $* < /dev/null
            fi
        done
    else
        recv_zpool=${recv_pool}
        recv_fmt=`recv_fmt ${recv_zpool}`
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

destroy_recv_dropsnap_clone () {
    for dropsnap in $* ; do
        destroy_snapshot "${recv_host}" "${recv_zpool}" "${recv_uuid}" "${recv_zfs}${send_zfs}" "${snprefix}${dropsnap}"
    done
}

destroy_recv_dropsnap_zdump () {
    # The snapshosts must be dropped when created, bo avoid incompleteness, so
    # we only mark them wit the -cleanup extension
    recv_dir="/mnt/${recv_zpool}/crbackup${recv_zfs}${send_zfs}"
    for dropsnap in $* ; do
        recv_ssh="`ssh_host ${recv_host}`"
        dropfiles=$(${recv_ssh} find ${recv_dir} -name full_${dropsnap}.ra[wz] \
                                -o -name incr_${dropsnap}_"'*.ra[wz]'" \
                                -o -name incr_"'*'"_${dropsnap}"'.ra[wz]'")
        for dropfile in ${dropfiles} ; do
            dryer ${recv_ssh} " mv ${dropfile} ${dropfile}-cleanup"
        done
    done
}

destroy_recv_dropsnap_top () {
    destroy_recv_dropsnap_top_${recv_fmt} $*
}

dropsnaps () {
    dropsnaps=${dropsnaps:-${1}}
    # Note: duplicated calls are handled by destroy_snapshot, so don't try to
    # optimize this here
    dropopts="-r"

    forall_backjobs \
        destroy_send_recv_dropsnap ${dropsnaps}
}

destroy_send_recv_dropsnap () {
    send_unfold=1 \
        zfs_prev_${fstype} \
        destroy_send_dropsnap ${dropsnaps}
    
    send_unfold=1 \
        forall_recv \
        destroy_recv_dropsnap ${dropsnaps}
}

destroy_recv_dropsnap () {
    destroy_recv_dropsnap_${recv_fmt} $*
}

smartretp () {
    if [ "${smartretp}" = 1 ] ; then
        forall_backjobs \
            destroy_send_recv_smartretp
    fi
}

destroy_send_recv_smartretp () {
    send_unfold=1 \
        zfs_prev \
        sendsnap \
        destroy_send_smartretp

    send_unfold=1 \
        forall_recv \
        destroy_recv_smartretp
}

destroy_recv_smartretp () {
    destroy_recv_smartretp_${recv_fmt}
}

destroy_recv_smartretp_zdump () {
    destroy_recv_smartretp_top
}

destroy_recv_smartretp_clone () {
    # zfs destroy supports recursion, so we don't do the recursion ourselves
    destroy_recv_smartretp_top
}

destroy_recv_smartretp_top () {
    # Next command means: keep initsnap, prevsnap, currsnap, and last 2.
    # initsnap must be kept to avoid a full backup in case it is removed.
    recvsnap="`recvsnap|tail -n +2|head -n -2`"
    recv_dropsnaps=`smartretp_snap ${recvsnap}`
    destroy_recv_dropsnap ${recv_dropsnaps} ${dropsnaps}
}

destroy_send_smartretp () {
    sendsnap="`sendsnap|tail -n +2|head -n -2`"
    send_dropsnaps=`smartretp_snap ${sendsnap}`
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

statistics () {
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

update_total () {
    if [ "`recvsnap|grep ${currsnap}`" = "" ] ; then
        snapshot_size=`snapshot_size`
        update_${fstype}_${recv_fmt}
    fi
}

backup () {
    if [ "`recvsnap|grep ${currsnap}`" = "" ] ; then
        snapshot_size=`snapshot_size`
        echo -e "\r$action ${send_host}:${send_zpoolfs} to ${recv_host}:${recv_zpoolfs}"
        backup_${fstype}_${recv_fmt}
	if [ "${send_unfolded}" = 0 ] ; then
	    for send_zpoolfs in ${send_zpoolfss} ; do
		# prevsnap=`prevsnap ${prevcmd}`
		# sendopts="-R"
		# dropopts=""
		send_zfs=${send_zpoolfs##${send_zpool}} offmount_${fstype}_${recv_fmt}
            done
	else
	    offmount_${fstype}_${recv_fmt}
	fi
    fi
}

restore_sh () {
    # echo "recording commands to restore ${send_host}:${send_zpoolfs} from ${recv_host}:${recv_zpoolfs}"
    baktype=full
    backup_restore_sh_${fstype}
}

calc_totals () {
    send_total=0
    send_files=0

    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        update_total
}

benchmark_noop () {
    true
}

echo_mediahost () {
    echo ${mediahost}
}

echo_sendhost () {
    echo ${send_host}
}

benchmarking () {
    echo "# empty loop"
    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        benchmark_noop
    echo "# done"
}

backups () {
    send_offset=0
    forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        backup

    nodry echo

    if [ "${send_total}" != "${send_offset}" ] ; then
        echo "ERROR: Total and Offset bytes doesn't match at the end: ${send_total} != ${send_offset}" 1>&2
    fi
}

offmount () {
    offmount_${fstype}_${recv_fmt}
}

offmounts () {
    # note: offmounts integrated in backups to avoid unmount problems
    send_unfold=1 \
        forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        offmount
}

fixmount () {
    fixmount_${fstype}_${recv_fmt}
}

bak_info () {
    bak_info_${fstype}_${recv_fmt}
}

bak_infos () {
    forall_fstype \
        forall_mediahosts \
        forall_medias \
        bak_info
}

restores () {
    forall_fstype \
        forall_mediahosts \
        forall_medias \
        cleanup_restore
    
    forall_backjobs \
        forall_recv \
        restore_sh
}

cleanup_restore () {
    media_fmt=`recv_fmt ${media_pool}`
    nodry cleanup_restore_${media_fmt}
}

cleanup_restore_clone () {
    cat <<EOF | ${media_ssh} "cat > /mnt/${media_pool}/crbackup/restore.sh"
#!/bin/bash

currsnap="${currsnap}"
recv_zpool=${media_pool}

restore_job () {
    rest_zpool="\${1}"
    recv_zfs="\${2}"
    send_zfs="\${3}"
    back_zfs="\${recv_zpool}\${recv_zfs}\${send_zfs}"
    back_size="\`(zfs send -nvPcR \${back_zfs}@${snprefix}\${currsnap} 2>/dev/null | grep size | awk '{print $2}')||echo 0\`"
    zfs send -Rc \${back_zfs}@${snprefix}\${currsnap} | pv -pers \${back_size} | zfs recv -d -F \${rest_zpool}\${send_zfs}
}

EOF
}

cleanup_restore_zdump () {
    cat <<EOF | ${media_ssh} "cat > /mnt/${media_pool}/crbackup/restore.sh"
#!/bin/bash

currsnap="${currsnap}"
recv_zpool=${media_pool}

restore_job () {
    rest_zpool="\${1}"
    recv_zfs="\${2}"
    send_zfs="\${3}"
    back_dir="/mnt/\${recv_zpool}/crbackup\${recv_zfs}\${send_zfs}"
    back_size="\`stat -c '%s' \${back_dir}/\${recv_file}\`"
    for recv_file in \`cd \${back_dir} ; ls *.ra[wz]\` ; do
        if [ "${recv_file##*.}" = raz ] ; then
	    ziper="lrz -d"
	else
	    ziper="cat"
        ${ziper} \${back_dir}/\${recv_file} | pv -pers \${back_size} | zfs recv -d -F \${rest_zpool}\${send_zfs} ;
    done
    for recv_sdir in \`cd \${back_dir} ; ls -p | grep /$ | sed 's:/$::g'\` ; do
        ( restore_job \${rest_zpool} \${recv_zfs} \${send_zfs}/\${recv_sdir} )
    done
}

EOF
}

fixmounts () {
    send_unfold=1 \
        forall_zjobs \
        zfs_wrapr \
        skip_eq_sendrecv \
        fixmount
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

disconnect_help () {
    cat <<EOF
$0 disconnect
Close the zfs pools that contain the medias and encrypt them

EOF
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
    local olddry=$dryrun
    dryrun=1
    echo "Note: dryrun, execute the next command to do the real stuff:"
    echo $0 $*
    echo
    main $*
    dryrun=$olddry
}

echorun () {
    local olddry=$dryrun
    dryrun=2
    main $*
    dryrun=$olddry
}

hotrun () {
    local olddry=$dryrun
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

smartretp_snap () {
    curr_timestamp=`date '+%s'`
    for snapshot in $* ; do
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
    echo "# update snapshot lists"
    update_hosts_snapshots
    echo "# Taking snapshots to get statistics right"
    hotrun snapshots
    echo "# Applying retention policy"
    smartretp
    echo "# Calculating totals"
    calc_totals
    echo "# Creating backups: ${send_files} objects / `byteconv ${send_total}`"
    backups
    # offmounts
    echo "# Saving restore scripts"
    restores
    echo "# generate bak_info dirs in the backup media"
    bak_infos
    echo "# generate fixmount_*.sh to restore the attributes of the filesystem"
    fixmounts
    echo "# Logging backup"
    backup_log
    echo "# Show backup history"
    show_history
    echo "# Show statistics"
    statistics
    echo "# Disconnecting"
    if [ "${dryrun}" = 0 ] ; then
	sleep 10 # avoid pool is busy error
    fi
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
    disconnect_help
    snapshots_help
    show_history_help
}

main () {
    if [ "$*" = "" ] ; then
        dryrun all
    else
        command="$1"
        shift
        case "${command}" in
            dryrun)
                dryrun $*
                ;;
            all)
                all $*
                ;;
            connect)
                connect
                ;;
	    disconnect)
		disconnect
		;;
            snapshots)
                snapshots
                ;;
            dropsnaps)
                dropsnaps $*
                ;;
            show_history)
                update_hosts_snapshots
                show_history
                ;;
            statistics)
                update_hosts_snapshots
                calc_totals
                backup_log
                # show_history
                statistics
                ;;
            *)
                help
                ;;
        esac
    fi
}

main $*

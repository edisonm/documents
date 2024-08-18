#!/bin/bash

# replicate a zfs dataset, via rsync.  Useful if you are splitting a dataset
# into several subsets
#
# replicate SOURCE_ZFS TARGET_ZFS

set -e

dryrun=0

dryer () {
    if [ "${dryrun}" = 1 ] ; then
	echo $*
    else
	$*
    fi
}

replicate () {
    send_zfs=$1
    recv_zfs=$2

    send_dir=`zfs get -H mountpoint ${send_zfs} -o value`
    recv_dir=`zfs get -H mountpoint ${recv_zfs} -o value`
    
    ssub_zfss="`zfs list -r -Ho name ${send_zfs}`"

    for snapshot in `zfs list -Ht snapshot -o name ${send_zfs} 2>/dev/null | sed -e "s:${send_zfs}@::g"` ; do
        changed=0
        for ssub_zfs in ${ssub_zfss} ; do
            ssub_dir="`zfs get -H mountpoint ${ssub_zfs} -o value | sed -e "s:${send_dir}::g"`"
            snapshot_dir=${send_dir}${ssub_dir}/.zfs/snapshot/${snapshot}
            if [ -d ${snapshot_dir} ] ; then
                dryer rsync -a --delete --delete-excluded ${snapshot_dir}/ ${recv_dir}/ || true
                changed=1
            fi
        done
        if [ ${changed} = 1 ] ; then
            dryer zfs snapshot -r ${recv_zfs}@${snapshot}
        fi
    done
}

replicate $*

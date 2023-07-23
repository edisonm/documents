#!/bin/bash

# Reference: https://askubuntu.com/questions/124094/how-to-hide-an-ntfs-partition-from-ubuntu

pxve_zfs=tank/PXVE

ignore_uuids () {
    for vm_dev in `ls /dev/zvol/${pxve_zfs}` ; do
        lsblk -lfn `readlink -f /dev/zvol/${pxve_zfs}/${vm_dev%@}` -o UUID
    done
    # custom partitions to be ignored:
    echo fae9a77a-daa5-4f66-9ecb-8ba41b2a9007
}

hide_partitions () {
    while IFS=' ' read -r uuid ; do
        if [ "$uuid" != "" ] ; then
            echo 'SUBSYSTEM=="block", ENV{ID_FS_UUID}=="'$uuid'", ENV{UDISKS_IGNORE}="1"'
        fi
    done < <(ignore_uuids | sort -u)
}

hide_partitions > /etc/udev/rules.d/99-hide-partitions.rules
udevadm control --reload
udevadm trigger --subsystem-match=block

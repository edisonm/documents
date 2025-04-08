#!/bin/bash

DISKS="/dev/sda /dev/sdb /dev/sdc"
ZPOOL="set3"
# PARTS="1 2"
# PARTSIZE=+4883735552
# ZOPTS=raidz1

PARTS="1"
PARTSIZE=0

ASKPASS_='/lib/cryptsetup/askpass'

dryrun=0

. `dirname $0`/common.sh

next_id () {
    if [ "${IDX}" = " " ] ; then
	IDX=0
    else
	IDX=$((${IDX}+1))
    fi
}

dryer set_key

IDX="0"
echo -en "volumes=\"" > settings_${ZPOOL}.sh
for DISK in ${DISKS} ; do
    # First, wipeout the disks:
    dryer sgdisk -o $DISK
    for PART in ${PARTS} ; do
	dryer sgdisk -n${PART}:0:${PARTSIZE} -t${PART}:8300 ${DISK}
	# Add --sector-size=4096 if needed
	dryern printf "%s" "$KEY_"|dryerp cryptsetup luksFormat --key-file - ${DISK}${PART}
	dryern printf "%s" "$KEY_"|dryerp cryptsetup luksAddKey --key-file - ${DISK}${PART} /crypto_keyfile.bin
	echo -en $(blkid -s UUID -o value ${DISK}${PART})' \\\n         ' >> settings_${ZPOOL}.sh
	next_id
    done
done
echo -e "\"" >> settings_${ZPOOL}.sh

IDX="0"
VOLS=""
for DISK in ${DISKS} ; do
    for PART in ${PARTS} ; do
	VOL=crbackup_$(blkid -s UUID -o value ${DISK}${PART})
	dryern printf "%s" "$KEY_"|dryerp cryptsetup luksOpen   --key-file - ${DISK}${PART} ${VOL}
	VOLS="${VOLS} ${VOL}"
	next_id
    done
done

dryer zpool create -o ashift=12 -o autotrim=on -O acltype=posixacl -O xattr=sa -O dnodesize=auto -O compression=on -O normalization=formD -O relatime=on -O canmount=off -O mountpoint=none -R /mnt/${ZPOOL} ${ZPOOL} ${ZOPTS} ${VOLS}

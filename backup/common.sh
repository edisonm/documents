#!/bin/bash

ASKPASS_='/lib/cryptsetup/askpass'

set_key () {
    echo "The password is used as failover decryption method"
    export KEY_="$($ASKPASS_ "New password:")"
    CONFIRM_="$($ASKPASS_ "Retype new password:")"
    if [ "${KEY_}" != "${CONFIRM_}" ] ; then
        echo "ERROR: Confirmation didn't match, aborting"
        exit 1
    fi
}

pvv () {
    local desc="`byteconv $1`"
    ./pvv-pipe.py --desc "`printf '%6s' $desc`" --offset $2 -s $3
}

ask_key () {
    echo "Input the password you used before"
    export KEY_="$($ASKPASS_ "Password:")"
}

declare -A units
units[0]=""
units[1]="K"
units[2]="M"
units[3]="G"
units[4]="T"
units[5]="E"

# tests (limit cases):

# . ./common.sh ; byteconv $((999*1024+512))
# 1000K

# . ./common.sh ; byteconv $((1024*1023+512-1))
# 1023K

# . ./common.sh ; byteconv $((1024*1023+512))
# 1M

byteconv_rec () {
    value=$1
    vunit=$2
    if [ $((${value}>=1024*1000-500)) != 0 ] && [ ${vunit} != 6 ] ; then
        vunit=$((${vunit}+1))
        value=$(((${value}+512)/1024))
        byteconv_rec $value $vunit
    else
        ipart=$((${value}/1000))
        fpart=`printf "%03g" $((${value}%1000))`
        if [ $((${ipart}${fpart}>=1000000-500)) != 0 ] ; then
            numfigs=4
            format="0f"
        else
            format="3g"
        fi
        printf "%.${format}%s\n" ${ipart}.${fpart} ${units[${vunit}]}
    fi
}

byteconv () {
    if [ "${1}" != "" ] ; then
        byteconv_rec $((${1}*1000)) 0
    fi
}

dryer () {
    if [ "${dryrun}" = 1 ] ; then
	echo $*
    else
	$*
    fi
}

nodry () {
    if [ "${dryrun}" != 1 ] ; then
	$*
    fi
}

ifdry () {
    if [ "${dryrun}" = 1 ] ; then
	$*
    fi
}

dryern () {
    if [ "${dryrun}" = 1 ] ; then
	echo -n $*
    else
	$*
    fi
}

dryerpn () {
    if [ "${dryrun}" = 1 ] ; then
	cat
	echo -n " | $*"
    else
	$*
    fi
}

dryerp () {
    if [ "${dryrun}" = 1 ] ; then
	cat
	echo " | $*"
    else
	$*
    fi
}

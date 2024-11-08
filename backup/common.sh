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

ask_key () {
    echo "Input the password you used before"
    export KEY_="$($ASKPASS_ "Password:")"
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

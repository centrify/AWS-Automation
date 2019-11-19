#!/bin/bash

#  This script is used by systemd /usr/lib/systemd/system/centrifycc-enroll.service

function prepare_for_cenroll()
{
    r=1
    NETWORK_ADDR_TYPE=${NETWORK_ADDR_TYPE:-PublicIP}
    case "$NETWORK_ADDR_TYPE" in
    PublicIP)
        CENTRIFYCC_NETWORK_ADDR=`curl --fail -s http://169.254.169.254/latest/meta-data/public-ipv4`
        r=$?
        ;; 
    PrivateIP)
        CENTRIFYCC_NETWORK_ADDR=`curl --fail -s http://169.254.169.254/latest/meta-data/local-ipv4`
        r=$?
        ;;
    HostName)
        CENTRIFYCC_NETWORK_ADDR=`hostname --fqdn`
		if [ "$CENTRIFYCC_NETWORK_ADDR" = "" ] ; then
			CENTRIFYCC_NETWORK_ADDR=`hostname`
		fi
        r=$?
        ;;
    esac
    if [ $r -ne 0 ];then
        return $r
    fi
    return $r
}

instance_id=`curl --fail -s http://169.254.169.254/latest/meta-data/instance-id`
r=$?
if [ $r -ne 0 ];then
  exit $r
fi

if [ "$COMPUTER_NAME_PREFIX" = "" ];then
    COMPUTER_NAME="$instance_id"
else
    COMPUTER_NAME="$COMPUTER_NAME_PREFIX-$instance_id"
fi

prepare_for_cenroll
r=$?
if [ $r -ne 0 ];then
  exit $r
fi

CMDPARAMARRAY=($CMDPARAM)

/usr/sbin/cenroll  \
    --tenant "$TENANT_URL" \
    --code "$ENROLLMENT_CODE" \
    --features "$FEATURES" \
    --name "$COMPUTER_NAME" \
    --address "$CENTRIFYCC_NETWORK_ADDR" \
    "${CMDPARAMARRAY[@]}"
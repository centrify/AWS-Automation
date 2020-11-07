#!/bin/bash

################################################################################
#
# Copyright 2017-2020 Centrify Corporation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Sample script for AWS automation orchestration with CentrifyCC
#
#
# This sample script is to demonstrate how AWS instances can be orchestrated to
# cenroll Centrify identity platform through Centrify agent for Linux.
#
# This script is tested on AWS Autoscaling using the following EC2 AMIs:
# - Red Hat Enterprise Linux 7.5                        x86_64
# - Red Hat Enterprise Linux 8                          x86_64
# - Ubuntu Server 16.04 LTS (HVM)                       x86_64
# - Ubuntu Server 18.04 LTS (HVM)                       x86_64
# - Amazon Linux 2 LTS Candidate AMI (HVM)              x86_64
# - CentOS 7 HVM                                        x86_64
# - CentOS 8 HVM                                        x86_64
# - SUSE Linux Enterprise Server 12 SP4 (HVM)           x86_64
#


function prerequisite()
{
   common_prerequisite
   r=$?
   if [ $r -ne 0 ];then
       echo "$CENTRIFY_MSG_PREX: prerequisite check failed"
   fi
   return $r
}

function check_config()
{
    if [ "$CENTRIFYCC_TENANT_URL" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_TENANT_URL!" 
        return 1
    fi

    if [ "$CENTRIFYCC_ENROLLMENT_CODE" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_ENROLLMENT_CODE!" 
        return 1
    fi

    if [ "$CENTRIFYCC_FEATURES" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_FEATURES!" 
        return 1
    fi

    if [[ "$CENTRIFYCC_AGENT_AUTH_ROLES" = "" && "$CENTRIFYCC_AGENT_SETS" = "" ]];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_AGENT_AUTH_ROLES or CENTRIFY_CC_AGENT_SETS!" 
        return 1
    fi

    CENTRIFYCC_NETWORK_ADDR_TYPE=${CENTRIFYCC_NETWORK_ADDR_TYPE:-PublicIP}
    case "$CENTRIFYCC_NETWORK_ADDR_TYPE" in
      PublicIP|PrivateIP|HostName)
        :
        ;;
      *)
        echo "$CENTRIFY_MSG_PREX: invalid CENTRIFYCC_NETWORK_ADDR_TYPE: $CENTRIFYCC_NETWORK_ADDR_TYPE " 
        return 1
        ;;
    esac

    instance_id=`curl --fail -s http://169.254.169.254/latest/meta-data/instance-id`
    r=$? 
    if [ $r -ne 0 ];then
      echo "$CENTRIFY_MSG_PREX: cannot get instance id" && return $r
    fi
    if [ "$CENTRIFYCC_COMPUTER_NAME_PREFIX" = "" ];then
        COMPUTER_NAME="$instance_id"
    else
        COMPUTER_NAME="$CENTRIFYCC_COMPUTER_NAME_PREFIX-$instance_id"
    fi
    return 0
}

function install_packages()
{
    r=1
    centrify_packages=""
    case "$OS_NAME" in
    rhel|amzn|centos|sles)
        centrify_packages=CentrifyCC
        r=0
        ;;
    ubuntu)
        centrify_packages=centrifycc
        r=0
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX doesn't supported for OS $OS_NAME"
        r=1
    esac
    [ $r -ne 0 ] && return $r
  
    install_packages_from_repo $centrify_packages
    r=$? 
  
    return $r
}


function prepare_for_cenroll()
{
    r=1
    case "$CENTRIFYCC_NETWORK_ADDR_TYPE" in
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
        echo "$CENTRIFY_MSG_PREX: cannot get network address for cenroll" && return $r
    fi
    return $r
}

function do_cenroll()
{
	# set up optional parameter string.
	# Note that login roles and sets are optional, but at least one must be required
	#
	CMDPARAM=()
	if [ "$CENTRIFYCC_AGENT_AUTH_ROLES" != "" ] ; then
	  CMDPARAM=("--agentauth" "$CENTRIFYCC_AGENT_AUTH_ROLES")
	  # grant permssion to view
	  IFS=","
	  for role in $CENTRIFYCC_AGENT_AUTH_ROLES
	  do
	    CMDPARAM=("${CMDPARAM[@]}" "--resource-permission" "role:$role:View")
	  done
	fi
	
	# set up add to set
	if [ "$CENTRIFYCC_AGENT_SETS" != "" ] ; then 
	   CMDPARAM=("${CMDPARAM[@]}" "--resource-set" "${CENTRIFYCC_AGENT_SETS[@]}")
	fi
	
	# for additional options, need to parse into array
	if [ "$CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS" != "" ] ; then
	  IFS=' ' read -a tempoption <<< "${CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS}"
	  CMDPARAM=("${CMDPARAM[@]}" "${tempoption[@]}")
	fi
	
	echo "cenroll parameters: [${CMDPARAM[@]}]"
	  
     /usr/sbin/cenroll  \
          --tenant "$CENTRIFYCC_TENANT_URL" \
          --code "$CENTRIFYCC_ENROLLMENT_CODE" \
          --features "$CENTRIFYCC_FEATURES" \
          --name "$COMPUTER_NAME" \
          --address "$CENTRIFYCC_NETWORK_ADDR" \
          "${CMDPARAM[@]}"
    r=$?
    if [ $r -ne 0 ];then
        echo "$CENTRIFY_MSG_PREX: cenroll failed!" 
        return $r
    fi
    /usr/bin/cinfo
    r=$?
    if [ $r -ne 0 ];then 
        echo "$CENTRIFY_MSG_PREX: cinfo failed after cenroll!" 
    fi

    return $r
}

function resolve_rpm_name()
{
    r=0
    case "$OS_NAME" in
    rhel|amzn|centos)
        CENTRIFYCC_RPM_NAME="CentrifyCC-rhel6.x86_64.rpm"
        ;;
    ubuntu)
        CENTRIFYCC_RPM_NAME="centrifycc-deb9-x86_64.deb"
        ;;
    sles)
        CENTRIFYCC_RPM_NAME="CentrifyCC-suse12.x86_64.rpm"
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX: cannot resolve rpm package name for centrifycc on current OS $OS_NAME"
        r=1
        ;;
    esac
    return $r
}

function install_unenroll_enroll_service()
{
    # save the cenroll info so it can be used by the centrifycc-enroll service
    ENV_FILE="/etc/centrifycc/cenroll.env"
    
    echo "CMDPARAM=\"${CMDPARAM[@]}\"" >> $ENV_FILE
    echo "TENANT_URL=$CENTRIFYCC_TENANT_URL" >> $ENV_FILE
    echo "ENROLLMENT_CODE=$CENTRIFYCC_ENROLLMENT_CODE" >> $ENV_FILE
    echo "FEATURES=$CENTRIFYCC_FEATURES" >> $ENV_FILE
    echo "COMPUTER_NAME_PREFIX=$CENTRIFYCC_COMPUTER_NAME_PREFIX" >> $ENV_FILE
    echo "NETWORK_ADDR_TYPE=$CENTRIFYCC_NETWORK_ADDR_TYPE" >> $ENV_FILE
    
    chmod 644 $ENV_FILE
    
    CENROLL_SCRIPT_PATH="/etc/centrifycc/scripts"
    mkdir -p $CENROLL_SCRIPT_PATH
    
    # needed by centrifycc-enroll.service
    cp -f $centrifycc_deploy_dir/cenroll.sh $CENROLL_SCRIPT_PATH/cenroll.sh
    chmod 744 $CENROLL_SCRIPT_PATH/cenroll.sh
    
    SYSTEMD_PATH="/lib"
    if [ -d "/usr/lib/systemd/system" ]; then
        SYSTEMD_PATH="/usr/lib"
    fi

    cp -f $centrifycc_deploy_dir/centrifycc-unenroll.service $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service
    cp -f $centrifycc_deploy_dir/centrifycc-enroll.service $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service
    
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service
    
    # need to start the centrifycc-unenroll.service immediately so when stop instance, cunenroll will be executed.
    systemctl enable centrifycc-unenroll.service --now
    systemctl enable centrifycc-enroll.service
}

function start_deploy()
{ 
    resolve_rpm_name
    r=$? && [ $r -ne 0 ] && return $r

    download_install_rpm $CENTRIFYCC_DOWNLOAD_PREFIX $CENTRIFYCC_RPM_NAME
    r=$? && [ $r -ne 0 ] && return $r
  
    enable_sshd_password_auth
    r=$? && [ $r -ne 0 ] && return $r

    enable_sshd_challenge_response_auth
    r=$? && [ $r -ne 0 ] && return $r
  
    prepare_for_cenroll
    r=$? && [ $r -ne 0 ] && return $r
  
    do_cenroll
    r=$? && [ $r -ne 0 ] && return $r
  
    install_unenroll_enroll_service
    r=$? && [ $r -ne 0 ] && return $r
    
    return 0
}

if [ "$DEBUG_SCRIPT" = "yes" ];then
    set -x
fi

file_parent=`dirname $0`
source $file_parent/common.sh
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot source common.sh [exit code=$r]" && exit $r

detect_os
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: detect OS failed  [exit code=$r]" && exit $r

check_supported_os centrifycc
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: current OS is not supported [exit code=$r]" && exit $r

check_config
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: error in configuration parameter settings [exit code=$r]" && exit $r

prerequisite
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot set up pre-requisites [Exit code=$r]" && exit $r

start_deploy
r=$?
if [ $r -eq 0 ];then
  echo "$CENTRIFY_MSG_PREX: CentrifyCC successfully deployed!"
else
  echo "$CENTRIFY_MSG_PREX: Error in CentrifyCC deployment [exit code=$r]!"
fi

exit $r

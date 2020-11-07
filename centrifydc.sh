#!/bin/bash

################################################################################
#
# Copyright (c) 2017-2020 Centrify Corporation
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
# Sample script for AWS automation orchestration with CentrifyDC
#
#
# This sample script is to demonstrate how AWS instances can be orchestrated to
# adjoin to Active Directory.
#
# This script is tested on AWS Autoscaling using the following EC2 AMIs:
# - Red Hat Enterprise Linux 7.3 or later               x86_64
# - Red Hat Enterprise Linux 8                          x86_64
# - Ubuntu Server 16.04 LTS (HVM), SSD Volume Type      x86_64
# - Ubuntu Server 18.04 LTS (HVM), SSD Volume Type      x86_64
# - Amazon Linux 2 LTS
# - CentOS 7.2                                          x86_64
# - SUSE Linux Enterprise Server 12 SP4 (HVM)           x86_64
#

# Use python to upgrade awscli.
# Why shall we upgrade the awscli ?
# Answer:
# I found that 'aws s3 cp .. login.keytab' will fail on 
# SUSE Linux Enterprise Server 11 SP4 (PV), SSD Volume Type.
# After I upgraded the existent awscli to latest version, 
# aws s3 cp will succeed.
function upgrade_awscli()
{
    if ! python3 --version ;then
        case "$OS_NAME" in
        rhel|centos)
            yum install python3 -y
            r=$?
            ;;
	amzn)
	    yum install python34 -y
            r=$?
            ;;
        ubuntu)
            apt-get -y install python3
            r=$?
            ;;
        sles)
            zypper --non-interactive install python3
            r=$?
            ;;
        *)
            echo "$CENTRIFY_MSG_PREX: Unknown platform: $OS_NAME" && return 1
            ;;
        esac
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: Python installation failed"
            return $r
        fi
    fi
    if ! pip --version ;then
    	case "$OS_NAME" in 
        ubuntu)
            case "$OS_VERSION" in
            16|16.*) :
                ;;
            *)
                apt-get -y install python3-distutils 
                ;;  
            esac
        esac
        curl --fail -s -O https://bootstrap.pypa.io/get-pip.py
        python3 get-pip.py
        r=$r
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: pip installation failed"
            return $r
        fi
    fi
    if ! aws --version ;then
        pip install awscli
        r=$?
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: AWS Command Line Interface installation failed!" 
            return $r
        fi
    else
        pip install --upgrade --user awscli
        r=$?
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: AWS Command Line Interface upgrade failed!" 
            return $r
        fi
    fi
    return $r
}

function prerequisite()
{ 
    common_prerequisite
    r=0
	# only need AWS CLI if we are not using S3 to store login.keytab file. 
	# So, check if join to AD and also CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION is not true
    if [ "$CENTRIFYDC_JOIN_TO_AD" = "yes" -a "$CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION" != "yes" ]; then
        # Ensure that aws cli installed, otherwise we cannot download login.keytab from S3 bucket.
        if ! aws --version ;then
            if ! python3 --version ;then
                case "$OS_NAME" in
                rhel|centos)
                    yum install python3 -y
                    r=$?
                    ;;
		amzn)
		    yum install python34 -y
		    r=$?
		    ;;
                ubuntu)
                    case "$OS_VERSION" in
                    16|16.*)
                        ;;
                    *)
                        mv /etc/resolv.conf /tmp/
                        ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
                        ;;
                    esac
                    apt-get update
                    apt-get -y install python3
                    r=$?
                    ;;
                sles)
                    zypper --non-interactive install python3
                    r=$?
                    ;;
                *)
                    echo "$CENTRIFY_MSG_PREX: Unknown platform: $OS_NAME" && return 1
                    ;;
                esac
                if [ $r -ne 0 ];then
                    echo "$CENTRIFY_MSG_PREX: Python installation failed"
                    return $r
                fi
            fi
            if ! pip --version ;then
	    	case "$OS_NAME" in 
        	ubuntu)
            	    case "$OS_VERSION" in
            	    16|16.*) :
                	 ;;
            	    *)
                	 apt-get -y install python3-distutils 
                	 ;;  
            	    esac
        	esac
                curl --fail -s -O https://bootstrap.pypa.io/get-pip.py
                python3 get-pip.py
                r=$r
                if [ $r -ne 0 ];then
                    echo "$CENTRIFY_MSG_PREX: pip installation failed"
                    return $r
                fi
            fi

            case "$OS_NAME" in
            ubuntu)
                case "$OS_VERSION" in
                14|14.*)
                    pip install awscli --upgrade --user  
                    export PATH=/root/.local/bin:$PATH
                    ;;
                *)  
                    pip install awscli
                    ;;
                esac
                ;;
            *)  
                pip install awscli
                ;;
            esac
            r=$?
            if [ $r -ne 0 ];then
                echo "$CENTRIFY_MSG_PREX: AWS Command Line Interface installation failed!" 
                return $r
            fi
        fi

        # Try to upgrade awscli on SuSE11.
        case "$OS_NAME" in
        sles)
            case "$OS_VERSION" in 
            11|11.*)
                upgrade_awscli
                r=$?
                [ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: upgrade awscli failed" && return $r
                ;;
            *)
                :
                ;;
            esac
            ;;
        *)    
            :
            ;;
        esac

        # Prevent aws s3 cp failed for some regions.
        # if an EC2 residing in a region whose default s3 signature version is 
        # lower than s3v4, it will fail when the EC2 accesses a S3 bucket 
        # whose s3 signature version is s3v4.
        # Hence we need to ensure that s3 API will use s3v4 signature.
        aws configure set default.s3.signature_version s3v4 
        r=$?
        [ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: awscli configure failed" && return $r
    fi
    return 0
}

function check_config()
{
    if [ "$CENTRIFYDC_JOIN_TO_AD" != "no" -a "$CENTRIFYDC_JOIN_TO_AD" != "yes" ];then
        echo "$CENTRIFY_MSG_PREX: invalid CENTRIFYDC_JOIN_TO_AD: $CENTRIFYDC_JOIN_TO_AD" && return 1
    fi
  
    if [ "$CENTRIFY_REPO_CREDENTIAL" = "" ];then
        echo "$CENTRIFY_MSG_PREX: invalid CENTRIFY_REPO_CREDENTIAL" && return 1
    fi
    
    if [ "$CENTRIFYDC_JOIN_TO_AD" = "yes" ];then
        if [ "$CENTRIFYDC_ZONE_NAME" = "" ];then
            echo "$CENTRIFY_MSG_PREX: Must set CENTRIFYDC_ZONE_NAME !" && return 1
        fi
        CENTRIFYDC_HOSTNAME_FORMAT=${CENTRIFYDC_HOSTNAME_FORMAT:-PRIVATE_IP}
        case "$CENTRIFYDC_HOSTNAME_FORMAT" in
        PRIVATE_IP|INSTANCE_ID)
            :
            ;;
        *)
            echo "$CENTRIFY_MSG_PREX: invalid CENTRIFYDC_HOSTNAME_FORMAT: $CENTRIFYDC_HOSTNAME_FORMAT" && return 1
            ;;
        esac
		CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION=${CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION:-}
		if [ "$CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION" = "" ] || [ "$CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION" = "no" ]; then
			CENTRIFYDC_KEYTAB_S3_BUCKET=${CENTRIFYDC_KEYTAB_S3_BUCKET:-}
			if [ "$CENTRIFYDC_KEYTAB_S3_BUCKET" = "" ];then
				echo "$CENTRIFY_MSG_PREX: requires a S3 bucket for the keytab file associated with the user who joins to Active Directory" 
				return 1
			fi
		elif [ "$CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION" = "yes" ]; then
			CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION=${CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION:-}
			if [ "$CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION" = "" ]; then
				echo "$CENTRIFY_MSG_PREX: must define custom login function to obtain login.keytab"
				return 1
			fi
		else
			echo "$CENTRIFY_MSG_PREX:  illegal value specified for CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION.  Must be yes or no."
			return 1
        fi
    fi
    centrify_packages=`echo -n "$CENTRIFYDC_ADDITIONAL_PACKAGES" | awk '{for(i=1;i<=NF;i++){ print $i;}}' | sort | uniq | awk '{printf("%s ", $1)}' |  awk 'BEGIN {invalid=0} {if(invalid != 1) {for(i=1;i<=NF;i++){if($i != "centrifydc-ldapproxy" && $i != "centrifydc-openssh" && $i != "") {invalid=1;printf("invalid ");break};if ( i == 1) { printf("%s", $i)} else { printf(" %s", $i)}} }}'`
    if echo $centrify_packages | grep 'invalid' >/dev/null ;then
        echo "$CENTRIFY_MSG_PREX: invalid CENTRIFYDC_ADDITIONAL_PACKAGES : $CENTRIFYDC_ADDITIONAL_PACKAGES" && return 1
    fi
    centrify_packages="centrifydc $centrify_packages"
    
    return 0
}

function get_packagename()
{
    r=1
    case "$OS_NAME" in
    rhel|amzn|centos|sles)
        centrify_packages=`echo $centrify_packages | sed -n 's/centrifydc/CentrifyDC/gp'`
        r=$?
        if [ $r -eq 0 -a "$centrify_packages" = "" ];then
            echo "$CENTRIFY_MSG_PREX: need specific valid centrifydc package names"
            r=1
        fi
        ;;
    ubuntu)
        # Need not convert lower-case package names.
        r=0
        ;;
    *)
        echo "Centrify doesn't support the os $OS_NAME currently"
        r=1
    esac
    return $r
}

function install_packages()
{
    r=1
    get_packagename
    [ $r -ne 0 ] && return $r

    install_packages_from_repo $centrify_packages
    [ $r -ne 0 ] && return $r

    return $r
}

function get_keytab_file()
{
    if [ "$CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION" = "yes" ]; then
		if [ "`type -t $CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION`" == "function" ]; then
			eval "$CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION"
			r=$?
			if [ $r -ne 0 ]; then
				echo "$CENTRIFY_MSG_PREX: download login.keytab from user defined function failed"
			fi
			if [ ! -f $centrifydc_deploy_dir/login.keytab ]; then
				echo "$CENTRIFY_MSG_PREX: login.keytab not set up in custom function $CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION."
				# return 2 (ENOENT)
				return 2
			fi 
			chmod 0600 $centrifydc_deploy_dir/login.keytab
			return $r
		else
			echo "$CENTRIFY_MSG_PREX: user defined function does not exist or is not a function"
			return 2
		fi
	else
		aws s3 cp s3://$CENTRIFYDC_KEYTAB_S3_BUCKET/login.keytab $centrifydc_deploy_dir/
		r=$?
		if [ $r -ne 0 ];then
			echo "$CENTRIFY_MSG_PREX: download login.keytab from s3 bucket failed" 
		fi
		chmod 0600 $centrifydc_deploy_dir/login.keytab
		return $r
	fi
}

function get_user_and_domain()
{
    join_user=`/usr/share/centrifydc/kerberos/bin/klist -k $centrifydc_deploy_dir/login.keytab | grep @ | awk '{print $2}' | sed -n '1p'`
    domain_name=`/usr/share/centrifydc/kerberos/bin/klist -k $centrifydc_deploy_dir/login.keytab | grep '@' | cut -d '@' -f 2 | sed -n '1p'`
    if [ "$join_user" = "" -o "$domain_name" = "" ];then
        echo "$CENTRIFY_MSG_PREX: cannot get username or domain name from keytab file" && return 1
    fi
    return 0
}

function generate_hostname()
{
    host_name=
    case "$CENTRIFYDC_HOSTNAME_FORMAT" in
    PRIVATE_IP)
        private_ip=`curl --fail -s http://169.254.169.254/latest/meta-data/local-ipv4`
        host_name="`echo $private_ip | sed -n 's/\./-/gp'`"
        ;;
    INSTANCE_ID)
        instance_id=`curl --fail -s http://169.254.169.254/latest/meta-data/instance-id`
        host_name=$instance_id
        ;;
    "")
        :
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX: invalid hostname format: $CENTRIFYDC_HOSTNAME_FORMAT" && return 1
        ;;
    esac
    if [ "$host_name" = "" ];then
        echo "$CENTRIFY_MSG_PREX: cannot set host_name, an internal error happened!" && return 1
    fi
    if [ ${#host_name} -gt 15 ];then
        # Only leave the start 15 chars.
        host_name=`echo $host_name | sed -n 's/^\(.\{15,15\}\).*$/\1/p'`
    fi
    echo "$host_name" | grep -E "[\._]" >/dev/null && host_name=`echo $host_name | sed -n 's/[\._]/-/gp'`
    # Setup hostname
    case "$OS_NAME" in
    rhel|amzn|centos)
        sed -i '/HOSTNAME=/d' /etc/sysconfig/network
        echo "HOSTNAME=$host_name" > /etc/sysconfig/network
        ;;
    *)
        echo "$host_name" >/etc/hostname 
        ;;
    esac
    hostname $host_name
    # Fix the bug that sudo cmd always complains 'sudo: unable to resolve host' on ubuntu.
    # Actually it is AWS who shall fix the bug.
    [ "$OS_NAME" = "ubuntu" ] && echo "127.0.0.1 $host_name" >> /etc/hosts
    return 0
}

function prepare_for_adjoin()
{
    # Backup krb5.conf
    [ -f /etc/krb5.conf ] && mv /etc/krb5.conf /etc/krb5.conf.centrify_backup
    # Generate keytab to adjoin without inputting password
    /usr/share/centrifydc/kerberos/bin/kinit -kt $centrifydc_deploy_dir/login.keytab -l $krb5_cache_lifetime $join_user
    r=$?
    [ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: generate kerberos credentials cache failed!" && return $r
    # Configure to support SSO
    echo "$CENTRIFY_MSG_PREX: will configure centrifydc.conf to support SSO ......."
    sed -i -r '/^[[:space:]]*adclient.dynamic.dns.enabled[[:space:]]*:.*$/d' /etc/centrifydc/centrifydc.conf
    echo "adclient.dynamic.dns.enabled: true" >> /etc/centrifydc/centrifydc.conf
    sed -i -r '/^[[:space:]]*krb5.forwardable.user.tickets[[:space:]]*:.*$/d' /etc/centrifydc/centrifydc.conf
    echo "krb5.forwardable.user.tickets: true" >> /etc/centrifydc/centrifydc.conf
  
    adlicense -l
    r=$?
    if [ $r -ne 0 ];then
        echo "$CENTRIFY_MSG_PREX: adlicense -l failed" 
        return $r
    fi
  
    return 0
}

function do_adjoin()
{

    result=$(/usr/sbin/adjoin  $domain_name -z $CENTRIFYDC_ZONE_NAME --name `hostname` $CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS)
    r=$?
    [ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: adjoin failed!!" && return $r
    if echo $result | grep 'The directory service is busy' >/dev/null 2>&1 ;then
        time_wait=$RANDOM
        time_wait=$((time_wait%30+1))
        echo "$CENTRIFY_MSG_PREX: the directory service is busy and will sleep $time_wait seconds"
        sleep $time_wait
        /usr/sbin/adjoin $domain_name \
            -z $CENTRIFYDC_ZONE_NAME \
            --name `hostname` \
            $CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS
        r=$?
        [ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: run adjoin failed again" && return 1
    fi
    /usr/share/centrifydc/kerberos/bin/kdestroy
    /usr/bin/adinfo | grep 'CentrifyDC mode' | grep 'connected' >/dev/null 2>&1
    [ $? -ne 0 ] && echo "$CENTRIFY_MSG_PREX: adjoin failed!!" && return 1

    return 0
}

function clean_files()
{
    if [ -e $centrifydc_deploy_dir/login.keytab ];then
      rm -rf $centrifydc_deploy_dir/login.keytab
    fi
    # revert the symlink of /etc/resolv.conf to its original file in Ubuntu 18.04+
    case $OS_NAME in
    ubuntu)
        case $OS_VERSION in
        16|16.*)
            ;;
        *)
            mv /tmp/resolv.conf /etc/
            ;;
        esac
        ;;
    esac
    return 0
}

function install_leave_join_service ()
{
    # install keytab file.
    cp -f $centrifydc_deploy_dir/login.keytab /etc/centrifydc/login.keytab
    chmod 400 /etc/centrifydc/login.keytab
    
    ENV_FILE="/etc/centrifydc/adjoin.env"
    
    # save the adjoin info so it can be used by the centrifydc-adleave centrifydc-adjoin service
    echo "ADJOINER=$join_user" >> $ENV_FILE
    echo "LOGIN_KEYTAB=/etc/centrifydc/login.keytab" >> $ENV_FILE
    echo "DOMAIN=$domain_name" >> $ENV_FILE
    echo "ZONE=$CENTRIFYDC_ZONE_NAME" >> $ENV_FILE
    echo "ADDITIONAL_OPS=$CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS" >> $ENV_FILE
    echo "CENTRIFYDC_HOSTNAME_FORMAT=$CENTRIFYDC_HOSTNAME_FORMAT" >> $ENV_FILE
    
    chmod 644 $ENV_FILE
    
    # adjoin.sh needs the common.sh
    cp -f $centrifydc_deploy_dir/common.sh /etc/centrifydc/scripts/common.sh
    cp -f $centrifydc_deploy_dir/adjoin.sh /etc/centrifydc/scripts/systemd/adjoin.sh
    
    chmod 644 /etc/centrifydc/scripts/common.sh
    chmod 744 /etc/centrifydc/scripts/systemd/adjoin.sh
    
    SYSTEMD_PATH="/lib"
    if [ -d "/usr/lib/systemd/system" ]; then
        SYSTEMD_PATH="/usr/lib"
    fi
    
    cp -f $centrifydc_deploy_dir/centrifydc-adleave.service $SYSTEMD_PATH/systemd/system/centrifydc-adleave.service
    cp -f $centrifydc_deploy_dir/centrifydc-adjoin.service $SYSTEMD_PATH/systemd/system/centrifydc-adjoin.service
    
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifydc-adleave.service
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifydc-adjoin.service
    
    # need to start the centrifydc-adleave immediately so when stop instance, adleave will be executed.
    systemctl enable centrifydc-adleave.service --now
    systemctl enable centrifydc-adjoin.service 
}

function start_deploy()
{
    prepare_repo
    r=$? && [ $r -ne 0 ] && return $r
  
    install_packages
    r=$? && [ $r -ne 0 ] && return $r
  
    if [ "$CENTRIFYDC_JOIN_TO_AD" = "yes" ];then
      get_keytab_file
      r=$? && [ $r -ne 0 ] && return $r
  
      get_user_and_domain
      r=$? && [ $r -ne 0 ] && return $r
  
      generate_hostname
      r=$? && [ $r -ne 0 ] && return $r
  
      prepare_for_adjoin
      r=$? && [ $r -ne 0 ] && return $r
  
      do_adjoin
      r=$? && [ $r -ne 0 ] && return $r
      
      install_leave_join_service
    fi
  
    enable_sshd_password_auth
    r=$? && [ $r -ne 0 ] && return $r

    enable_sshd_challenge_response_auth
    r=$? && [ $r -ne 0 ] && return $r

    return 0
}

if [ "$DEBUG_SCRIPT" = "yes" ];then
    set -x
fi

krb5_cache_lifetime=10m

file_parent=`dirname $0`
source $file_parent/common.sh
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot source common.sh [exit code=$r]" && exit $r

detect_os
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: detect OS failed [exit code=$r]" && exit $r

check_supported_os centrifydc
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: current OS is not supported [exit code=$r]" && exit $r

check_config
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: error in configuration parameter settings [exit code=$r]" && exit $r

# SuSE11 will install python to  /usr/local/bin
export PATH=$PATH:/usr/local/bin
prerequisite
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot set up pre-requisites [exit code=$r]" && exit $r

start_deploy
r=$?
if [ $r -eq 0 ];then
  echo "$CENTRIFY_MSG_PREX: CentrifyDC successfully deployed!"
else
  echo "$CENTRIFY_MSG_PREX: error in CentrifyDC deployment [exit code=$r]!"
fi

clean_files
exit $r


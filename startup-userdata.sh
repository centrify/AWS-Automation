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
# Sample script for AWS deployment automation
#
# This sample script is to demonstrate how AWS instances can be orchestrated to
# enroll a computer in the Centrify identity platform using the Centrify agent;
# and/or join to Active Directory.
#
# This sample script downloads and executes additional scripts from Centrify github
# to perform the following tasks:
#  - Download and install the required packages from Centrify repository.
#  - Modify sshd configuration file to allow password authentication
#  - Enroll the instance to Centrify identify platform (if requested)
#  - Join the instance to Active Directory (if requested)
#
# This script is tested on AWS EC2 using the following EC2 AMIs:
# - Red Hat Enterprise Linux 7.3 or later               x86_64
# - Red Hat Enterprise Linux 8                          x86_64
# - Ubuntu Server 16.04 LTS (HVM)                       x86_64
# - Ubuntu Server 18.04 LTS (HVM)                       x86_64
# - Amazon Linux 2 LTS Candidate AMI (HVM)              x86_64
# - CentOS 7.x HVM                                      x86_64
# - CentOS 8.x HVM                                      x86_64
# - SUSE Linux Enterprise Server 12 SP4 (HVM)           x86_64
#
# Note that Amazon EC2 user data is limited to 16KB.   Please refer to README
# file for instructions and other information.

####### Set Configuration Parameters ##########################
# This specifies whether the script will install CentrifyCC and 
# enroll to Centrify Identity Platform.  
# Allowed value: yes/no (default: yes)
export DEPLOY_CENTRIFYCC=yes

# This specifies whether the script will install CentrifyDC.
# Allowed value: yes/no (default: yes)
export  DEPLOY_CENTRIFYDC=yes

####### Set Configuration Parameters for CentrifyCC ###########
# The CIP instance to enroll to.  Cannot be empty.
export CENTRIFYCC_TENANT_URL=

# The enrollment used to enroll.  Cannot be empty.
export CENTRIFYCC_ENROLLMENT_CODE=

# Specify the CIP roles (as a comma separated list) where members can log in to the instance.
export CENTRIFYCC_AGENT_AUTH_ROLES=

# Specify the sets (as a comma separated list) where this machine will be a member of.
# A value must be specified in CENTRIFYCC_AGENT_SETS and/or CENTRIFYCC_AGENT_AUTH_ROLES
export CENTRIFYCC_AGENT_SETS=''

# Specify the features (as a comma separated list) to enable in cenroll CLI.
# Cannot be empty.
export CENTRIFYCC_FEATURES=

# Specify what to use as the network address in created CPS resource.   
# Allowed values:  PublicIP, PrivateIP, HostName.  Default: PublicIP
export CENTRIFYCC_NETWORK_ADDR_TYPE=PublicIP

# Specify the prefix to use as the hostname in CPS.   
# The hostname will be shown as <prefix>-<AWS instance ID> in CPS.
# If it is empty, then cenroll will use <AWS instance ID> instead.
export CENTRIFYCC_COMPUTER_NAME_PREFIX=

# This specifies which addtional options will be used.
# Default we will use following options to cenroll:
#  /usr/sbin/cenroll \
#        --tenant "$CENTRIFYCC_TENANT_URL" \
#        --code "$CENTRIFYCC_ENROLLMENT_CODE" \
#        --agentauth "$CENTRIFYCC_AGENT_AUTH_ROLES" \ (if specified)
#        --resource-set "$CENTRIFYCC_AGENT_SETS" \ (if specified)
#        --features "$CENTRIFYCC_FEATURES" \
#        --name "$CENTRIFYCC_COMPUTER_NAME_PREFIX-<aws instance id>" \
#        --address "$CENTRIFYCC_NETWORK_ADDR"
#
# The options shall be list(separated by space) such as --resource-setting ProxyUser:centrify .
export CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS=''



####### Set Configuration Parameters for CentrifyDC ###########
# The user name and password required to access Centrify repository.  
# Must be specified if DEPLOY_CENTRIFYDC is yes.
export CENTRIFY_REPO_CREDENTIAL=

# This specifies whether the agent will join to on-premise Active Directory directly. 
# Allowed value: yes/no (default: yes)
export CENTRIFYDC_JOIN_TO_AD=yes

# The name of the zone to join to.  Cannot be empty.
export CENTRIFYDC_ZONE_NAME=

# Specify how to create the host name for the computer in Active Directory.
# Allowed values: INSTANCE_ID, PRIVATE_IP (default:PRIVATE_IP).
# Note that hostname is limited to max of 15 characters, 
# so only the first 15 characters of instance ID is used if INSTANCE_ID is specified.
export CENTRIFYDC_HOSTNAME_FORMAT=PRIVATE_IP

#Specify how the login.keytab will be obtained, either through a custom function or 
#by standard download from the s3 bucket. Optional -- default download through s3 bucket (default: no).
export CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION=no

#Define the custom function to be used to download the login.keytab if 
#CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION=yes in my_function(). Do not change anything if 
#downloading from an s3 bucket (default).

my_function()
{
	# replace the line below with your function 
	:
}
export -f my_function
export CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION=my_function

# This specifies a s3 bucket to download the login.keytab that has the credential of 
# the user who joins the computer to AD. Note that the startup script will use AWS CLI
# to download this file.  Leave empty if retreiving the login.keytab from external 
#function (CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION=yes).
export CENTRIFYDC_KEYTAB_S3_BUCKET=

# This specifies whether to install additional Centrify packages. 
# The package names shall be separated by space.
# Allowed value: centrifydc-openssh centrifydc-ldapproxy (default: none).
# For example: CENTRIFYDC_ADDITIONAL_PACKAGES="centrifydc-openssh centrifydc-ldapproxy"
export CENTRIFYDC_ADDITIONAL_PACKAGES=''

# This specifies additional adjoin options.
# The additional options shall be a list separated by space.
# Default we will run adjoin with following options:
# /usr/sbin/adjoin $domain_name -z $ZONE_NAME --name `hostname`
export CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS=''



# This specifies whether the script of centrifydc.sh/centrifycc.sh will enable 'set -x'.
# Allowed values are yes|no (default no).
export DEBUG_SCRIPT=no

####### End Configuration Parameters ###########

set -x
# Where to download centrifycc rpm package.
export CENTRIFYCC_DOWNLOAD_PREFIX=https://edge.centrify.com/products/cloud-service/CliDownload/Centrify
CENTRIFY_MSG_PREX='Orchestration(user-data)'
TEMP_DEPLOY_DIR=/tmp/auto_centrify_deployment
rm -rf $TEMP_DEPLOY_DIR
mkdir -p $TEMP_DEPLOY_DIR
if [ $? -ne 0 ];then
  echo "$CENTRIFY_MSG_PREX: create temporary Centrify deployment directory failed!"
  logger "$CENTRIFY_MSG_PREX: create temporary Centrify deployment directory failed!"
  exit 1
fi

export CENTRIFY_GIT_PREFIX_URL=https://raw.githubusercontent.com/centrify/AWS-Automation/master
if [ "$DEPLOY_CENTRIFYDC" = "yes" ];then
  export CENTRIFY_MSG_PREX='Orchestration(CentrifyDC)'
  export centrifydc_deploy_dir=$TEMP_DEPLOY_DIR/centrifydc
  mkdir -p $centrifydc_deploy_dir
  # Download deployment script from github.
  scripts=("common.sh" "centrifydc.sh" "centrifydc-adleave.service" "centrifydc-adjoin.service" "adjoin.sh")
  for script in ${scripts[@]} ;do
    curl --fail \
		 -s \
         -o $centrifydc_deploy_dir/$script \
         -L "$CENTRIFY_GIT_PREFIX_URL/$script" >> $centrifydc_deploy_dir/deploy.log 2>&1
    r=$?
    if [ $r -ne 0 ];then
        echo "curl download $script failed [exit code=$r]" >> $centrifycc_deploy_dir/deploy.log 2>&1
        exit $r
    fi
  done
  chmod u+x $centrifydc_deploy_dir/centrifydc.sh
  $centrifydc_deploy_dir/centrifydc.sh   >> $centrifydc_deploy_dir/deploy.log 2>&1
fi

if [ "$DEPLOY_CENTRIFYCC" = "yes" ];then
  export CENTRIFY_MSG_PREX='Orchestration(CentrifyCC)'
  export centrifycc_deploy_dir=$TEMP_DEPLOY_DIR/centrifycc
  mkdir -p $centrifycc_deploy_dir
  # Download deployment script from github.
  scripts=("common.sh" "centrifycc.sh" "centrifycc-unenroll.service" "centrifycc-enroll.service" "cenroll.sh")
  for script in ${scripts[@]} ;do
    curl --fail \
		 -s \
         -o $centrifycc_deploy_dir/$script \
         -L "$CENTRIFY_GIT_PREFIX_URL/$script" >> $centrifycc_deploy_dir/deploy.log 2>&1
    r=$?
    if [ $r -ne 0 ];then
        echo "curl download $script failed [exit code=$r]" >> $centrifycc_deploy_dir/deploy.log 2>&1
        exit $r
    fi
  done
  chmod u+x $centrifycc_deploy_dir/centrifycc.sh
  $centrifycc_deploy_dir/centrifycc.sh   >> $centrifycc_deploy_dir/deploy.log 2>&1
fi



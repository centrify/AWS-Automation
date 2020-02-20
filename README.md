# Introduction

This is the README file for using sample orchestration scripts to automatically
enroll Linux-based cloud instances to Centrify Identity Platform or
to automatically join the instance to Active Directory.

You need to set up your configuration by modifying the top part of the sample orchestration
script startup-userdata.sh.  When you launch the new EC2 instance, you 
need to upload the script as "user data".  

The following platforms are supported:
* Red Hat Enterprise Linux 7.5 or later
* Ubuntu Server 16.04 LTS
* Ubuntu Server 18.04 LTS
* Amazon Linux AMI 2018.03.0
* Amazon Linux 2
* CentOS 7.x
* SUSE Linux Enterprise Server 12 SP4

# Prerequisite
- You need the following AWS permissions:
  - Full permission to EC2
- If you need to use Centrify Infrastructure Services to join the AWS instance to Active Directory, 
  you also need the followings:
  -  An AD user who joins the EC2 instance for Linux to your centrify zone. 
     You need to make sure that the AD user has following two permissions at least:
    - Delegate `Join a computer to the domain` in `Active Directory Users and Computers`.
    - Delegate 'Join comupters to the zone' in `Centrify Access Manager`.
  - Permission to create and upload files to a S3 bucket
  - permisison to create, modify, read, list and delete IAM Policies and Roles
  - An EC2 instance that has Centrify Infrastructure Services installed and joined to your Active Directory.
  - An account in the Centrify Support website 
	 (http://www.centrify.com/support).   Follow the instruction in 
	 https://www.centrify.com/support/customer-support-portal/repos to generate the repo key. Use the string
	 before @repo.centrify.com to set up the parameter CENTRIFY_REPO_CREDENTIAL.  For example, if the repo key 
	 is 1111111122222233333333333333344444555555:777888880000099999991234567890abcdefghij@repo.centrify.com, set
	 CENTRIFY_REPO_CREDENIIAL=1111111122222233333333333333344444555555:777888880000099999991234567890abcdefghij

# Configuration parameters
You can specify the AWS deployment configuration in the `User Data` of the AWS instance.   You need to download the file 
startup-userdata.sh and set up the parameter values in the top part of the file.  The whole file must be copied to 
the `User Data` of the new EC2 instance and/or Auto Scaling group launch configuration.

## Centrify Agent for Linux parameters
The following parameters are for enrolling the AWS instances to Centrify Identity Platform.

| Parameter | Description | Optional | Example |
| --- | --- | --- | --- | 
| DEPLOY_CENTRIFYCC | Specifies enroll to Centrify Identity Platform | no | yes |
| CENTRIFYCC_TENANT_URL | Centrify Identity Platform URL | no | *my-company.deployment.centrify.com* |
| CENTRIFYCC_ENROLLMENT_CODE | Enrollment code to use | no | *12345678-1234-5678-1234-ABCDEF123456* |
| CENTRIFYCC_AGENT_AUTH_ROLES | Roles where members can log in to the instance.  Specifies as a comma separated list | yes | *my_login_role* |
| CENTRIFYCC_AGENT_SETS | Sets that the machine will be added as a member. Specifies as a comma separated list | yes | *my_machine_sets* |
| CENTRIFYCC_FEATURES | Features to enable for the agent.  Specifies as a comma separated list.  Valid values are: **agentauth**, **aapm**, **all** | no | agentauth,aapm |
| CENTRIFYCC_NETWORK_ADDR_TYPE | Value to use to as network address for the created resource.  Allowed values are PublicIP, PrivateIP, Hostname. | no | PublicIP |
| CENTRIFYCC_COMPUTER_NAME_PREFIX | Prefix to use for computer name | yes | *apac* |
| CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS | Additional options for cenroll command line | yes | --resource-setting ProxyUser:centrify | 

Notes:
- The AWS instance ID used as the computer name for the created resource.  If CENTRIFYCC_COMPUTER_NAME_PREFIX is specified, the computer name 
  will be *\<CENTRIFYCC_COMPUTER_NAME_PREFIX\>*-*\<AWS Instance ID\>*.  Otherwise, it will be *\<AWS Instance ID\>*.
- Both CENTRIFYCC_AGENT_AUTH_ROLES and CENTRIFYCC_AGENT_SETS cannot be empty.



## Centrify Infrastructure Services agent parameters
The following parameters are for joining to Active Directory using the Centrify Infrastructure Services agent.

| Parameter | Description | Optional | Example |
| --- | --- | --- | --- | 
| DEPLOY_CENTRIFYDC | Install Centrify Infrastructure Services agent | no | yes |
| CENTRIFY_REPO_CREDENTIAL | Credential required to access Centrify Repo | no | *a long string* |
| CENTRIFYDC_JOIN_TO_AD | Whether to join to Active Directory | no | yes |
| CENTRIFYDC_ZONE_NAME | Name of zone to join to | no | *my_zone* |
| CENTRIFYDC_HOSTNAME_FORMAT | How to generate host name to use in Active Directory.  Valid values are PRIVATE_IP, INSTANCE_ID. See note below | no | PRIVATE_IP |
| CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION | Whether login.keytab is retrieved using default method or a custom function provided by user. | no | yes |
| CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION | The name of the custom function used to retrieve login.keytab file. | yes | my_function |
| custom_keytab_function | Customized function for retrieving the login.keytab file.  Function name is specified in CENTRIFYDC_CUSTOM_KEYTAB_FUNCTION | yes, if using customized function; no for default download. Be sure to save the login.keytab file to /tmp/auto_centrify_deployment/centrifydc; return 0 for success, others for error | wget -O /tmp/auto_centrify_deployment/centrifydc/login.keytab https://your_bucket_name.s3.amazonaws.com/path/to/file <br> r=$? <br> return $r|
| CENTRIFYDC_KEYTAB_S3_BUCKET | Name of S3 bucket where the login.keytab file for the enroller is stored | no, if using customized function; yes for defualt download | *my_s3_bucket* |
| CENTRIFYDC_ADDITIONAL_PACKAGES | Name of additional packages to install.  Allowed values are: **centrifydc-openssh**, **centrifydc--ldapproxy** | yes | |
| CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS | Additional options for adjoin command | yes | |

Note that host name is limited to 15 characters.  If the instance ID is longer than 15 characters, the first 15 characters of instance ID will be used 
and there is a remote possibility of hostname conflicts.   We recommend to use PRIVATE-IP address for hostname.


# Deployment process
  1. If you do not need to install/deploy Centrify Infrastructure Services agent to join to Active Directory,
     you can skip directly to step 3.  
	 </br>
	 Generate login.keytab using following command on your Linux/Unix that has joined
     to Active Directory:
     ```
     adkeytab -A -K login.keytab -u your_admin -p your_admin_password your_ad_user
     ```
     where 
	 - *your_admin* is the name of an user who is permitted to adopt the account *your_ad_user*
	 - *your_admin_password* is the password of *your_admin*
     - *your_ad_user* is the user who joins the instance to Active Directory. 
	For example:</br>
	```
     adkeytab -A -K login.keytab -u admin1  -p admin1_pass join_user1
	```
	
  1. If you are using a customized function to get the login.keytab file, you can skip to step 3.
  	 </br>
     You need to sign in https://console.aws.amazon.com/s3 to create a S3 bucket and then upload 
     login.keytab file (created in step 1) to the bucket. You can refer to
     http://docs.aws.amazon.com/AmazonS3/latest/gsg/CreatingABucket.html about how to create a bucket.

  1. Create your Key Pair if you don't have one so that you can log into your EC2 instances. You can refer to</br>
      http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair about 
      how to create Key Pair.

  1. Create VPC, subnet and security group for your new EC2 instances.
  
  1. If your AWS instance does not need to join to Active Directory, or if it needs to join to Active Directory but you
  	 are using a customized function to get login.keytab, skip to step 6.</br>
     1. Create the following IAM Policy to allow the instance to access the S3 bucket to download the login.keytab file:</br>
        ```
        {
            "Version": "2012-10-17",
            "Statement": [{ 
            "Effect": 
                "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:ListObject"
                    ],
                "Resource": [
                    "arn:aws:s3:::your_s3_bucketname/*"
                ]
            }]
        }
        ```
        </br>Replace *your_s3_bucketname* by the name of the S3 bucket that you created in step 2.
	 1. Create IAM Role for the AWS instance:
      - Select IAM Service in AWS Console
	  - Select Roles, and click on `Create role`.
	    - Select `AWS service` as type of trusted entity
		- Select `EC2` as the service to use the role
		- Select `EC2` as the use case
		- Click on `Next: Permissions` to continue.
      - In the `Attach permissions policies` page, select the IAM policy created above.
		- Click on `Next: Review` to continue.
	  - Enter your role name and description, click `Create role`.

  1. Download startup-userdata.sh and create an userdata template.  See the section **Configuration Parameters** for more information.
  	 If CENTRIFYDC_USE_CUSTOM_KEYTAB_FUNCTION=yes, be sure to define a valid function with its necessary prerequisites.
  
  1. Create a new EC2 instance. If you set the configuration parameter CENTRIFYCC_NETWORK_ADDR_TYPE to PublicIP, you need to select your subnet you can access public internet in. Set up user data from the userdata template created in step 6 above.

# FAQ

Q. Can I only install CentrifyDC but not join to AD?

Yes. You can set CENTRIFYDC_JOIN_TO_AD to no in the user data.  You also do not need to specify CENTRIFYDC_KEYTAB_S3_BUCKET and CENTRIFYDC_ZONE_NAME.

Q. Can I specify additional packages to be installed for CentrifyDC?

Yes. You can specify additional packages in parameters CENTRIFYDC_ADDITIONAL_PACKAGES.

Q. Can I specify additional options for adjoin or cenroll?

Yes. You can specify additional options in parameter CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS
or CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS.

Q. Can I output debug information?

Yes. You can set DEBUG_SCRIPT to yes and the centrifydc.sh/centrifycc.sh will enable 'set -x'.

Q. Can I specify what to use as the network address in created CPS resource?

Yes. You can set parameter CENTRIFYCC_NETWORK_ADDR_TYPE to specify public
IP(set to PublicIP), private IP(set to PrivateIP), or host name(set to HostName)
as your network address in CPS resource.

Q. Can I specify my computer name in Active Directory while adjoin?

Yes. You can set CENTRIFYDC_HOSTNAME_FORMAT. Currently we only support using 
aws instance id(set to INSTANCE_ID) or private IP(set to PRIVATE_IP) as your computer name.

Q. Why don't I get Public IP while enroll EC2 for Linux to Centrify identity?

You shall make sure that your AutoScaling/EC2 has enabled public IP assignment and
set CENTRIFYCC_NETWORK_ADDR_TYPE to PublicIP if you want to use public IP as your
address while running cenroll. If you want to use hostname or private IP as your
address parameter of cenroll, you need not a public IP for your EC2 and only need to 
set CENTRIFYCC_NETWORK_ADDR_TYPE parameter to PrivateIP or HostName.

Q. Can I view any log output after running startup-userdata.sh?

Yes. You can find the log in /tmp/auto_centrify_deployment/centrifycc/deploy.log
for CentrifyCC and in /tmp/auto_centrify_deployment/centrifydc/deploy.log for CentrifyDC.

Q. What does error "x509: certificate signed by unknown authority" mean?

Your computer needs to be enrolled to Centrify Identity Platform, but none of
the server certificates can be verified. Certificate problems may indicate
potential security risks. Please contact your administrator to configure the
root CA certificate.
References:
  - https://centrify.force.com/support/Article/KB-7973-How-to-configure-Linux-machine-trusted-certificate-chain-to-perform-enrollment-for-Centrify-Agent

Q. How to use "user data" to run orchestration script on AWS instances?

From AWS documentation:

"Scripts entered as user data are executed as the root user, so do not use the
sudo command in the script. Remember that any files you create will be owned by
root; if you need non-root users to have file access, you should modify the
permissions accordingly in the script. Also, because the script is not run
interactively, you cannot include commands that require user feedback (such as
yum update without the -y flag)." [1]

"User data is limited to 16 KB." [2]

References:
[1] Running Commands on Your Linux Instance at Launch
  - http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html

[2] Instance Metadata and User Data
  - http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html


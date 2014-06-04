#!/bin/bash -
# Original author: Colin Johnson / colin@cloudavail.com
# Date: 2012-02-27
# Version 0.5
# License Type: GNU GENERAL PUBLIC LICENSE, Version 3
# Edited by Monica Colangelo / monica.colangelo@gmail.com
# Date: 2014-05-22
# Version 0.5-1
#####
#as-update-launch-config start

#determines that the user provided AMI does, in fact, exit
imageidvalidation()
{
    if [[ -n $imageid ]] ; then
	#amivalid redirects stderr to stdout - if the user provided AMI does not exist, the if statement will exit as-update-launch-config.sh else it is assumed that the user provided AMI exists
        amivalid=`aws ec2 describe-images --image-ids $imageid --region $region --output text 2>&1`
	if [[ $amivalid =~ "InvalidAMIID.NotFound" ]]
		then echo "The AMI ID $imageid could not be found. If you specify an AMI (-m) it must exist and be in the given region (-r). Note that region (-r defaults to \"eu-west-1\" if not given." 1>&2 ; exit 64
	else echo "The user provided AMI \"$imageid\" will be used when updating the Launch Configuration for the Auto Scaling Group \"$asgroupname.\""
	fi
    else
        echo "You did not specify an AMI. You must specify a valid AMI" 1>&2 ; exit 64
    fi
}

#confirms that executables required for succesful script execution are available
prerequisitecheck()
{
	for prerequisite in basename cut curl date head grep aws
	do
		#use of "hash" chosen as it is a shell builtin and will add programs to hash table, possibly speeding execution. Use of type also considered - open to suggestions.
		hash $prerequisite &> /dev/null
		if [[ $? == 1 ]] #has exits with exit status of 70, executable was not found
			then echo "In order to use `basename $0`, the executable \"$prerequisite\" must be installed." 1>&2 ; exit 70
		fi
	done
}

#calls prerequisitecheck function to ensure that all executables required for script execution are available
prerequisitecheck

#sets as-update-launch-config Defaults
region="eu-west-1"
dateymdHMS=`date +\%Y\%m\%d-\%H\%M\%S`

#handles options processing
while getopts :a:i:u:b:s:p:r:m: opt
	do
		case $opt in
			a) asgroupname="$OPTARG";;
			i) instancetype="$OPTARG";;
			u) userdata="$OPTARG";;
			b) bits="$OPTARG";;
			s) storage="$OPTARG";;
			p) preview="$OPTARG";;
			r) region="$OPTARG";;
			m) imageid="$OPTARG";;
			*) echo "Error with Options Input. Cause of failure is most likely that an unsupported parameter was passed or a parameter was passed without a corresponding option." 1>&2 ; exit 64 ;;
		esac
	done

#sets previewmode - will echo commands rather than performing work
case $preview in
	true|True) previewmode="echo"; echo "Preview Mode is set to $preview" 1>&2 ;;
	""|false|False) previewmode="";;
	*) echo "You specified \"$preview\" for Preview Mode. If specifying a Preview Mode you must specific either \"true\" or \"false.\"" 1>&2 ; exit 64 ;;
esac

# instance-type validator
case $instancetype in
	t1.micro|m1.small|c1.medium|m1.medium) bits=$bits ; 
	# bit depth validator for micro to medium instances - demands that input of bits for micro to medium size instances be 32 or 64 bit
		if [[ $bits -ne 32 && bits -ne 64 ]]
			then echo "You must specify either a 32-bit (-b 32) or 64-bit (-b 64) platform for the \"$instancetype\" EC2 Instance Type." 1>&2 ; exit 64
		fi ;;
	m1.large|m1.xlarge|m2.xlarge|m2.2xlarge|m2.4xlarge|c1.xlarge|cc1.4xlarge) bits=64;;
	"") echo "You did not specify an EC2 Instance Type. You must specify a valid EC2 Instance Type (example: -i m1.small or -i m1.large)." 1>&2 ; exit 64;;
	*) echo "The \"$instancetype\" EC2 Instance Type does not exist. You must specify a valid EC2 Instance Type (example: -i m1.small or -i m1.large)." 1>&2 ; exit 64;;
esac

# user-data validator
if [[ ! -f $userdata ]]
	then echo "The user-data file \"$userdata\" does not exist. The instance will be launched without userdata." 1>&2 ;
fi

# storage validator
case $storage in
	ebs|EBS) storage=EBS;;
	s3|S3) storage=S3;;
	"") storage=EBS ;; # if no storage type is set - default to EBS
	*) echo "The \"$storage\" storage type does not exist. You must specify a valid storage type (either: -s ebs or -s s3)." 1>&2 ; exit 64;;
esac

# region validator
case $region in
	us-east-1|us-west-2|us-west-1|eu-west-1|ap-southeast-1|ap-northeast-1|sa-east-1|ap-southeast-2) ;;
	*) echo "The \"$region\" region does not exist. You must specify a valid region (example: -r us-east-1 or -r us-west-2)." 1>&2 ; exit 64;;
esac

# as-group-name validator - need to also include "command not found" if as-describe-auto-scaling-groups doesn't fire
if [[ -z $asgroupname ]]
	then echo "You must specify an Auto Scaling Group name (example: -a asgname)." 1>&2 ; exit 64
fi

#creates list of Auto Scaling Groups
asgresult=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asgroupname --region $region --max-items 1000 --output text`

#user response for Auto Scaling Group lookup - alerts user if Auto Scaling Group was not found.
if [[ $asgresult == "" ]]
	then echo "The Auto Scaling Group named \"$asgroupname\" does not exist. You must specify an Auto Scaling Group that exists." 1>&2 ; exit 64
fi

#if $imageid has a length of non-zero call imageidvalidation else call getimageid.
imageidvalidation

#gets current launch-config
launch_config_current=`echo $asgresult | cut -d ' ' -f9`

aslcresult=`aws autoscaling describe-launch-configurations --launch-configuration-names $launch_config_current --region $region --output text`

launch_config_security_groups=`echo $aslcresult | tr " " "\n" | while read W;do echo $W | grep -qi sg- ;if [ $? -eq 0 ];then echo $W;fi;done`
launch_config_key=`echo $aslcresult | cut -d ' ' -f8`

echo "The Auto Scaling Group \"$asgroupname\" uses the security groups \"$launch_config_security_groups\"." 1>&2
echo "The Auto Scaling Group \"$asgroupname\" uses the key \"$launch_config_key.\"" 1>&2

launchconfig_new="$asgroupname-$dateymdHMS"

echo "A new Launch Configuration named \"$launchconfig_new\" for Auto Scaling Group \"$asgroupname\" will be created using EC2 Instance Type \"$instancetype\" and AMI \"$imageid.\""

#Create Launch Config
if [[ ! -z $userdata ]] ; then
    aws autoscaling create-launch-configuration --launch-configuration-name $launchconfig_new --image-id $imageid --instance-type $instancetype --region $region --key-name $launch_config_key --security-groups $launch_config_security_groups --user-data $userdata
else
    aws autoscaling create-launch-configuration --launch-configuration-name $launchconfig_new --image-id $imageid --instance-type $instancetype --region $region --key-name $launch_config_key --security-groups $launch_config_security_groups
fi

#Update Auto Scaling Group
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $asgroupname --region $region --launch-configuration-name $launchconfig_new

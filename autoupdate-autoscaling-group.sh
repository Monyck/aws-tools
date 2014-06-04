#!/bin/bash -
# Original author: Ravi Gadgil
# Edited by Monica Colangelo / monica.colangelo@gmail.com
# Date: 2014-05-23
# Version 0.1-1
#####
# Script to create ami of running instance, make launch Conf from it and than add it to Auto Scaling group

 #To get the current Instance ID
instance_id=`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`

 #To get the current Instance Type
instance_type=`wget -q -O - http://169.254.169.254/latest/meta-data/instance-type`

 #To create a unique AMI name for this script
ami_name="$instance_id-autoAMI-$(date +\%Y\%m\%d-\%H\%M\%S)"

 #To create a unique Launch Conf name for this script
launch_conf="autoLaunchConf-$(date +\%Y\%m\%d-\%H\%M\%S)"

echo ""
echo "Starting the AMI creation with name as $ami_name"
echo ""

 #Creating AMI of current server by taking above values
aws ec2 create-image --instance-id $instance_id --name "$ami_name" --description "autoAMI from $instance_id created at `date +\%Y\%m\%d-\%H\%M\%S`" --no-reboot | grep -ir ami | awk '{print $4}' > /tmp/amiID.txt

 #Showing the AMI name created by AWS
echo "AMI ID is `cat /tmp/amiID.txt`"

echo ""

 #Showing the parameters which will be used while creating the Launch Conf
echo "Creating the launch config as `cat /tmp/launchConf.txt` with key as mykey.pem Instance type `cat /tmp/instanceType.txt` and security group ravi-test"
echo ""

 #Creating the Launch Config with defining the key name to be used and security group
aws autoscaling create-launch-configuration --launch-configuration-name `cat /tmp/launchConf.txt` --image-id `cat /tmp/amiID.txt` --instance-type `cat /tmp/instanceType.txt` --key-name mykey --security-groups ravi-test --iam-instance-profile test1
echo "The launch Config created succesfully as `cat /tmp/launchConf.txt`"
echo ""
echo "Updating the Auto scaling Group test-prod-autoscaling with new launch Conf"

 #Updating the auto scaling group with new launch Conf
aws autoscaling update-auto-scaling-group --auto-scaling-group-name test-prod-autoscaling --launch-configuration-name `cat /tmp/launchConf.txt`

#some happy faces after all done well :)
echo "The Auto scaling group is updated succesfully...:)"
#!/bin/bash
#
# aws_ephemeral_swap.sh
# version: 1.0
# date: 2014 June 04
# author: Monica Colangelo (monica.colangelo@gmail.com)
#
# This script unmounts ephemeral disk from its predefined mountpoint
# and uses it as swap space. It is intended to be used in rc.local
# to auto-mount swap space at boot time

# Search for drive scheme
root_drive=`df -h | grep -v grep | awk 'NR==2{print $1}'`

if [ "$root_drive" == "/dev/xvda1" ]; then
  echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='sd'
fi

# Search for ephemeral disk
device_name=`curl -s http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`
if [ -z "${device_name}" ]; then
        echo "Ephemeral device not found. Exiting..."
        exit 0
fi

device_name=$(echo $device_name | sed "s/sd/$DRIVE_SCHEME/")
device_path="/dev/$device_name"
  
# test that the device actually exists since you can request more ephemeral drives than are available
# for an instance type and the meta-data API will happily tell you it exists when it really does not.
if [ -b $device_path ]; then
    echo "Detected ephemeral disk: $device_path"
else
    echo "No ephemeral disk detected. Exiting"
    exit 0
fi

# Check if ephemeral disk is mounted
MOUNTED=`mount | grep $device_path`
if [ -n "${MOUNTED}" ]; then
    echo "WARNING: Ephemeral device $device_path is mounted. I will try to unmount it..."
    MY_MP=`df $device_path | awk 'NR==2{print$6}'`
    umount ${MY_MP}
    if [[ `echo $?` -ne 0 ]]; then
        echo "ERROR: cannot umount. Exiting"
        exit 1
    fi
fi

# Check if fstab will try to remount the disk and comment the entry if needed
commented=`egrep ^#$device_path /etc/fstab`
if [[ -z $commented ]]; then
    sed -i "s|$device_path|# AUTO COMMENTED TO ENABLE SWAP\n#$device_path|g" /etc/fstab
fi

# If is not mounted, initialize the disk, create the swap partition and activate it.
echo "Creating and activating swap... "
mkswap -f -L ephemeral-swap $device_path
swapon -f $device_path

exit 0
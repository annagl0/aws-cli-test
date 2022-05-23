#!/bin/bash
# ------------------------------------------------------------------
# Name:         ec2-create.sh
#
# Author:       PlaiView
# Version:      1.0
# Created Date: 18-05-2022
#
# Purpose:      PlaiView EC2 creation script
#
# OS:           Ubuntu
# Usage:        ./ec2-create.sh
#
# Set of IAM permissions needed for the script:
#
# "ec2:DescribeImages",
# "ec2:DescribeInstanceAttribute",
# "ec2:DescribeInstanceStatus",
# "ec2:DescribeSubnets",
# "ec2:AllocateAddress",
# "ec2:AuthorizeSecurityGroupIngress",
# "ec2:AssociateAddress",
# "ec2:CreateSecurityGroup",
# "ec2:CreateTags",
# "ec2:RunInstances"
# ------------------------------------------------------------------

# START #

# ------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Default AMI ID to use, change it
NAME="test-ec2-9"
AMI_ID="ami-0c4f7023847b90238";
INS_TYPE="t2.micro"
KEY_NAME="$NAME"
REGION="us-east-1"
VOLUME_SIZE=8GB

#aws ssm create-activation \
#  --default-instance-name "test.py-ec2-9" \
#  --description "Activation for EC2 instance" \
#  --iam-role AmazonEC2RunCommandRoleForManagedInstances \
#  --registration-limit 10 \
#  --region "us-east-1" \
#  --tags Key=Name,Value="test.py-ec2-9"

PORT=8080

# ------------------------------------------------------------------------
# Temp log files
TMP="/tmp/tmp.log";
AMI_FILE="/tmp/amis.log";
SG_FILE="/tmp/secgroup.log"
INS_FILE="/tmp/instance.log";
VOL_FILE="/tmp/vol.log";
STATUS_FILE="/tmp/status.log";
EIP_FILE="/tmp/eip.log";


# ------------------------------------------------------------------------
# sudo check
# ------------------------------------------------------------------------

if [ "$EUID" -eq "0" ]; then
  echo "Please be nice and don't run as root.";
  exit 1;
fi

# ------------------------------------------------------------------------
# AWS CLI configuration and test.py
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Check if aws-cli is installed
_verify_aws_installation(){
  type aws >/dev/null 2>&1 || { echo "ERROR: I require awscli, but it's not installed. Aborting.
  To fix this on Debian/Ubuntu, do:
  # apt-get install python2.7 python-pip
  # pip install awscli";
  exit 1; };
}

# ------------------------------------------------------------------------
# Check AWS credentials
_verify_aws_access(){
  # Provide your AWS keys below
#  ACCESS_KEY="AKIAWLJEMOY27VUSUMZB";
#  SECRET_KEY="kHFigb3JMXJ5egNWt0y3Vp1OKk+EeXgdlyANL6AF";

  if [ ! -d ""$HOME"/.aws" ]; then
    mkdir "$HOME"/.aws ;
  fi

cat > "$HOME"/.aws/config << EOL
[default]
region = $REGION
aws_access_key_id = $ACCESS_KEY
aws_secret_access_key = $SECRET_KEY
output = text
EOL
}

# ------------------------------------------------------------------------
# Check AWS connection
_verify_aws_connection(){
  if aws ec2 describe-instances >/dev/null 2>&1; then
    echo -e "\nTest connection to AWS was successful.";
  else
    echo -e "\nERROR: test connection to AWS failed. Please check the AWS keys.";
    exit 1;
  fi
}


# ------------------------------------------------------------------------
# Instance security groups setup
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# key pair creation
_create_key_pair(){
  aws ec2 create-key-pair --key-name $KEY_NAME --tag-specification "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEY_NAME}]" --query "KeyMaterial" --output text > $KEY_NAME.pem
  KEY_FILE=$KEY_NAME.pem
  chmod 400 $KEY_FILE
}

# ------------------------------------------------------------------------
# security group creation
_create_security_group(){
  echo -e "\nCreating "$NAME" security group.";
  if ! aws ec2 create-security-group --group-name "$NAME" --description "$NAME" >"$SG_FILE"; then
    echo -e "\nERROR: failed to create a security group. Please check the AMI permissions.";
    exit 1;
  fi
  SECGRP_ID=$(cut -f1 "$SG_FILE");
}

# ------------------------------------------------------------------------
# open port in instance
_open_port(){
  _security_group_id=$1
  _port=$2
  _cidr=$3
  if ! aws ec2 authorize-security-group-ingress --group-id "$_security_group_id" --protocol tcp \
    --port "$_port" --cidr "$_cidr" >/dev/null; then
    echo -e "\nERROR: failed to modify a security group. Please check the AMI permissions.";
    exit 1;
  fi

  echo "TCP port "$_port" has been opened for "$_cidr" on the "$NAME" security group.";
}

# ------------------------------------------------------------------------
# ports opening
# Note: 22 is SSH port
_open_ports(){
  CIDR="0.0.0.0/0"
  _open_port $SECGRP_ID 22 $CIDR
  _open_port $SECGRP_ID $PORT $CIDR
}


# ------------------------------------------------------------------------
# EC2 instance creation
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Instance details verification
_verify_ec2_configs(){
  echo -e "\n(9) Details to use for the new "$NAME" instance:\n";
  echo -e "NAME:\t"$NAME"";
  echo -e "AMI:\t"$AMI_ID"";
  echo -e "TYPE:\t"$INS_TYPE"";
  echo -e "VOLUME_SIZE:\t"$VOLUME_SIZE"\n";

  while true; do
    read -p "Do you wish to use continue (y/n)? " yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) echo "Exiting." && exit 1;;
      * ) echo "Please answer 'y' or 'n'.";;
    esac
  done
}


# ------------------------------------------------------------------------
# ec2 creation
_create_ec2(){
  echo "Creating "$NAME" "$INS_TYPE" instance inside "$AV_ZONE".";
  if ! aws ec2 run-instances  \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INS_TYPE" \
    --key-name $KEY_NAME  \
    --security-group-ids "$SECGRP_ID" \
    --disable-api-termination \
    --monitoring Enabled=false \
    --instance-initiated-shutdown-behavior stop \
    --no-ebs-optimized \
    --associate-public-ip-address \
    --user-data file://aws-cmd-install.txt \
    >"$INS_FILE";then
    echo -e "\nERROR: failed to run a new instance. Please check the AMI permissions.";
    exit 1;
  fi

  # Get the instance ID
  INS_ID=$(grep -wo "i-................." "$INS_FILE");
  INSTANCE_DNS_NAME=$(aws ec2 describe-instances --instance-ids $INS_ID --query 'Reservations[].Instances[].PublicDnsName')

  echo ""$NAME" instance has been started. Instance ID is: "$INS_ID"";
  echo ""$NAME" instance has been started. Instance DNS NAME is: "$INSTANCE_DNS_NAME"";
  echo "Instance termination protection has been enabled.";
  sleep 10;
}

# ------------------------------------------------------------------------
# ec2 tags setup
_create_ec2_tags(){
  echo "Adding "$NAME" tag to the new instance."
  if ! aws ec2 create-tags --resources "$INS_ID" --tags Key=Name,Value="$NAME" >/dev/null; then
    echo -e "\nERROR: failed to create tags. Please check the AMI permissions.";
    echo "This error does not cause the script to terminate.";
  fi

  echo "Adding a name tag to the root volume.";
  if ! aws ec2 describe-instance-attribute --instance-id "$INS_ID" \
    --attribute blockDeviceMapping >"$VOL_FILE"; then
    echo -e "\nERROR: failed to describe instance attributes. Please check the AMI permissions.";
    echo "This error does not cause the script to terminate.";
    exit 1;
  fi

  # Assuming that the first volume ID returned is the root one
  VOL_ROOT=$(grep -wo "vol-................." "$VOL_FILE"|head -n1);
  if ! aws ec2 create-tags --resources "$VOL_ROOT" \
    --tags Key=Name,Value=""$NAME" ROOT" >/dev/null; then
    echo -e "\nERROR: failed to create tags. Please check the AMI permissions.";
    echo "This error does not cause the script to terminate.";
  fi
}

# ------------------------------------------------------------------------
# ec2 setup verification
_verify_ec2_setup(){
  # Wait for the new instance to become available online
  echo "Waiting for the new instance to initialise. This may take a while."
  while true;do
    if ! aws ec2 describe-instance-status --instance-ids "$INS_ID" >"$STATUS_FILE"; then
      echo -e "\nERROR: failed to describe instance status. Please check the AMI permissions.";
      echo "This error does not cause the script to terminate.";
      # Wait for 60 seconds, break the loop and try to assign an EIP
      sleep 60;
      break;
    fi

    if grep passed "$STATUS_FILE"; then
      echo "Instance "$NAME" has passed security checks on Amazon.";
      break;
    else
      echo "Instance is initialising. Script sleeping for 60 seconds..."
      sleep 60;
    fi
  done
}


#_create_iams(){
##  aws iam create-policy --policy-name my-policy --policy-document file://policy
##$aws iam attach-role-policy --role-name YourNewRole --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
##$aws iam create-instance-profile --instance-profile-name YourNewRole-Instance-Profile
##$aws iam add-role-to-instance-profile --role-name YourNewRole --instance-profile-name YourNewRole-Instance-Profile
#
#}

_create_activation(){
  registration_limit=10
  aws ssm create-activation \
  --default-instance-name $NAME \
  --description "Activation for EC2 instance" \
  --iam-role AmazonEC2RunCommandRoleForManagedInstances \
  --registration-limit 10 \
  --region $REGION \
  --tags Key=Name,Value="$NAME" | tee ssm-activation.json
}

_create_role(){
  roles=$(aws iam list-roles \
        --query 'Roles[*].RoleName' \
        --output text)
  # Loop through role names and get tags
  for role in $roles
  do
      aws iam list-role-tags --role-name $role
  done
}
# ------------------------------------------------------------------------
# TOOLS
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# ec2 tags verification
_copy_file_to_ec2(){
  file=$1
  scp -i $KEY_FILE $file ubuntu@$INSTANCE_DNS_NAME:/home/ubuntu/
}

_delete_tmp_files(){
  rm -f "$TMP" "$AMI_FILE" "$VPC_FILE" "$SUBNET_FILE" "$SG_FILE" \
    "$INS_FILE" "$VOL_FILE" "$STATUS_FILE" "$EIP_FILE";
}



# ------------------------------------------------------------------------
# getopts
# ------------------------------------------------------------------------

usage()
{
    ### BASIC USAGE ###
    echo -e "Usage: $(basename "$0") [--help] [command]"
    echo -e ""

    ### OPTION SECTION ###
    echo -e "Options include:"
    echo -e "   -h --help\t\t Display this help."
    echo -e "   -n --name\t\t Instance name."
    echo -e "   -a --ami\t\t  Instance AMI id."
    echo -e "   -t --type\t\t Instance type."
    echo -e "   -v --volume\t\t volume size."
    echo -e ""
}

# ------------------------------------------------------------------------
# require n args
require_n_args() {
  (( reqcnt = $2))
  if [[ $1 -eq $reqcnt ]]; then
    return 0;
  else
    echo "The incorrect number of arguments were specified. Required is $2"
    exit 1
  fi
}

# ------------------------------------------------------------------------
# read arguments
_setup (){
  while [ "$1" != "" ]; do
      PARAM=`echo -e $1 | awk -F= '{print $1}'`
      VALUE=`echo -e $1 | awk -F= '{print $2}'`
  #    echo $PARAM $VALUE
      case $PARAM in
          -h | --help)
              usage
              exit
              ;;
          -n | --name)
              NAME=$VALUE
              ;;
          -a | --ami)
              AMI_ID=$VALUE
              ;;
          -t | --type)
              INS_TYPE=$VALUE
              ;;
          -v | --volume)
              VOLUME_SIZE=$VALUE
              ;;
          *)
              echo -e "ERROR: unknown parameter $PARAM"
              exit 1
              ;;
      esac
      shift
  done
}

# ------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------

set -e

# ------------------------------------------------------------------------
# read arguments
#require_n_args $# 4
_setup "$@"

_verify_ec2_configs


# ------------------------------------------------------------------------
# setup instance
_verify_aws_installation
_verify_aws_access
_verify_aws_connection

_create_key_pair
_create_security_group
#_create_iams
_open_ports

_create_ec2
_create_ec2_tags
_verify_ec2_setup

_copy_file_to_ec2 kubeflow-setup.sh



exit 0;


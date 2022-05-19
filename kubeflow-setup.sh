#!/bin/bash
# ------------------------------------------------------------------
# Name:         kubeflow-setup.sh
#
# Author:       PlaiView
# Version:      1.0
# Created Date: 18-05-2022
#
# Purpose:      PlaiView Kubeflow installation script
#
# OS:           Ubuntu
# Usage:        ./kubeflow-setup.sh
#
# ------------------------------------------------------------------------

# START #

# ------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------

LATEST_RELEASE=1.0.0

BASE_DIR=$(pwd)fs
BASENAME=$(basename $0)

# ------------------------------------------------------------------------
# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1

# ------------------------------------------------------------------------
# Message colors
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
NORMAL=$(tput sgr0)

# ------------------------------------------------------------------------
# Characters
dashes=$(printf "%0.s#" {1..55})

# ------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
Version() {
  log "${PROGNAME} Version: ${VERSION}"
  return 0
}

# ------------------------------------------------------------------------
# log
log() {
  echo -e "$(date -u) (LOGGING) ${NORMAL}${BASENAME}: ${FUNCNAME[1]:-unknown}: $1 "
}

# ------------------------------------------------------------------------
# Raise an error
# Note: based on the scrypt name
_error_than_exit() {
  log "${RED}ERROR:$1${NORMAL}"
  exit ${EXIT_FAILURE}
}

# ------------------------------------------------------------------------
# Services setup
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Background service removal
remove_systemd(){
  servicename=$1
  systemctl stop $servicename
  systemctl disable $servicename
  rm /etc/systemd/system/$servicename
  rm /etc/systemd/system/$servicename # and symlinks that might be related
  rm /usr/lib/systemd/system/$servicename
  rm /usr/lib/systemd/system/$servicename # and symlinks that might be related
  systemctl daemon-reload
  systemctl reset-failed
}

# ------------------------------------------------------------------------
# Background service setup
_setup_installation_systemd_service(){
  echo "Setup instalation script systemd service"
  sudo mkdir -p /opt/kubeflow-installation/
  echo "
cd $HOME/KubeflowPipeline
bash kubeflow.sh --cuda=$CUDA_VERSION --driver=$NVIDIA_DRIVER_VERSION --gpu=$GPU_NUMBER --token=$GITHUB_ACCESS_TOKEN
" | sudo tee /opt/kubeflow-installation/start.sh
  echo "
[Unit]
Description=Kubeflow-ui
After=network.target

[Service]
Type=idle
ExecStart= bash /opt/kubeflow-installation/start.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target"  | sudo tee /etc/systemd/system/kubeflow-installation.service
  sudo systemctl enable kubeflow-installation
  sudo systemctl start kubeflow-installation
  echo "Kubeflow-installation systemd service is enabled"
}

# ------------------------------------------------------------------------
# setup repository
_setup_repository(){
  export GITHUB_ACCESS_TOKEN=$GITHUB_ACCESS_TOKEN
  echo "export "GITHUB_ACCESS_TOKEN"="$GITHUB_ACCESS_TOKEN"" | sudo tee -a ~/.bashrc
  echo "export "GITHUB_ACCESS_TOKEN"="$GITHUB_ACCESS_TOKEN"" | sudo tee -a /etc/environment
  source ~/.bashrc
  source /etc/environment
  cd $HOME
  git clone "https://$GITHUB_ACCESS_TOKEN@github.com/PlaiView0/KubeflowPipeline.git"
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
    echo -e "   -c --cuda\t\t Define the CUDA version."
    echo -e "   -d --driver\t\t Define the NVIDIA driver version."
    echo -e "   -h --gpu\t\t Define the GPU number."
    echo -e "   -t --token\t\t Define the GITHUB ACCESS TOKEN."
    echo -e ""
}

# ------------------------------------------------------------------------
# require n args
require_n_args() {
  (( reqcnt = $2))
  if [[ $1 -eq $reqcnt ]]; then
    return 0;
  else
    _error_than_exit "The incorrect number of arguments were specified. Required is $2"
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
          -c | --cuda)
              CUDA_VERSION=$VALUE
              ;;
          -d | --driver)
              NVIDIA_DRIVER_VERSION=$VALUE
              ;;
          -g | --gpu)
              GPU_NUMBER=$VALUE
              ;;
          -t | --token)
              GITHUB_ACCESS_TOKEN=$VALUE
              ;;
          *)
              echo -e 'ERROR: unknown parameter \"$PARAM"\n'
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
require_n_args $# 4
_setup "$@"
echo -e "CUDA_VERSION is $CUDA_VERSION";
echo -e "NVIDIA_DRIVER_VERSION is $NVIDIA_DRIVER_VERSION";
echo -e "GPU_NUMBER is $GPU_NUMBER";
echo -e "GITHUB_ACCESS_TOKEN is $GITHUB_ACCESS_TOKEN";

# ------------------------------------------------------------------------
# create a background service

_setup_repository
_setup_installation_systemd_service
# bash kubeflow.sh --cuda=11.4.0 --driver=470 --gpu=1 --token=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

#!/bin/bash

time_start=$(date +'%s')

read -p "Specify the operating system (RHEL8 or RHEL9): " c4p_build_os

if [[ $c4p_build_os != "RHEL8" && $c4p_build_os != "RHEL9" ]] ; then
  echo "The operating system \"$c4p_build_os\" does not exist"
  exit  
fi

echo ""
echo "############################"
echo "### Install C4P-HTCondor ###"
echo "############################"
echo ""

condor_version=$(condor_version | grep Version | cut -d ' ' -f 7)
echo "HTCondor version before installation: $condor_version"
echo ""

echo "Stop HTCondor"
echo ""
systemctl stop condor

if [[ $c4p_build_os = "RHEL8" ]] ; then
  rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms-rhel8/Custom/PUNCH/"
elif [[ $c4p_build_os = "RHEL9" ]] ; then
  rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms-rhel9/Custom/PUNCH/"
fi

echo "Install rpms from $rpms_dir"
echo ""

if [ ! -d "/usr/include/condor" ]; then
  mkdir /usr/include/condor
fi

dnf install -y $rpms_dir/*.rpm

echo ""
echo "Set permissions \"rws r_s r_x\" for condor_producer_mytoken"
echo ""

chmod 0755 /usr/sbin/condor_producer_mytoken
chmod g+s /usr/sbin/condor_producer_mytoken
chmod u+s /usr/sbin/condor_producer_mytoken

source ~/.bashrc

echo "Restart HTCondor"
echo ""
systemctl start condor

sleep 10

echo "Reconfigure HTCondor: $(condor_reconfig)"
echo ""
condor_version=$(condor_version | grep Version | cut -d ' ' -f 7)
echo "HTCondor version after installation: $condor_version"
echo ""

time_end=$(date +'%s')
time_elapsed=$(($time_end-$time_start))
echo "The installation of condor $condor_version took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
echo ""





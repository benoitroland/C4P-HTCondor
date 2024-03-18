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

condor_version=$(condor_version | grep Version | cut -d ' ' -f 2)
echo "HTCondor version before installation: $condor_version"
echo ""

echo "Stop HTCondor"
echo ""
systemctl stop condor

if [[ $c4p_build_os = "RHEL8" ]] ; then
  binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries-rhel8"
elif [[ $c4p_build_os = "RHEL9" ]] ; then
  binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries-rhel9"
fi

echo "Install binaries from $binaries_dir"
echo ""

if [ ! -d "/usr/include/condor" ]; then
  mkdir /usr/include/condor
fi

\cp -r $binaries_dir/bin/* /usr/bin
\cp -r $binaries_dir/sbin/* /usr/sbin

\cp -r $binaries_dir/lib/* /usr/lib64/condor
\cp -r $binaries_dir/include/* /usr/include/condor
\cp -r $binaries_dir/libexec/* /usr/libexec/condor
\cp $binaries_dir/lib/CondorJavaInfo.class /usr/share/condor
\cp $binaries_dir/lib/CondorJavaWrapper.class /usr/share/condor

echo "Set permissions \"rws r_s r_x\" for condor_producer_mytoken"
echo ""

chmod 0755 /usr/sbin/condor_producer_mytoken
chmod g+s /usr/sbin/condor_producer_mytoken
chmod u+s /usr/sbin/condor_producer_mytoken
# chmod 6755 /usr/sbin/condor_producer_mytoken

source ~/.bashrc

echo "Restart HTCondor"
echo ""
systemctl start condor

sleep 10

echo "Reconfigure HTCondor: $(condor_reconfig)"
echo ""
condor_version=$(condor_version | grep Version | cut -d ' ' -f 2)
echo "HTCondor version after installation: $condor_version"
echo ""

time_end=$(date +'%s')
time_elapsed=$(($time_end-$time_start))
echo "The installation of condor $condor_version took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
echo ""





#!/bin/bash

time_start=$(date +'%s')

read -p "Specify the source \"binaries\" or \"rpms\": " install_process

if [[ $install_process != binaries && $install_process != rpms ]] ; then
  echo "The source \"$install_process\" does not exist"
  exit
fi  

echo ""
echo "############################"
echo "### Install C4P-HTCondor ###"
echo "############################"
echo ""

echo "Installation is using the $install_process"
echo ""

condor_version=$(condor_version | grep Version | cut -d ' ' -f 2)
echo "HTCondor version before installation: $condor_version"
echo ""

echo "Stop HTCondor"
echo ""
systemctl stop condor

if [[ $install_process == binaries ]]; then    
  
  binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries"
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

elif [[ $install_process == rpms ]]; then

  rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms"
  echo "Install rpms from $rpms_dir"
  echo ""

  condor_rpm=$rpms_dir/$(ls $rpms_dir | grep "\bcondor-23.5.0-0.*.el8.x86_64.rpm" | grep -v "python")
  condor_credmon_mytoken_rpm=$rpms_dir/$(ls ../c4p-condor-rpms/ | grep "condor-credmon-mytoken-23.5.0-0")
  condor_python3_rpm=$rpms_dir/$(ls ../c4p-condor-rpms/ | grep "python3-condor-23.5.0")

  yum install -y $condor_credmon_mytoken_rpm $condor_rpm $condor_python3_rpm 
  echo ""
fi
    
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





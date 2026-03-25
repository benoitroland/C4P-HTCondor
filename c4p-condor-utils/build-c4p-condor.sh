#!/bin/bash

echo ""
echo "######################################################################################################"
echo "# explanations to build binaries and rpms: https://github.com/htcondor/htcondor/blob/main/INSTALL.md #"
echo "# containers to build binaries and rpms: htcondor/nmi_tools/nmi-build-platforms                      #"
echo "######################################################################################################"
echo ""

should_exit_process=true
should_exit_branch=true
should_exit_os=true

read -p "Specify the build process \"binaries\", \"rpms\" or \"debs\": " build_process
echo "Specify the feature branch to be used among the following ones: "

branch_output=$(git ls-remote -h https://github.com/benoitroland/C4P-HTCondor.git | awk -F 'refs/heads/' '{print $2}')
branch_array=($branch_output)

echo "$branch_output"

read -p "feature branch to be used: " c4p_condor_branch

if [ $build_process == "rpms" ] || [ $build_process == "debs" ]; then
  read -p "Specify the build id: " c4p_build_id
fi

read -p "Specify the operating system (RHEL8, RHEL9 or Debian12): " c4p_build_os

for feature in "${branch_array[@]}"
do
  if [ $c4p_condor_branch == $feature ]; then
    should_exit_branch=false
  fi
done

if [ $c4p_build_os == "RHEL8" ] || [ $c4p_build_os == "RHEL9" ] || [ $c4p_build_os == "Debian12" ]; then
  should_exit_os=false  
fi

if [ $build_process == "binaries" ] || [ $build_process == "rpms" ] || [ $build_process == "debs" ]; then
  should_exit_process=false
fi    

if [ $should_exit_process == "false" ] && [ $should_exit_branch == "false" ] && [ $should_exit_os == "false" ]; then
  echo ""  
  if [ $build_process == "binaries" ]; then
    echo "Building the binaries on $(nproc) cores for the branch $c4p_condor_branch and the operating system $c4p_build_os"
  elif [ $build_process == "rpms" ]; then
    echo "Building the rpms on $(nproc) cores for the branch $c4p_condor_branch, the operating system $c4p_build_os and the build id $c4p_build_id"
  else
    echo "Building the debs on $(nproc) cores for the branch $c4p_condor_branch, the operating system $c4p_build_os and the build id $c4p_build_id"
  fi
fi

if [ $should_exit_process == "true" ] || [ $should_exit_branch == "true" ] || [ $should_exit_os == "true" ]; then
  if [ $should_exit_process == "true" ]; then
    echo "The build process \"$build_process\" does not exist"
  fi
  if [ $should_exit_branch == "true" ]; then
    echo "The feature branch \"$c4p_condor_branch\" does not exist"
  fi
  if [ $should_exit_os == "true" ]; then
    echo "The operating system \"$c4p_build_os\" does not exist"
  fi    
  exit
fi

sleep 1

time_start=$(date +'%s')

utils_dir="$HOME/C4P-HTCondor/c4p-condor-utils"
chown condor:condor $utils_dir
chmod 777 $utils_dir

echo ""
echo "###########################"
echo "# 1/6 Create build script #"
echo "###########################"
echo ""

touch build-command.sh
chown condor:condor build-command.sh
chmod 777 build-command.sh

echo "#!/bin/bash" >> build-command.sh

if [ $c4p_build_os == "RHEL8" ] || [ $c4p_build_os == "RHEL9" ]; then
  echo ". /opt/rh/gcc-toolset-12/enable" >> build-command.sh
fi    
echo "export CC=\$(which cc)" >> build-command.sh
echo "export CXX=\$(which c++)" >> build-command.sh

echo "cd /tmp" >> build-command.sh
echo "git clone -b $c4p_condor_branch https://github.com/benoitroland/C4P-HTCondor.git" >> build-command.sh

if [ $build_process == "binaries" ]; then
  echo "cd C4P-HTCondor" >> build-command.sh
  echo "mkdir __build" >> build-command.sh
  echo "cd __build" >> build-command.sh
  echo "cmake .." >> build-command.sh
  echo "make -j $(nproc) install" >> build-command.sh
else
  echo "mkdir __build" >> build-command.sh
  echo "cd __build" >> build-command.sh
  echo "OMP_NUM_THREADS=$(nproc) ../C4P-HTCondor/c4p-condor-build/build-on-linux-c4p.sh ../C4P-HTCondor $c4p_build_id" >> build-command.sh
fi

cat build-command.sh
sleep 1

echo ""
echo "#########################"
echo "# 2/6 Create Dockerfile #"
echo "#########################"
echo ""

if [ $c4p_build_os == "RHEL8" ]; then
  echo "FROM htcondor/nmi-build:x86_64_AlmaLinux8-23050000" >> Dockerfile
elif [ $c4p_build_os == "RHEL9" ]; then
  echo "FROM htcondor/nmi-build:x86_64_AlmaLinux9-23050000" >> Dockerfile
elif [ $c4p_build_os == "Debian12" ]; then
  echo "FROM htcondor/nmi-build:x86_64_Debian12-23050200" >> Dockerfile
fi

echo "USER condor" >> Dockerfile
echo "ENV container=docker" >> Dockerfile   
echo "COPY build-command.sh /tmp" >> Dockerfile

cat Dockerfile
sleep 1

echo ""
echo "###################"
echo "# 3/6 Build image #"
echo "###################"
echo ""

docker build -t c4p-condor-container .

echo ""
echo "#####################"
echo "# 4/6 Run container #"
echo "#####################"
echo ""

docker run --user condor --rm -it -v $PWD:/tmp c4p-condor-container:latest /bin/bash -c /tmp/build-command.sh

sleep 1


if [ $build_process == "binaries" ]; then
  echo ""
  echo "#########################"
  echo "# 5/6 Retrieve binaries #"
  echo "#########################"
  echo ""

  if [ $c4p_build_os == "RHEL8" ]; then
    binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries-rhel8"
  elif [ $c4p_build_os == "RHEL9" ]; then
    binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries-rhel9"
  fi

  echo "binaries moved to $binaries_dir"

  if [ -d "$binaries_dir" ]; then
    rm -rf $binaries_dir
  fi

  mkdir $binaries_dir
  chown condor:condor $binaries_dir
  chmod 777 $binaries_dir

  cp -r C4P-HTCondor/__build/release_dir/* $binaries_dir
  
elif [ $build_process == "rpms" ]; then
  echo ""
  echo "#####################"
  echo "# 5/6 Retrieve rpms #"
  echo "#####################"
  echo ""

  if [ $c4p_build_os == "RHEL8" ]; then
    rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms-rhel8/Custom/PUNCH"
  elif [ $c4p_build_os == "RHEL9" ]; then
    rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms-rhel9/Custom/PUNCH"
  fi

  condor_version=$(condor_version | grep Version | cut -d ' ' -f 2)
  echo "condor version: $condor_version"
  echo ""
  echo "rpms moved to $rpms_dir"

  if [ -d "$rpms_dir" ]; then
    rm -rf $rpms_dir
  fi

  mkdir -p $rpms_dir
  chown condor:condor $rpms_dir
  chmod 777 $rpms_dir

  if [[ $c4p_build_os = "RHEL8" ]] ; then
    rhel="el8"
  elif [[ $c4p_build_os = "RHEL9" ]] ; then
    rhel="el9"
  fi
  
  cp __build/condor-c4p-$condor_version-$c4p_build_id.$rhel.x86_64.rpm $rpms_dir
  cp __build/condor-credmon-mytoken-$condor_version-$c4p_build_id.$rhel.x86_64.rpm $rpms_dir
  cp __build/condor-$condor_version-$c4p_build_id.$rhel.x86_64.rpm $rpms_dir
  cp __build/python3-condor-$condor_version-$c4p_build_id.$rhel.x86_64.rpm $rpms_dir

  cp __build/BUILD-ID $rpms_dir/../..

  rm -rf __build

elif [ $build_process == "debs" ]; then
  echo ""
  echo "#####################"
  echo "# 5/6 Retrieve debs #"
  echo "#####################"
  echo ""

  debs_dir="$HOME/C4P-HTCondor/c4p-condor-debian12"

  condor_version=$(condor_version | grep Version | cut -d ' ' -f 2)
  echo "condor version: $condor_version"
  echo ""
  echo "debs moved to $debs_dir"
  
  if [ -d "$debs_dir" ]; then
    rm -rf $debs_dir
  fi

  mkdir -p $debs_dir
  chown condor:condor $debs_dir
  chmod 777 $debs_dir

  cp -r __build/* $debs_dir
  
  rm -rf __build
  rm files
  rm obj
fi

echo ""
echo "###################"
echo "# 6/6 Clean setup #"
echo "###################"
echo ""

rm -rf C4P-HTCondor
rm build-command.sh
rm Dockerfile

docker image rm c4p-condor-container

#if [ $c4p_build_os == "RHEL8" ]; then
#  docker image rm docker.io/htcondor/nmi-build:x86_64_AlmaLinux8-23050000
#elif [ $c4p_build_os == "RHEL9" ]; then
#  docker image rm docker.io/htcondor/nmi-build:x86_64_AlmaLinux9-23050000
#elif [ $build_process == "debs" ]; then
#  docker image rm docker.io/htcondor/nmi-build:x86_64_Debian12-23050200
#fi

chown root:root $utils_dir
chmod 755 $utils_dir

if [ -d "$binaries_dir" ]; then
  chown root:root $binaries_dir
  chmod 755 $binaries_dir
elif [ -d "$rpms_dir" ]; then
  chown root:root $rpms_dir
  chmod 755 $rpms_dir
elif [ -d "$debs_dir" ]; then
  chown root:root $debs_dir
  chmod 755 $debs_dir
fi

time_end=$(date +'%s')
time_elapsed=$(($time_end-$time_start))

echo ""
if [ $build_process == "binaries" ]; then
  echo "Builiding the binaries took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
elif [ $build_process == "rpms" ]; then
  echo "Builiding the rpms took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"  
elif [ $build_process == "debs" ]; then
  echo "Builiding the debian packages took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
fi
echo ""

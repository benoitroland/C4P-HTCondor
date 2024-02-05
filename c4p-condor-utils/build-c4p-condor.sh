#!/bin/bash

echo ""
echo "######################################################################################################"
echo "# explanations to build binaries and rpms: https://github.com/htcondor/htcondor/blob/main/INSTALL.md #"
echo "# containers to build binaries and rpms: htcondor/nmi_tools/nmi-build-platforms                      #"
echo "######################################################################################################"
echo ""

should_exit_process=true
should_exit_branch=true

read -p "Specify the build process \"binaries\" or \"rpms\": " build_process
echo "Specify the feature branch to be used among the following ones: "

branch_output=$(git ls-remote -h https://github.com/benoitroland/C4P-HTCondor.git | awk -F 'refs/heads/' '{print $2}')
branch_array=($branch_output)

echo "$branch_output"
read -p "feature branch to be used: " c4p_condor_branch

for feature in "${branch_array[@]}"
do
  if [[ $c4p_condor_branch = $feature ]] ; then
    should_exit_branch=false
  fi
done

if [[ $build_process = binaries || $build_process = rpms ]] ; then
  should_exit_process=false
  if [[ $should_exit_branch = false ]] ; then
    echo ""  
    if [[ $build_process = binaries ]] ; then
      echo "Building the binaries on $(nproc) cores for the branch $c4p_condor_branch"
    else
      echo "Building the rpms on $(nproc) cores for the branch $c4p_condor_branch"
    fi
  fi
fi

if [[ $should_exit_process = true || $should_exit_branch = true ]] ; then
  if [[ $should_exit_process = true ]] ; then
    echo "The build process \"$build_process\" does not exist"
  fi
  if [[ $should_exit_branch = true ]] ; then
    echo "The feature branch \"$c4p_condor_branch\" does not exist"
  fi
  exit
fi  

sleep 1

time_start=$(date +'%s')

utils_dir="$HOME/C4P-HTCondor/c4p-condor-utils"
chown condor:condor $utils_dir
chmod 777 $utils_dir

echo ""
echo "######################"
echo "# 1/7 Install docker #"
echo "######################"
echo ""

yum install -y docker

echo ""
echo "###########################"
echo "# 2/7 Create build script #"
echo "###########################"
echo ""

touch build-command.sh
chown condor:condor build-command.sh
chmod 777 build-command.sh

echo "#!/bin/bash" >> build-command.sh

echo ". /opt/rh/gcc-toolset-12/enable" >> build-command.sh
echo "export CC=\$(which cc)" >> build-command.sh
echo "export CXX=\$(which c++)" >> build-command.sh

echo "cd /tmp" >> build-command.sh
echo "git clone -b $c4p_condor_branch https://github.com/benoitroland/C4P-HTCondor.git" >> build-command.sh

if [[ $build_process = binaries ]] ; then
  echo "cd C4P-HTCondor" >> build-command.sh
  echo "mkdir __build" >> build-command.sh
  echo "cd __build" >> build-command.sh
  echo "cmake .." >> build-command.sh
  echo "make -j $(nproc) install" >> build-command.sh

elif [[ $build_process = rpms ]] ; then
  echo "mkdir __build" >> build-command.sh
  echo "cd __build" >> build-command.sh
  echo "OMP_NUM_THREADS=$(nproc) ../C4P-HTCondor/build-on-linux.sh ../C4P-HTCondor" >> build-command.sh
fi

echo "echo \"\""  >> build-command.sh
echo "echo \"condor version: \$(condor_version | grep Version | cut -d ' ' -f 2)\"" >> build-command.sh

cat build-command.sh
sleep 1

echo ""
echo "#########################"
echo "# 3/7 Create Dockerfile #"
echo "#########################"
echo ""

echo "FROM htcondor/nmi-build:x86_64_AlmaLinux8-23050000" >> Dockerfile
echo "USER condor" >> Dockerfile
echo "ENV container docker" >> Dockerfile   
echo "COPY build-command.sh /tmp" >> Dockerfile

cat Dockerfile
sleep 1

echo ""
echo "###################"
echo "# 4/7 Build image #"
echo "###################"
echo ""

docker build -t c4p-condor-container .

echo ""
echo "#####################"
echo "# 5/7 Run container #"
echo "#####################"
echo ""

docker run --user condor --rm -it -v $PWD:/tmp localhost/c4p-condor-container:latest /bin/bash -c /tmp/build-command.sh

sleep 1

if [[ $build_process = binaries ]] ; then
  echo ""
  echo "#########################"
  echo "# 6/7 Retrieve binaries #"
  echo "#########################"
  echo ""

  binaries_dir="$HOME/C4P-HTCondor/c4p-condor-binaries"
  echo "binaries moved to $binaries_dir"

  if [ -d "$binaries_dir" ]; then
    rm -rf $binaries_dir
  fi

  mkdir $binaries_dir
  chown condor:condor $binaries_dir
  chmod 777 $binaries_dir

  cp -r C4P-HTCondor/__build/release_dir/* $binaries_dir
  
elif [[ $build_process = rpms ]] ; then
  echo ""
  echo "#####################"
  echo "# 6/7 Retrieve rpms #"
  echo "#####################"
  echo ""

  rpms_dir="$HOME/C4P-HTCondor/c4p-condor-rpms"
  echo "rpms moved to $rpms_dir" 

  if [ -d "$rpms_dir" ]; then
    rm -rf $rpms_dir
  fi

  mkdir $rpms_dir
  chown condor:condor $rpms_dir
  chmod 777 $rpms_dir

  cp -r __build/* $rpms_dir
  rm -rf __build
fi

echo ""
echo "####################"
echo "# 7/7 Clean setup  #"
echo "####################"
echo ""

rm -rf C4P-HTCondor

rm build-command.sh
rm Dockerfile

docker image rm localhost/c4p-condor-container
docker image rm docker.io/htcondor/nmi-build:x86_64_AlmaLinux8-23050000

time_end=$(date +'%s')
time_elapsed=$(($time_end-$time_start))

echo ""
if [[ $build_process = binaries ]] ; then
  echo "Builiding the binaries took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
elif [[ $build_process = rpms ]] ; then
  echo "Builiding the rpms took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"  
fi
echo ""
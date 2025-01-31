#!/bin/bash

time_start=$(date +'%s')

utils_dir="$HOME/C4P-HTCondor/c4p-condor-utils"
chmod 777 $utils_dir

echo ""
echo "######################"
echo "# 1/7 Install docker #"
echo "######################"
echo ""

yum install -y docker

echo ""
echo "####################################"
echo "# 2/7 Specify package to be tested #"
echo "####################################"
echo ""

debian_dirs=($(ls $HOME/C4P-HTCondor | grep c4p-condor-debian))

echo "The following debian packages have been found: "
echo ""

for debian_dir in "${debian_dirs[@]}"
do
   echo "$debian_dir"
done

echo ""
read -p "Please specify the package to be tested: " debian_package
echo ""


should_exit=true

for debian_dir in "${debian_dirs[@]}"
do
  if [ $debian_dir == $debian_package ]; then
    should_exit=false
  fi
done
  		  
if [ $should_exit == "true" ]; then
  echo "The package \"$debian_package\" does not exist"
  exit
fi
		  
cp -r $HOME/C4P-HTCondor/$debian_package $utils_dir

echo ""
echo "###########################"
echo "# 3/7 Create check script #"
echo "###########################"
echo ""

touch check-command.sh
chmod 755 check-command.sh
echo "#!/bin/bash" >> check-command.sh

packages_to_check=($(ls $utils_dir/$debian_package))

for package in "${packages_to_check[@]}"
do
  if [[ $package == *".deb" && $package == *"credmon"* && $package != *"dbg"* ]]; then
    echo "echo \"\"" >> check-command.sh
    echo "echo \"Checking package $package\"" >> check-command.sh
    echo "echo \"\"" >> check-command.sh
    echo "lintian -I -i -E -o /tmp/$debian_package/$package >> /tmp/lintian_$package.txt" >> check-command.sh
    fi
done

cat check-command.sh
sleep 1

echo ""
echo "#########################"
echo "# 4/7 Create Dockerfile #"
echo "#########################"
echo ""

echo "FROM debian:12.1" >> Dockerfile
echo "RUN  apt-get update" >> Dockerfile
echo "RUN apt-get install -y lintian" >> Dockerfile

cat Dockerfile
sleep 1

echo ""
echo "###################"
echo "# 5/7 Build image #"
echo "###################"
echo ""

docker build -t c4p-debian-check .

echo ""
echo "#####################"
echo "# 6/7 Run container #"
echo "#####################"
echo ""

docker run --rm -it -v $PWD:/tmp localhost/c4p-debian-check:latest /bin/bash -c /tmp/check-command.sh
sleep 1

echo ""
echo "###################"
echo "# 7/7 Clean setup #"
echo "###################"
echo ""

rm -rf $utils_dir/$debian_package
rm -rf $utils_dir/mldbm*

rm check-command.sh
rm Dockerfile

docker image rm localhost/c4p-debian-check:latest
docker image rm docker.io/library/debian:12.1

chmod 755 $utils_dir

time_end=$(date +'%s')
time_elapsed=$(($time_end-$time_start))

echo ""
echo "Checking the debian packages took $(( $time_elapsed / 3600 ))h $(( ($time_elapsed / 60) % 60 ))m $(( $time_elapsed % 60 ))s"
echo ""






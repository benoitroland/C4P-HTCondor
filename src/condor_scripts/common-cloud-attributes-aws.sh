#!/bin/bash
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -v -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`

while read common specific; do
    value=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/${specific}`
    echo ${common}=\"${value}\"
done << EOF
    Image ami-id
    Type instance-type
    Zone placement/availability-zone
    Region placement/region
    InstanceID instance-id
EOF

echo 'Provider="AWS"'
echo 'Platform="EC2"'

interruptable="False"
ilc=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-life-cycle`
if [[ $ilc == "spot" ]]; then
    interruptable="True"
fi
echo "Interruptable=${interruptable}"

echo "- update:true"

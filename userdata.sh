#!/bin/bash
set -e

yum update -y
yum install -y jq httpd aws-cli

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

NAME=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
       --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" --output text)
[ -z "$NAME" ] && NAME="server1"
hostnamectl set-hostname "$NAME"

systemctl start httpd
systemctl enable httpd
echo "Hi I am from $NAME" > /var/www/html/index.html

HZ=$(aws route53 list-hosted-zones-by-name --dns-name "dvstech.com." --region "$REGION" \
      --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

cat <<EOF > /tmp/r53.json
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${NAME}.dvstech.com.",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          { "Value": "$PRIVATE_IP" }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --region "$REGION" --hosted-zone-id "$HZ" --change-batch file:///tmp/r53.json
rm /tmp/r53.json


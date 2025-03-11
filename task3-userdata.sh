#!/bin/bash
set -e 

# Configuration
DOMAIN="dvstech.com"
TTL=60

# Install dependencies
yum update -y
yum install -y jq

# Retrieve an authentication token for IMDSv2 (instance metadata service)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
       -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Get Instance ID
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s \
             http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

# Get Private IP
PRIVATE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
              --query "Reservations[0].Instances[0].PrivateIpAddress" \
              --output text)
echo "Private IP: $PRIVATE_IP"

# Get Instance Name Tag
INSTANCE_NAME=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" \
                --output text)
if [ -z "$INSTANCE_NAME" ]; then
  INSTANCE_NAME="server1"  # Default to "server1" if Name tag is missing
fi
echo "Instance Name: $INSTANCE_NAME"

# Get Hosted Zone ID dynamically
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
                   --query "HostedZones[0].Id" --output text | cut -d'/' -f3)
if [ -z "$HOSTED_ZONE_ID" ]; then
  echo "Error: Hosted zone for $DOMAIN not found."
  exit 1
fi
echo "Hosted Zone ID: $HOSTED_ZONE_ID"

# Construct the DNS Record
DNS_RECORD="${INSTANCE_NAME}.${DOMAIN}"
echo "Updating DNS: $DNS_RECORD -> $PRIVATE_IP"

# Prepare JSON for Route 53
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Auto-registering $INSTANCE_NAME",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DNS_RECORD",
        "Type": "A",
        "TTL": $TTL,
        "ResourceRecords": [
          {
            "Value": "$PRIVATE_IP"
          }
        ]
      }
    }
  ]
}
EOF
)

# Save JSON to a temporary file
TMPFILE=$(mktemp)
echo "$CHANGE_BATCH" > "$TMPFILE"

# Update Route 53 DNS record
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file://"$TMPFILE"

# Cleanup
rm "$TMPFILE"

echo "DNS record: $DNS_RECORD -> $PRIVATE_IP"


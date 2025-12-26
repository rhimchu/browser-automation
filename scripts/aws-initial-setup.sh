#!/bin/bash
# aws-initial-setup.sh
# Run this ONCE to set up your AWS environment
# Save to: scripts/aws-initial-setup.sh

set -e

REGION="ap-southeast-1"
KEY_NAME="browser-automation-key"

echo "=== AWS Initial Setup for Browser Automation ==="
echo "Region: $REGION"
echo ""

# 1. Create key pair
echo "[1/3] Creating key pair..."
aws ec2 create-key-pair \
    --region $REGION \
    --key-name $KEY_NAME \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/${KEY_NAME}.pem

chmod 400 ~/.ssh/${KEY_NAME}.pem
echo "✓ Key saved to ~/.ssh/${KEY_NAME}.pem"

# 2. Create security group
echo "[2/3] Creating security group..."
VPC_ID=$(aws ec2 describe-vpcs \
    --region $REGION \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

SG_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name browser-automation-sg \
    --description "Security group for browser automation" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

echo "✓ Security Group ID: $SG_ID"

# 3. Allow SSH from your current IP
echo "[3/3] Configuring SSH access..."
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr ${MY_IP}/32

echo "✓ SSH allowed from $MY_IP"

# Save config for later use
cat > ../config.env << EOF
# Auto-generated AWS configuration
# Source this file: source config.env

export AWS_REGION="$REGION"
export KEY_NAME="$KEY_NAME"
export KEY_FILE="~/.ssh/${KEY_NAME}.pem"
export SECURITY_GROUP="$SG_ID"
export AMI_ID="ami-01811d4912b4ccb26"  # Ubuntu 22.04 in ap-southeast-1
export INSTANCE_TYPE="t2.micro"
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Configuration saved to config.env"
echo ""
echo "Key Name:       $KEY_NAME"
echo "Key File:       ~/.ssh/${KEY_NAME}.pem"
echo "Security Group: $SG_ID"
echo "Region:         $REGION"
echo ""
echo "Next step: Run ./scripts/orchestrate.sh to start automation"

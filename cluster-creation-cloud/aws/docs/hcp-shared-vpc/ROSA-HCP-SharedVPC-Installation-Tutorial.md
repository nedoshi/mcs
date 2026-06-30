# ROSA HCP Installation with Shared VPC - Complete Tutorial

This tutorial provides step-by-step instructions for installing a Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP) using a Shared VPC architecture.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Account Setup](#account-setup)
4. [Phase 1: Shared VPC Account Setup](#phase-1-shared-vpc-account-setup)
5. [Phase 2: Cluster Account Setup](#phase-2-cluster-account-setup)
6. [Phase 3: Cross-Account Configuration](#phase-3-cross-account-configuration)
7. [Phase 4: Cluster Installation](#phase-4-cluster-installation)
8. [Phase 5: Post-Installation Verification](#phase-5-post-installation-verification)
9. [Troubleshooting](#troubleshooting)
10. [Cleanup](#cleanup)

---

## Architecture Overview

In a Shared VPC architecture, you have two AWS accounts:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SHARED VPC ACCOUNT                                 │
│                         (Network Owner Account)                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  VPC                                                                 │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │  Subnet AZ-a │  │  Subnet AZ-b │  │  Subnet AZ-c │               │    │
│  │  │  (Private)   │  │  (Private)   │  │  (Private)   │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────┐  ┌─────────────────────┐                           │
│  │  Route53 Role       │  │  VPC Endpoint Role  │                           │
│  └─────────────────────┘  └─────────────────────┘                           │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Private Hosted Zones (Route53)                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    (Shared via AWS RAM)
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLUSTER ACCOUNT                                    │
│                        (ROSA Workload Account)                               │
│                                                                              │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐  │
│  │  Account Roles      │  │  Operator Roles     │  │  OIDC Provider      │  │
│  │  - Installer        │  │  - 8 roles for      │  │  - S3 Bucket        │  │
│  │  - Worker           │  │    cluster ops      │  │  - IAM Provider     │  │
│  │  - Support          │  │                     │  │                     │  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  ROSA HCP Cluster (Worker Nodes in Shared VPC Subnets)              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Account | Purpose | Resources |
|---------|---------|-----------|
| **Shared VPC Account** | Network infrastructure owner | VPC, Subnets, Route53 Hosted Zones, Shared VPC IAM Roles |
| **Cluster Account** | ROSA cluster workloads | Account Roles, Operator Roles, OIDC Provider, Worker Nodes |

---

## Prerequisites

### Required Tools

```bash
# Install ROSA CLI
# Download from: https://console.redhat.com/openshift/downloads
rosa version

# Install AWS CLI
aws --version

# Install OpenShift CLI (optional, for cluster management)
oc version
```

### Required Access

- AWS credentials configured for both accounts
- Red Hat account with ROSA enabled
- Sufficient AWS quotas (EC2, VPC, EBS, etc.)

### Verify ROSA Login

```bash
# Login to Red Hat
rosa login --token=<your-token>

# Verify login
rosa whoami
```

---

## Account Setup

### Set Environment Variables

Create a configuration file or export these variables:

```bash
# Cluster Configuration
export CLUSTER_NAME="my-rosa-cluster"
export REGION="us-east-1"
export VERSION="4.18.32"  # Use: rosa list versions --channel-group stable --hosted-cp

# Account IDs
export CLUSTER_ACCOUNT_ID="111111111111"      # Replace with your cluster account ID
export SHARED_VPC_ACCOUNT_ID="222222222222"   # Replace with your shared VPC account ID

# Network Configuration
export VPC_CIDR="10.0.0.0/16"
export MACHINE_CIDR="10.0.0.0/16"

# Will be set during setup
export VPC_ID=""
export SUBNET_IDS=""
export OIDC_ID=""
export PRIVATE_HOSTED_ZONE_ID=""
export HCP_INTERNAL_HOSTED_ZONE_ID=""
```

---

## Phase 1: Shared VPC Account Setup

> **Switch to Shared VPC Account credentials**

```bash
export AWS_PROFILE=shared-vpc-account  # Or configure credentials appropriately
```

### Step 1.1: Create VPC

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${CLUSTER_NAME}-vpc}]" \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames '{"Value": true}'

# Enable DNS support
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support '{"Value": true}'
```

### Step 1.2: Create Subnets (Multi-AZ)

```bash
# Get available AZs
AZS=($(aws ec2 describe-availability-zones \
  --query 'AvailabilityZones[?State==`available`].ZoneName' \
  --output text | head -3))

echo "Using AZs: ${AZS[@]}"

# Create Subnet in AZ-a
SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block "10.0.0.0/24" \
  --availability-zone ${AZS[0]} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-subnet-az-a},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Create Subnet in AZ-b
SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block "10.0.1.0/24" \
  --availability-zone ${AZS[1]} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-subnet-az-b},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Create Subnet in AZ-c
SUBNET_C=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block "10.0.2.0/24" \
  --availability-zone ${AZS[2]} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-subnet-az-c},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' \
  --output text)

export SUBNET_IDS="${SUBNET_A},${SUBNET_B},${SUBNET_C}"
echo "Subnet IDs: $SUBNET_IDS"
```

### Step 1.3: Create Internet Gateway and NAT Gateway (for outbound connectivity)

```bash
# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${CLUSTER_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID

# Create Elastic IP for NAT Gateway
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${CLUSTER_NAME}-nat-eip}]" \
  --query 'AllocationId' \
  --output text)

# Create public subnet for NAT Gateway
PUBLIC_SUBNET=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block "10.0.255.0/24" \
  --availability-zone ${AZS[0]} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-public-subnet}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Create NAT Gateway
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET \
  --allocation-id $EIP_ALLOC \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${CLUSTER_NAME}-nat-gw}]" \
  --query 'NatGateway.NatGatewayId' \
  --output text)

echo "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
echo "NAT Gateway ready: $NAT_GW_ID"
```

### Step 1.4: Configure Route Tables

```bash
# Create public route table
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${CLUSTER_NAME}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET \
  --route-table-id $PUBLIC_RT

# Create private route table
PRIVATE_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GW_ID

# Associate private subnets with private route table
aws ec2 associate-route-table --subnet-id $SUBNET_A --route-table-id $PRIVATE_RT
aws ec2 associate-route-table --subnet-id $SUBNET_B --route-table-id $PRIVATE_RT
aws ec2 associate-route-table --subnet-id $SUBNET_C --route-table-id $PRIVATE_RT
```

### Step 1.5: Create Private Hosted Zones (Route53)

```bash
# Get a unique caller reference
CALLER_REF=$(date +%s)

# Create HCP Internal Communication Hosted Zone
HCP_INTERNAL_HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name "${CLUSTER_NAME}.hypershift.local" \
  --caller-reference "${CALLER_REF}-hcp" \
  --vpc VPCRegion=$REGION,VPCId=$VPC_ID \
  --hosted-zone-config Comment="HCP Internal Communication Zone",PrivateZone=true \
  --query 'HostedZone.Id' \
  --output text | sed 's|/hostedzone/||')

echo "HCP Internal Hosted Zone ID: $HCP_INTERNAL_HOSTED_ZONE_ID"

# Create DNS domain for ROSA
rosa create dns-domain

# Get the DNS domain
DNS_DOMAIN=$(rosa list dns-domain --output json | jq -r '.[0].id')
echo "DNS Domain: $DNS_DOMAIN"

# Create Ingress Private Hosted Zone
PRIVATE_HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name "rosa.${CLUSTER_NAME}.${DNS_DOMAIN}" \
  --caller-reference "${CALLER_REF}-ingress" \
  --vpc VPCRegion=$REGION,VPCId=$VPC_ID \
  --hosted-zone-config Comment="ROSA Ingress Private Hosted Zone",PrivateZone=true \
  --query 'HostedZone.Id' \
  --output text | sed 's|/hostedzone/||')

echo "Ingress Private Hosted Zone ID: $PRIVATE_HOSTED_ZONE_ID"
```

### Step 1.6: Share Subnets via AWS RAM

```bash
# Create Resource Share
RESOURCE_SHARE_ARN=$(aws ram create-resource-share \
  --name "${CLUSTER_NAME}-subnet-share" \
  --resource-arns \
    "arn:aws:ec2:${REGION}:${SHARED_VPC_ACCOUNT_ID}:subnet/${SUBNET_A}" \
    "arn:aws:ec2:${REGION}:${SHARED_VPC_ACCOUNT_ID}:subnet/${SUBNET_B}" \
    "arn:aws:ec2:${REGION}:${SHARED_VPC_ACCOUNT_ID}:subnet/${SUBNET_C}" \
  --principals $CLUSTER_ACCOUNT_ID \
  --query 'resourceShare.resourceShareArn' \
  --output text)

echo "Resource Share ARN: $RESOURCE_SHARE_ARN"
```

### Step 1.7: Create Shared VPC IAM Roles (Initial - will update trust policy later)

#### Route53 Role

```bash
# Create Route53 Role Trust Policy (initial - with root, will scope down later)
cat > /tmp/route53-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${CLUSTER_ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create Route53 Role Permission Policy
cat > /tmp/route53-permission-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:ListResourceRecordSets",
                "route53:GetHostedZone",
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the Route53 Role
aws iam create-role \
  --role-name "${CLUSTER_NAME}-Route53-Role" \
  --assume-role-policy-document file:///tmp/route53-trust-policy.json \
  --description "Role for ROSA cluster principals to manage Route53"

aws iam put-role-policy \
  --role-name "${CLUSTER_NAME}-Route53-Role" \
  --policy-name "Route53Policy" \
  --policy-document file:///tmp/route53-permission-policy.json

ROUTE53_ROLE_ARN="arn:aws:iam::${SHARED_VPC_ACCOUNT_ID}:role/${CLUSTER_NAME}-Route53-Role"
echo "Route53 Role ARN: $ROUTE53_ROLE_ARN"
```

#### VPC Endpoint Role

```bash
# Create VPC Endpoint Role Trust Policy (initial - with root, will scope down later)
cat > /tmp/vpc-endpoint-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${CLUSTER_ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create VPC Endpoint Role Permission Policy
cat > /tmp/vpc-endpoint-permission-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVpcEndpoint",
                "ec2:DeleteVpcEndpoints",
                "ec2:DescribeVpcEndpoints",
                "ec2:ModifyVpcEndpoint",
                "ec2:CreateTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the VPC Endpoint Role
aws iam create-role \
  --role-name "${CLUSTER_NAME}-VPC-Endpoint-Role" \
  --assume-role-policy-document file:///tmp/vpc-endpoint-trust-policy.json \
  --description "Role for ROSA cluster principals to manage VPC Endpoints"

aws iam put-role-policy \
  --role-name "${CLUSTER_NAME}-VPC-Endpoint-Role" \
  --policy-name "VPCEndpointPolicy" \
  --policy-document file:///tmp/vpc-endpoint-permission-policy.json

VPC_ENDPOINT_ROLE_ARN="arn:aws:iam::${SHARED_VPC_ACCOUNT_ID}:role/${CLUSTER_NAME}-VPC-Endpoint-Role"
echo "VPC Endpoint Role ARN: $VPC_ENDPOINT_ROLE_ARN"
```

---

## Phase 2: Cluster Account Setup

> **Switch to Cluster Account credentials**

```bash
export AWS_PROFILE=cluster-account  # Or configure credentials appropriately
```

### Step 2.1: Verify ROSA Prerequisites

```bash
# Verify AWS permissions
rosa verify permissions

# Verify AWS quota
rosa verify quota --region $REGION
```

### Step 2.2: Create Account Roles

```bash
# Create HCP Account Roles
rosa create account-roles \
  --prefix $CLUSTER_NAME \
  --hosted-cp \
  --version $VERSION \
  --mode auto \
  --yes

# Verify account roles
rosa list account-roles | grep $CLUSTER_NAME
```

**Expected Output:**
```
ROLE NAME                                    ROLE TYPE   OPENSHIFT VERSION
my-rosa-cluster-HCP-ROSA-Installer-Role      Installer   4.18
my-rosa-cluster-HCP-ROSA-Worker-Role         Worker      4.18
my-rosa-cluster-HCP-ROSA-Support-Role        Support     4.18
```

### Step 2.3: Create OIDC Configuration

```bash
# Create OIDC Config (unmanaged for more control)
rosa create oidc-config \
  --prefix $CLUSTER_NAME \
  --managed=false \
  --mode auto \
  --yes

# Get OIDC Config ID
OIDC_ID=$(rosa list oidc-config --output json | jq -r ".[] | select(.id | contains(\"$CLUSTER_NAME\") or .issuer_url | contains(\"$CLUSTER_NAME\")) | .id" | head -1)

# If the above doesn't work, list and manually select
rosa list oidc-config
# Set OIDC_ID manually if needed:
# export OIDC_ID="your-oidc-config-id"

echo "OIDC Config ID: $OIDC_ID"
```

### Step 2.4: Create OIDC Provider (CRITICAL STEP)

> ⚠️ **This step is often missed and causes installation failures!**

```bash
# Create the IAM OIDC Identity Provider
rosa create oidc-provider \
  --oidc-config-id $OIDC_ID \
  --mode auto \
  --yes

# Verify OIDC Provider was created
aws iam list-open-id-connect-providers

# Get OIDC Provider details
OIDC_ENDPOINT=$(rosa list oidc-config --output json | jq -r ".[] | select(.id==\"$OIDC_ID\") | .issuer_url" | sed 's|https://||')
echo "OIDC Endpoint: $OIDC_ENDPOINT"

aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::${CLUSTER_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT}"
```

### Step 2.5: Create Operator Roles

```bash
# Create Operator Roles
rosa create operator-roles \
  --prefix $CLUSTER_NAME \
  --oidc-config-id $OIDC_ID \
  --hosted-cp \
  --mode auto \
  --yes

# Verify operator roles
rosa list operator-roles --prefix $CLUSTER_NAME
```

**Expected Output (8 roles):**
```
OPERATOR NAME                OPERATOR NAMESPACE                           ROLE NAME
capa-controller-manager      kube-system                                  my-rosa-cluster-kube-system-capa-controller-manager
control-plane-operator       kube-system                                  my-rosa-cluster-kube-system-control-plane-operator
kms-provider                 kube-system                                  my-rosa-cluster-kube-system-kms-provider
kube-controller-manager      kube-system                                  my-rosa-cluster-kube-system-kube-controller-manager
cloud-credentials            openshift-cloud-network-config-controller    my-rosa-cluster-openshift-cloud-network-config-controller-cloud-cr
ebs-cloud-credentials        openshift-cluster-csi-drivers                my-rosa-cluster-openshift-cluster-csi-drivers-ebs-cloud-credential
installer-cloud-credentials  openshift-image-registry                     my-rosa-cluster-openshift-image-registry-installer-cloud-credentia
cloud-credentials            openshift-ingress-operator                   my-rosa-cluster-openshift-ingress-operator-cloud-credentials
```

### Step 2.6: Create Security Group for Worker Nodes (Optional)

```bash
# Get the VPC ID (shared from other account)
aws ec2 describe-subnets --subnet-ids ${SUBNET_A} --query 'Subnets[0].VpcId' --output text

# Create security group in cluster account
WORKER_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-worker-sg" \
  --description "Security Group for ROSA HCP Worker Nodes" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${CLUSTER_NAME}-worker-sg}]" \
  --query 'GroupId' \
  --output text)

# Add inbound rule - allow all traffic from self
aws ec2 authorize-security-group-ingress \
  --group-id $WORKER_SG \
  --protocol -1 \
  --source-group $WORKER_SG

# Add outbound rule - allow all outbound
aws ec2 authorize-security-group-egress \
  --group-id $WORKER_SG \
  --protocol -1 \
  --cidr 0.0.0.0/0

echo "Worker Security Group: $WORKER_SG"
```

---

## Phase 3: Cross-Account Configuration

### Step 3.1: Get Operator Role ARNs

```bash
# Get the ARNs needed for trust policy updates
INSTALLER_ROLE_ARN="arn:aws:iam::${CLUSTER_ACCOUNT_ID}:role/${CLUSTER_NAME}-HCP-ROSA-Installer-Role"
CONTROL_PLANE_OPERATOR_ROLE_ARN="arn:aws:iam::${CLUSTER_ACCOUNT_ID}:role/${CLUSTER_NAME}-kube-system-control-plane-operator"
INGRESS_OPERATOR_ROLE_ARN="arn:aws:iam::${CLUSTER_ACCOUNT_ID}:role/${CLUSTER_NAME}-openshift-ingress-operator-cloud-credentials"

echo "Installer Role: $INSTALLER_ROLE_ARN"
echo "Control Plane Operator Role: $CONTROL_PLANE_OPERATOR_ROLE_ARN"
echo "Ingress Operator Role: $INGRESS_OPERATOR_ROLE_ARN"
```

### Step 3.2: Update Shared VPC Role Trust Policies

> **Switch to Shared VPC Account credentials**

```bash
export AWS_PROFILE=shared-vpc-account
```

#### Update Route53 Role Trust Policy

```bash
cat > /tmp/route53-trust-policy-updated.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "${INSTALLER_ROLE_ARN}",
                    "${CONTROL_PLANE_OPERATOR_ROLE_ARN}",
                    "${INGRESS_OPERATOR_ROLE_ARN}"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam update-assume-role-policy \
  --role-name "${CLUSTER_NAME}-Route53-Role" \
  --policy-document file:///tmp/route53-trust-policy-updated.json

echo "Route53 Role trust policy updated"
```

#### Update VPC Endpoint Role Trust Policy

```bash
cat > /tmp/vpc-endpoint-trust-policy-updated.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "${INSTALLER_ROLE_ARN}",
                    "${CONTROL_PLANE_OPERATOR_ROLE_ARN}"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam update-assume-role-policy \
  --role-name "${CLUSTER_NAME}-VPC-Endpoint-Role" \
  --policy-document file:///tmp/vpc-endpoint-trust-policy-updated.json

echo "VPC Endpoint Role trust policy updated"
```

### Step 3.3: Accept RAM Share (Cluster Account)

> **Switch to Cluster Account credentials**

```bash
export AWS_PROFILE=cluster-account

# List pending invitations
aws ram get-resource-share-invitations --query 'resourceShareInvitations[?status==`PENDING`]'

# Accept the invitation (get the ARN from above)
INVITATION_ARN=$(aws ram get-resource-share-invitations \
  --query 'resourceShareInvitations[?status==`PENDING`].resourceShareInvitationArn' \
  --output text)

aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn $INVITATION_ARN

# Verify subnets are accessible
aws ec2 describe-subnets --subnet-ids $SUBNET_A $SUBNET_B $SUBNET_C
```

---

## Phase 4: Cluster Installation

> **Ensure you are using Cluster Account credentials**

```bash
export AWS_PROFILE=cluster-account
```

### Step 4.1: Final Pre-flight Verification

```bash
echo "=== Pre-flight Verification ==="

echo -e "\n1. ROSA Permissions:"
rosa verify permissions

echo -e "\n2. ROSA Quota:"
rosa verify quota --region $REGION

echo -e "\n3. Account Roles:"
rosa list account-roles | grep $CLUSTER_NAME

echo -e "\n4. Operator Roles:"
rosa list operator-roles --prefix $CLUSTER_NAME

echo -e "\n5. OIDC Config:"
rosa list oidc-config

echo -e "\n6. OIDC Provider (CRITICAL):"
aws iam list-open-id-connect-providers

echo -e "\n7. DNS Domain:"
rosa list dns-domain

echo -e "\n8. Subnets:"
aws ec2 describe-subnets \
  --subnet-ids $SUBNET_A $SUBNET_B $SUBNET_C \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

### Step 4.2: Create the Cluster

```bash
# Set all required variables
export DNS_DOMAIN=$(rosa list dns-domain --output json | jq -r '.[0].id')

rosa create cluster \
  --cluster-name=$CLUSTER_NAME \
  --private \
  --default-ingress-private \
  --sts \
  --mode=auto \
  --hosted-cp \
  --machine-cidr=$MACHINE_CIDR \
  --oidc-config-id=$OIDC_ID \
  --region=$REGION \
  --version=$VERSION \
  --operator-roles-prefix=$CLUSTER_NAME \
  --hcp-internal-communication-hosted-zone-id=$HCP_INTERNAL_HOSTED_ZONE_ID \
  --vpc-endpoint-role-arn=$VPC_ENDPOINT_ROLE_ARN \
  --route53-role-arn=$ROUTE53_ROLE_ARN \
  --ingress-private-hosted-zone-id=$PRIVATE_HOSTED_ZONE_ID \
  --base-domain=$DNS_DOMAIN \
  --multi-az \
  --subnet-ids=$SUBNET_IDS \
  --additional-allowed-principals=$VPC_ENDPOINT_ROLE_ARN,$ROUTE53_ROLE_ARN \
  --yes
```

### Step 4.3: Monitor Installation Progress

```bash
# Watch cluster status
rosa describe cluster --cluster=$CLUSTER_NAME

# Watch installation logs
rosa logs install --cluster=$CLUSTER_NAME --watch

# Check cluster status periodically
watch -n 30 "rosa describe cluster --cluster=$CLUSTER_NAME | grep -E 'State|Status'"
```

**Installation typically takes 15-30 minutes.**

---

## Phase 5: Post-Installation Verification

### Step 5.1: Verify Cluster Status

```bash
# Check cluster is ready
rosa describe cluster --cluster=$CLUSTER_NAME

# Expected State: ready
```

### Step 5.2: Create Admin User

```bash
# Create cluster admin
rosa create admin --cluster=$CLUSTER_NAME

# Note the credentials provided
# Example output:
# Login: oc login https://api.my-rosa-cluster.xxxx.p1.openshiftapps.com:6443 \
#        --username cluster-admin --password XXXXX-XXXXX-XXXXX-XXXXX
```

### Step 5.3: Access the Cluster

```bash
# Get API URL
API_URL=$(rosa describe cluster --cluster=$CLUSTER_NAME --output json | jq -r '.api.url')
echo "API URL: $API_URL"

# Get Console URL
CONSOLE_URL=$(rosa describe cluster --cluster=$CLUSTER_NAME --output json | jq -r '.console.url')
echo "Console URL: $CONSOLE_URL"

# Login to cluster (from a machine with access to private network)
oc login $API_URL --username cluster-admin --password <password>

# Verify nodes
oc get nodes

# Verify cluster operators
oc get clusteroperators
```

### Step 5.4: Verify Cluster Health

```bash
# Check all operators are available
oc get clusteroperators | grep -v "True.*False.*False"

# Check all nodes are ready
oc get nodes | grep -v " Ready"

# Check all pods are running
oc get pods -A | grep -v "Running\|Completed"
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: InvalidIdentityToken - No OpenIDConnect provider found

**Error:**
```
InvalidIdentityToken: No OpenIDConnect provider found in your account for https://...
```

**Solution:**
```bash
# Create the missing OIDC Provider
rosa create oidc-provider --oidc-config-id=$OIDC_ID --mode=auto --yes

# Verify
aws iam list-open-id-connect-providers
```

#### Issue 2: Access Denied when assuming Shared VPC roles

**Error:**
```
Access Denied when assuming role arn:aws:iam::...:role/...-Route53-Role
```

**Solution:**
Verify trust policies in Shared VPC account include the correct cluster account role ARNs:
```bash
aws iam get-role --role-name "${CLUSTER_NAME}-Route53-Role" --query 'Role.AssumeRolePolicyDocument'
```

#### Issue 3: Subnet not found or access denied

**Error:**
```
Subnet subnet-xxx not found or you do not have access
```

**Solution:**
1. Verify RAM share is accepted in cluster account
2. Verify subnets are shared correctly:
```bash
aws ram get-resource-shares --resource-owner OTHER-ACCOUNTS
aws ec2 describe-subnets --subnet-ids $SUBNET_IDS
```

#### Issue 4: Cluster stuck in "installing" state

**Solution:**
```bash
# Check installation logs
rosa logs install --cluster=$CLUSTER_NAME

# Check for specific errors
rosa describe cluster --cluster=$CLUSTER_NAME --output json | jq '.status'
```

### Useful Debugging Commands

```bash
# List all ROSA resources
rosa list clusters
rosa list account-roles
rosa list operator-roles --prefix $CLUSTER_NAME
rosa list oidc-config
rosa list oidc-provider

# Check AWS IAM
aws iam list-roles --query "Roles[?contains(RoleName, '$CLUSTER_NAME')]"
aws iam list-open-id-connect-providers

# Check cluster logs
rosa logs install --cluster=$CLUSTER_NAME
rosa logs uninstall --cluster=$CLUSTER_NAME
```

---

## Cleanup

### Delete Cluster

```bash
# Delete cluster
rosa delete cluster --cluster=$CLUSTER_NAME --yes --watch

# Wait for deletion to complete
```

### Delete ROSA Resources (Cluster Account)

```bash
# Delete operator roles
rosa delete operator-roles --prefix $CLUSTER_NAME --mode auto --yes

# Delete OIDC provider
rosa delete oidc-provider --oidc-config-id $OIDC_ID --mode auto --yes

# Delete OIDC config
rosa delete oidc-config --oidc-config-id $OIDC_ID --mode auto --yes

# Delete account roles
rosa delete account-roles --prefix $CLUSTER_NAME --mode auto --yes

# Delete DNS domain (if no longer needed)
rosa delete dns-domain --dns-domain $DNS_DOMAIN --yes
```

### Delete Shared VPC Resources (Shared VPC Account)

```bash
export AWS_PROFILE=shared-vpc-account

# Delete IAM roles
aws iam delete-role-policy --role-name "${CLUSTER_NAME}-Route53-Role" --policy-name "Route53Policy"
aws iam delete-role --role-name "${CLUSTER_NAME}-Route53-Role"

aws iam delete-role-policy --role-name "${CLUSTER_NAME}-VPC-Endpoint-Role" --policy-name "VPCEndpointPolicy"
aws iam delete-role --role-name "${CLUSTER_NAME}-VPC-Endpoint-Role"

# Delete RAM share
aws ram delete-resource-share --resource-share-arn $RESOURCE_SHARE_ARN

# Delete Route53 hosted zones
aws route53 delete-hosted-zone --id $PRIVATE_HOSTED_ZONE_ID
aws route53 delete-hosted-zone --id $HCP_INTERNAL_HOSTED_ZONE_ID

# Delete NAT Gateway
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID
sleep 60  # Wait for NAT Gateway deletion

# Release Elastic IP
aws ec2 release-address --allocation-id $EIP_ALLOC

# Delete subnets
aws ec2 delete-subnet --subnet-id $SUBNET_A
aws ec2 delete-subnet --subnet-id $SUBNET_B
aws ec2 delete-subnet --subnet-id $SUBNET_C
aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET

# Detach and delete Internet Gateway
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# Delete route tables (non-main)
aws ec2 delete-route-table --route-table-id $PUBLIC_RT
aws ec2 delete-route-table --route-table-id $PRIVATE_RT

# Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID
```

---

## Quick Reference

### Environment Variables Checklist

```bash
# Required variables for installation
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "REGION: $REGION"
echo "VERSION: $VERSION"
echo "CLUSTER_ACCOUNT_ID: $CLUSTER_ACCOUNT_ID"
echo "SHARED_VPC_ACCOUNT_ID: $SHARED_VPC_ACCOUNT_ID"
echo "VPC_ID: $VPC_ID"
echo "SUBNET_IDS: $SUBNET_IDS"
echo "OIDC_ID: $OIDC_ID"
echo "DNS_DOMAIN: $DNS_DOMAIN"
echo "PRIVATE_HOSTED_ZONE_ID: $PRIVATE_HOSTED_ZONE_ID"
echo "HCP_INTERNAL_HOSTED_ZONE_ID: $HCP_INTERNAL_HOSTED_ZONE_ID"
echo "ROUTE53_ROLE_ARN: $ROUTE53_ROLE_ARN"
echo "VPC_ENDPOINT_ROLE_ARN: $VPC_ENDPOINT_ROLE_ARN"
```

### Installation Order Summary

1. **Shared VPC Account:**
   - Create VPC and Subnets
   - Create NAT Gateway
   - Create Private Hosted Zones
   - Share Subnets via RAM
   - Create Route53 and VPC Endpoint Roles

2. **Cluster Account:**
   - Create Account Roles
   - Create OIDC Config
   - **Create OIDC Provider** ⚠️
   - Create Operator Roles

3. **Cross-Account:**
   - Update Shared VPC Role trust policies
   - Accept RAM share invitation

4. **Cluster Creation:**
   - Run `rosa create cluster` with all parameters

---

## References

- [ROSA Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/)
- [ROSA HCP Shared VPC Configuration](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_clusters/rosa-hcp-shared-vpc-config)
- [ROSA Prepare IAM Roles](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/prepare_your_environment/rosa-hcp-prepare-iam-roles-resources)
- [AWS RAM Documentation](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html)

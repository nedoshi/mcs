cluster creation and management |
| `aws` CLI | v2.x | VPC, IAM, and infrastructure management |
| `terraform` | v1.4.0+ | VPC creation (recommended method) |
| `oc` CLI | Latest | Cluster access after creation |
| `git` | Any | Clone Terraform templates |

### AWS Account Requirements

- ROSA service enabled in the AWS Console
- Sufficient service quotas (VPCs, Elastic IPs, EC2 instances, VPC Endpoints)
- IAM permissions to create: VPCs, subnets, security groups, VPC endpoints, IAM roles/policies

### Red Hat Account

- Active Red Hat account linked to AWS via `rosa login`
- ROSA entitlement / quota available

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                     │
│  AWS Region: ap-southeast-1                                                         │
│                                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────────────┐    │
│  │ Zero-Egress VPC  (10.0.0.0/16)  ─  NO IGW, NO NAT, NO PUBLIC SUBNETS      │    │
│  │                                                                              │    │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐                  │    │
│  │  │ Private Subnet  │  │ Private Subnet  │  │ Private Subnet  │                │    │
│  │  │ AZ-a 10.0.0/24 │  │ AZ-b 10.0.1/24 │  │ AZ-c 10.0.2/24 │                │    │
│  │  │                 │  │                 │  │                 │                 │    │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │  │  ┌───────────┐  │                │    │
│  │  │  │  Worker    │  │  │  │  Worker    │  │  │  │  Worker    │  │                │    │
│  │  │  │  Node      │  │  │  │  Node      │  │  │  │  Node      │  │                │    │
│  │  │  └───────────┘  │  │  └───────────┘  │  │  └───────────┘  │                │    │
│  │  │                 │  │                 │  │                 │                 │    │
│  │  │  ┌───────────┐  │  │                 │  │                 │                │    │
│  │  │  │ Windows    │  │  │                 │  │                 │                │    │
│  │  │  │ Bastion    │  │  │                 │  │                 │                │    │
│  │  │  │ (SSM)      │  │  │                 │  │                 │                │    │
│  │  │  └───────────┘  │  │                 │  │                 │                │    │
│  │  └────────────────┘  └────────────────┘  └────────────────┘                  │    │
│  │                                                                              │    │
│  │  VPC Endpoints (PrivateLink)                                                 │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐                          │    │
│  │  │ STS      │ │ ECR API  │ │ ECR DKR  │ │ S3 GW  │                          │    │
│  │  │ (intf)   │ │ (intf)   │ │ (intf)   │ │ (gw)   │                          │    │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘                          │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐     │                               │    │
│  │  │ SSM      │ │ SSM Msg  │ │ EC2 Msg  │     │                               │    │
│  │  │ (intf)   │ │ (intf)   │ │ (intf)   │     │                               │    │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘     │                               │    │
│  └───────┼────────────┼────────────┼────────────┼───────────────────────────────┘    │
│          │            │            │            │                                     │
│          ▼            ▼            ▼            ▼                                     │
│  ┌───────────────────────────────────────────────────┐                               │
│  │                 AWS Services                       │                               │
│  │                                                    │                               │
│  │  ┌──────────────────────────────────────────────┐  │                               │
│  │  │ ECR (Red Hat Managed: <REDHAT_ECR_ACCOUNT_ID>)           │  │                               │
│  │  │ ► OCP platform images (quay.io mirrors)       │  │                               │
│  │  │ ► Red Hat operator images                     │  │                               │
│  │  └──────────────────────────────────────────────┘  │                               │
│  │  ┌──────────────────────────────────────────────┐  │                               │
│  │  │ ECR (Customer: <AWS_ACCOUNT_ID>)                  │  │                               │
│  │  │ ► openshift-mirror/nvidia/* (GPU Operator)    │  │                               │
│  │  │ ► openshift-mirror/redhat/certified-op-index  │  │                               │
│  │  └──────────────────────────────────────────────┘  │                               │
│  │  ┌────────────┐  ┌─────────────┐                   │                               │
│  │  │ S3 Bucket  │  │ STS / IAM   │                   │                               │
│  │  │ (staging)  │  │             │                   │                               │
│  │  └────────────┘  └─────────────┘                   │                               │
│  └───────────────────────────────────────────────────┘                               │
│                                                                                     │
│  ┌───────────────────────────────────────────────────┐                               │
│  │  ROSA HCP Control Plane (Red Hat Managed)         │                               │
│  │  ► Hosted etcd, API server, controllers           │                               │
│  │  ► Connected via AWS PrivateLink                  │                               │
│  └───────────────────────────────────────────────────┘                               │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

External (Internet-Connected) ─── used only during setup ───
┌─────────────────────────────┐
│  Mirror Host (temp EC2)     │     oc-mirror v2
│  or Admin Workstation       │──── pulls from registry.redhat.io, nvcr.io
│                             │──── pushes to Customer ECR & S3
│  rosa CLI, aws CLI          │──── creates cluster, manages IAM
└─────────────────────────────┘
```

**Image flow:**
- Red Hat platform images: `quay.io` / `registry.redhat.io` → Red Hat ECR (`<REDHAT_ECR_ACCOUNT_ID>`) → Worker nodes (via ECR VPC endpoints)
- Third-party operators (NVIDIA): `nvcr.io` → Customer ECR (`<AWS_ACCOUNT_ID>`) → Worker nodes (via ECR VPC endpoints)
- S3 staging: CLI binaries, mirror archives, manifests transferred via S3 Gateway endpoint

---

## 4. Deployment Plan — Step by Step

### Phase 1: Environment Setup

#### Step 1.1: Set Environment Variables

```bash
export AWS_DEFAULT_REGION=us-east-2          # Choose your region
export REGION=$AWS_DEFAULT_REGION
export CLUSTER_NAME=rosa-zero-egress         # Max 15 chars for domain prefix
export VPC_CIDR="10.0.0.0/16"
export PRIVATE_SUBNET_1="10.0.0.0/24"
export PRIVATE_SUBNET_2="10.0.1.0/24"
export PRIVATE_SUBNET_3="10.0.2.0/24"
export OPERATOR_ROLES_PREFIX=$CLUSTER_NAME
export ACCOUNT_ROLES_PREFIX="ManagedOpenShift"
```

> **Note**: Region choice matters. ECR mirrors exist in all standard ROSA-supported regions. Verify with `rosa list versions --hosted-cp` after setting the region.

#### Step 1.2: Login

```bash
# AWS (configure with the new project credentials)
aws configure

# Red Hat
rosa login --token=<your-ocm-token>

# Verify
rosa whoami
aws sts get-caller-identity
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

---

### Phase 2: Create the Zero-Egress VPC

This is the most critical difference from a standard deployment. The VPC has **no IGW, no NAT GW, no public subnets**.

#### Option A: Terraform (Recommended)

Uses the official Red Hat Terraform template for zero-egress VPCs.

```bash
git clone https://github.com/openshift-cs/terraform-vpc-example
cd terraform-vpc-example/zero-egress
terraform init
```

Plan the VPC:

```bash
terraform plan -out rosa-zero-egress.tfplan \
  -var region=$REGION \
  -var "availability_zones=[\"${REGION}a\", \"${REGION}b\", \"${REGION}c\"]" \
  -var vpc_cidr_block=$VPC_CIDR \
  -var "private_subnets=[\"$PRIVATE_SUBNET_1\", \"$PRIVATE_SUBNET_2\", \"$PRIVATE_SUBNET_3\"]" \
  -var cluster_name=$CLUSTER_NAME
```

Apply:

```bash
terraform apply rosa-zero-egress.tfplan
```

**What the Terraform template creates:**

| Resource | Type | Details |
|----------|------|---------|
| VPC | `aws_vpc` | CIDR `10.0.0.0/16`, DNS hostnames + support enabled |
| Private Subnets (x3) | `aws_subnet` | One per AZ, tagged `kubernetes.io/role/internal-elb=1` |
| Security Group | `aws_security_group` | Allows all inbound from private subnet CIDRs, all outbound |
| STS VPC Endpoint | Interface (`com.amazonaws.<region>.sts`) | Private DNS enabled |
| ECR API VPC Endpoint | Interface (`com.amazonaws.<region>.ecr.api`) | Private DNS enabled |
| ECR DKR VPC Endpoint | Interface (`com.amazonaws.<region>.ecr.dkr`) | Private DNS enabled |
| S3 VPC Endpoint | Gateway (`com.amazonaws.<region>.s3`) | Attached to private route tables |

**What it does NOT create (by design):**
- No Internet Gateway
- No NAT Gateway
- No public subnets
- No Elastic IPs
- No public route table

After apply, capture the outputs:

```bash
export VPC_ID=$(terraform output -raw vpc_id)
export PRIVATE_SUBNET_IDS=$(terraform output -raw private_subnet_ids)
# Format: "subnet-xxx,subnet-yyy,subnet-zzz"
```

#### Option B: ROSA CLI (`rosa create network`)

Available in ROSA CLI v1.2.48+. Uses AWS CloudFormation under the hood.

```bash
rosa create network \
  --param Region=$REGION \
  --param Name=${CLUSTER_NAME}-network \
  --param AvailabilityZoneCount=3 \
  --param VpcCidr=$VPC_CIDR
```

> **Note**: The default `rosa create network` template creates an IGW and NAT GW (standard VPC). For zero egress, you may need to use the Terraform method or a custom CloudFormation template. The default template output includes public subnets and NAT gateways which are **not needed** for zero egress. Validate whether `rosa create network` has a zero-egress-specific template during actual deployment.

#### Option C: AWS CLI (Manual)

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${CLUSTER_NAME}-vpc}]" \
  --query 'Vpc.VpcId' --output text)

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'

# Create private subnets (one per AZ)
SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_1 --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-1},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)

SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_2 --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-2},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)

SUBNET_3=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_3 --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-3},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)

# Create security group allowing all inbound from private subnets
SG_ID=$(aws ec2 create-security-group \
  --group-name ${CLUSTER_NAME}-vpce-sg \
  --description "Allow inbound from private subnets for VPC endpoints" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol -1 --cidr $PRIVATE_SUBNET_1
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol -1 --cidr $PRIVATE_SUBNET_2
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol -1 --cidr $PRIVATE_SUBNET_3

# Create VPC Endpoints
# 1. STS (Interface)
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.sts \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled

# 2. ECR API (Interface)
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.ecr.api \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled

# 3. ECR DKR (Interface)
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.ecr.dkr \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled

# 4. S3 (Gateway)
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Gateway \
  --service-name com.amazonaws.${REGION}.s3 \
  --route-table-ids $ROUTE_TABLE_ID

export PRIVATE_SUBNET_IDS="$SUBNET_1,$SUBNET_2,$SUBNET_3"
```

---

### Phase 3: Create IAM Roles

#### Step 3.1: Create Account-Wide Roles

```bash
rosa create account-roles --hosted-cp --mode auto --yes
```

#### Step 3.2: Attach ECR ReadOnly Policy to Worker Role

This is the **key IAM difference** for zero egress. The worker nodes need permission to pull from ECR.

```bash
aws iam attach-role-policy \
  --role-name ${ACCOUNT_ROLES_PREFIX}-HCP-ROSA-Worker-Role \
  --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
```

**Verify:**

```bash
aws iam list-attached-role-policies \
  --role-name ${ACCOUNT_ROLES_PREFIX}-HCP-ROSA-Worker-Role
```

You should see `AmazonEC2ContainerRegistryReadOnly` in the list.

#### Step 3.3: Create OIDC Configuration

```bash
rosa create oidc-config --mode=auto --yes
export OIDC_ID=<oidc_config_id_from_output>
```

#### Step 3.4: Create Operator Roles

```bash
rosa create operator-roles --hosted-cp \
  --prefix=$OPERATOR_ROLES_PREFIX \
  --oidc-config-id=$OIDC_ID \
  --installer-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ACCOUNT_ROLES_PREFIX}-HCP-ROSA-Installer-Role \
  --mode auto --yes
```

---

### Phase 4: Create the Cluster

```bash
rosa create cluster \
  --cluster-name=$CLUSTER_NAME \
  --hosted-cp \
  --private \
  --operator-roles-prefix=$OPERATOR_ROLES_PREFIX \
  --oidc-config-id=$OIDC_ID \
  --subnet-ids=$PRIVATE_SUBNET_IDS \
  --region=$REGION \
  --machine-cidr=$VPC_CIDR \
  --service-cidr=172.30.0.0/16 \
  --pod-cidr=10.128.0.0/14 \
  --host-prefix=23 \
  --properties zero_egress:true \
  --mode=auto \
  --yes
```

**Key flags:**
- `--private` — No public API endpoint (no internet path exists anyway)
- `--properties zero_egress:true` — Enables ECR image mirroring, skips internet-dependent steps
- `--subnet-ids` — Only private subnets (no public subnet IDs)
- No `--billing-account` needed unless cross-account billing

#### Monitor Installation

```bash
rosa describe cluster --cluster=$CLUSTER_NAME
rosa logs install --cluster=$CLUSTER_NAME --watch
```

Expected state transitions: `pending` → `installing` → `installing (DNS setup in progress)` → `ready`

Estimated time: **15-30 minutes** (similar to standard HCP).

---

### Phase 5: Access the Cluster

Since this is a private cluster with no internet path, you need network-level access to the VPC to reach the API server.

#### Option A: Jump Host / Bastion in the VPC

Deploy an EC2 instance in one of the private subnets with SSM (Systems Manager) access:

```bash
# Create an SSM VPC endpoint (needed since there's no internet)
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.ssm \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled

aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.ssmmessages \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled

aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.ec2messages \
  --subnet-ids $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --security-group-ids $SG_ID \
  --private-dns-enabled
```

Then launch a bastion with an IAM instance profile that has SSM permissions, and connect via `aws ssm start-session`.

#### Option B: AWS VPN / Direct Connect

If you have an existing VPN or Direct Connect to the VPC, use that to reach the private API endpoint.

#### Option C: VPC Peering

Peer from an existing VPC that has internet access or from your corporate network VPC.

#### Create Cluster Admin

```bash
rosa create admin --cluster=$CLUSTER_NAME
```

Save the credentials and log in from a host with VPC access:

```bash
oc login https://api.<cluster_domain>:6443 --username cluster-admin --password <password>
```

---

## 5. Post-Deployment Validation Checklist

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Cluster status | `rosa describe cluster --cluster=$CLUSTER_NAME` | `State: ready` |
| Nodes ready | `oc get nodes` | All nodes `Ready` |
| Cluster operators | `oc get clusteroperators` | All `Available=True`, no `Degraded=True` |
| Image source | `oc get imagecontentsourcepolicy` or `oc get imagedigestmirrorset` | Shows ECR mirror rules |
| ECR connectivity | `oc debug node/<node> -- chroot /host curl -s https://api.ecr.<region>.amazonaws.com/` | 200 OK (via VPC endpoint) |
| No internet | `oc debug node/<node> -- chroot /host curl -s --connect-timeout 5 https://quay.io` | Timeout / connection refused |
| VPC endpoints | `aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID"` | 4 endpoints (STS, ECR API, ECR DKR, S3) |
| Operator catalog | `oc get catalogsource -n openshift-marketplace` | Sources present and healthy |
| Pod image pulls | `oc get pods -A \| grep -v Running \| grep -v Completed` | No `ImagePullBackOff` for platform pods |

---

## 6. Known Limitations & Workarounds

### Limitation 1: Workloads Needing Public Registries

Pods pulling from `docker.io`, `ghcr.io`, `quay.io`, etc. will fail.

**Workarounds:**
- Mirror required images to a private ECR repository in the same region
- Set up an internal image registry and configure `ImageDigestMirrorSet` / `ImageTagMirrorSet`
- Add a NAT Gateway to a single subnet for controlled egress (breaks the "zero" part)

### Limitation 2: Only Default Operator Channel Mirrored

If you need a non-default Operator channel, it won't be available from the ECR mirror.

**Workaround:** Mirror the specific Operator catalog to a private ECR repo.

### Limitation 3: Internal Image Registry Limitations

Due to upstream issues with the internal image registry in disconnected environments, builds that push to the internal registry may fail.

**Workaround:** Use the latest z-stream release. Red Hat is actively fixing this.

### Limitation 4: No Telemetry / Insights

Cluster health telemetry won't reach Red Hat. Support cases may require manual must-gather uploads.

### Limitation 5: Cluster Access Requires VPC Connectivity

You cannot `oc login` from the public internet. A bastion, VPN, or Direct Connect is required.

### Limitation 6: ROSA CLI Cannot Run from Within the Zero-Egress VPC

**Observed during deployment:** `rosa login` requires internet access to `sso.redhat.com` for OAuth token exchange. From within the zero-egress VPC (e.g., the Windows bastion), this times out with:
```
ERR: Failed to create OCM connection: can't send request: Post "https://sso.redhat.com/...": dial tcp: i/o timeout
```

**Workaround:** Run `rosa` commands from an internet-connected machine (your local workstation). Only `oc` and `aws` CLIs work from within the VPC. The `oc` CLI connects to the private cluster API via PrivateLink, and the `aws` CLI uses STS/S3 via VPC endpoints.

### Limitation 7: CLI Installation on Bastion Requires S3 Staging

Since the bastion has no internet, you cannot download CLI binaries directly. The approach used:
1. Download binaries on an internet-connected machine
2. Upload to an S3 bucket in the same region
3. Download from S3 on the bastion (via the S3 Gateway VPC endpoint)

---

## 7. Cost Comparison

| Component | Standard ROSA HCP | Zero Egress ROSA HCP |
|-----------|-------------------|----------------------|
| NAT Gateway | ~$0.045/hr + $0.045/GB processed | **$0 — not used** |
| VPC Interface Endpoints (x3) | Not required | ~$0.01/hr each × 3 × AZs |
| VPC Gateway Endpoint (S3) | Not required | **Free** |
| Data transfer (NAT) | $0.045/GB outbound | **$0 — no outbound** |
| Data transfer (VPC endpoints) | N/A | $0.01/GB processed |
| ECR | N/A | **Free** (Red Hat-managed mirror) |

**Typical savings:** For a cluster pulling ~100 GB/month of images, zero egress saves approximately **$30-50/month** on NAT Gateway fees alone, while VPC endpoint costs are ~$22/month (3 interface endpoints × 1 AZ). Multi-AZ deployments increase endpoint costs linearly but NAT savings also scale.

The primary motivation is **security** (no internet egress path), not cost savings.

---

## 8. Cleanup Plan

When the cluster is no longer needed:

```bash
# Delete the cluster
rosa delete cluster --cluster=$CLUSTER_NAME --yes --watch

# Delete operator roles
rosa delete operator-roles --prefix=$OPERATOR_ROLES_PREFIX --mode auto --yes

# Delete OIDC config
rosa delete oidc-config --oidc-config-id=$OIDC_ID --mode auto --yes

# Delete the VPC (if created with Terraform)
cd terraform-vpc-example/zero-egress
terraform destroy -var region=$REGION \
  -var "availability_zones=[\"${REGION}a\", \"${REGION}b\", \"${REGION}c\"]" \
  -var vpc_cidr_block=$VPC_CIDR \
  -var "private_subnets=[\"$PRIVATE_SUBNET_1\", \"$PRIVATE_SUBNET_2\", \"$PRIVATE_SUBNET_3\"]" \
  -var cluster_name=$CLUSTER_NAME

# Or if created with AWS CLI, delete VPC endpoints, subnets, SG, VPC manually
```

---

## 9. Windows Jump Host & Session Manager Access

### Deployed Resources

| Resource | ID/Value |
|----------|----------|
| Instance ID | `<BASTION_INSTANCE_ID>` |
| Instance Type | `t3.medium` |
| OS | Windows Server 2022 Datacenter |
| Private IP | `10.0.0.120` |
| Subnet | `<BASTION_SUBNET_ID>` (ap-southeast-1a) |
| Security Group | `<BASTION_SG_ID>` |
| IAM Role | `rosazeroeg-bastion-ssm-role` |
| Instance Profile | `rosazeroeg-bastion-profile` |

### Additional VPC Endpoints for SSM

| Endpoint | ID | Service |
|----------|----|---------|
| SSM | `<SSM_VPCE_ID>` | `com.amazonaws.ap-southeast-1.ssm` |
| SSM Messages | `<SSM_MSG_VPCE_ID>` | `com.amazonaws.ap-southeast-1.ssmmessages` |
| EC2 Messages | `<EC2_MSG_VPCE_ID>` | `com.amazonaws.ap-southeast-1.ec2messages` |

### How to Access the Jump Host via Session Manager

#### Option 1: AWS Console (GUI)

1. Go to **AWS Systems Manager** > **Session Manager** in the `ap-southeast-1` region
2. Click **Start session**
3. Select instance `<BASTION_INSTANCE_ID>` (`rosazeroeg-windows-bastion`)
4. Click **Start session** — opens a PowerShell terminal in your browser

#### Option 2: AWS CLI

```bash
# Prerequisites: Install the Session Manager plugin
# macOS: brew install --cask session-manager-plugin
# Windows: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# Start a session
aws ssm start-session \
  --target <BASTION_INSTANCE_ID> \
  --region ap-southeast-1

# Start a port-forwarding session (e.g., to use RDP)
aws ssm start-session \
  --target <BASTION_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3389"],"localPortNumber":["33389"]}' \
  --region ap-southeast-1
# Then connect via RDP to localhost:33389
```

#### Option 3: Send Commands Remotely (no interactive session needed)

```bash
aws ssm send-command \
  --instance-ids <BASTION_INSTANCE_ID> \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["oc get nodes","oc get clusterversion"]' \
  --region ap-southeast-1 \
  --query 'Command.CommandId' --output text

# Retrieve output
aws ssm get-command-invocation \
  --command-id <COMMAND_ID> \
  --instance-id <BASTION_INSTANCE_ID> \
  --query '[Status,StandardOutputContent]' --output text
```

### Installed CLIs on Jump Host

| CLI | Version | Path | Works from VPC? |
|-----|---------|------|-----------------|
| AWS CLI | v2.34.10 | `C:\Program Files\Amazon\AWSCLIV2\aws.exe` | Yes (via STS VPC endpoint) |
| ROSA CLI | v1.2.53 | `C:\Windows\System32\rosa.exe` | No (requires internet for `sso.redhat.com`) |
| OC CLI | v4.21.4 | `C:\Windows\System32\oc.exe` | Yes (cluster API is private within VPC) |

### S3 Staging Bucket

CLI binaries were staged via `s3://rosazeroeg-staging-<AWS_ACCOUNT_ID>/cli/` since the bastion has no internet access. The bastion downloads from S3 using the S3 Gateway VPC endpoint.

---

## 10. Deployment Log

### Actual Deployment — 2026-03-17

| Step | Planned | Actual | Notes |
|------|---------|--------|-------|
| VPC creation | Terraform zero-egress template | **AWS CLI** (Terraform not installed) | VPC `<VPC_ID>` created |
| VPC endpoints verified | 4 endpoints (STS, ECR API, ECR DKR, S3) | **4 endpoints created** | All in `available` state |
| No IGW/NAT verified | No IGW, no NAT, no public subnets | **Verified** | `describe-internet-gateways` and `describe-nat-gateways` return empty |
| Account roles | `rosa create account-roles --hosted-cp` | **Created** | ECR ReadOnly auto-attached to Worker Role |
| OIDC config | `rosa create oidc-config` | **Created** | ID: `2p38fhrmfs7s9h5fib2pq419mldtkarq` |
| Operator roles | `rosa create operator-roles --hosted-cp` | **Created** | 8 roles, prefix `rosazeroeg` |
| OCM + User roles | Needed for billing | **Created** | Required for billing account linkage |
| Cluster creation | `--properties zero_egress:true` | **Created** at 04:23 UTC | Billing account `<BILLING_ACCOUNT_ID>` (cross-account) |
| Cluster ready | 15-30 min expected | **~8 min** to `ready` state | Faster than expected |
| Worker nodes | 3 nodes | **3 nodes Ready** across 3 AZs | `10.0.0.31`, `10.0.1.81`, `10.0.2.186` |
| Cluster admin | `rosa create admin` | **Created** | user: `cluster-admin` |
| Windows bastion | SSM access | **Working** | Instance `<BASTION_INSTANCE_ID>`, SSM Online |
| AWS CLI login | Bastion | **Confirmed** | `sts get-caller-identity` returns `<AWS_ACCOUNT_ID>` |
| ROSA login | Bastion | **Failed (expected)** | Requires internet for `sso.redhat.com` |
| OC login | Bastion | **Confirmed** | `oc whoami` returns `cluster-admin` |

### Key Observations

1. **Billing account cross-linking works**: Used billing account `<BILLING_ACCOUNT_ID>` from a different AWS account — the Red Hat organization links them
2. **Cluster install was fast**: ~8 minutes from `waiting` to `ready`, faster than standard HCP
3. **ROSA CLI auto-detected ECR policy**: When creating account roles with `--hosted-cp`, the CLI automatically attached `AmazonEC2ContainerRegistryReadOnly` to the Worker Role
4. **SSM endpoints are essential**: Without SSM VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`), the SSM agent cannot register and the bastion is unreachable
5. **S3 staging pattern**: Without internet, all software must be staged via S3. The S3 Gateway endpoint is free and provides the path for this
6. **`rosa` CLI unusable from VPC**: Expected limitation. ROSA management is done from an internet-connected machine; `oc` is the operational tool from within the VPC
7. **Version 4.18.34**: Used latest 4.18 z-stream as recommended by Red Hat for zero egress stability

### Cluster Details

| Property | Value |
|----------|-------|
| Cluster Name | `rosazeroeg` |
| Cluster ID | `2p38idgsae168pmg260fobnch7vvc288` |
| OpenShift Version | 4.18.34 |
| Region | ap-southeast-1 |
| DNS | `rosazeroeg.<CLUSTER_HASH>.openshiftapps.com` |
| API URL | `https://api.rosazeroeg.<CLUSTER_HASH>.openshiftapps.com:443` |
| Private | Yes |
| Zero Egress | Enabled |
| Workers | 3 x m5.xlarge (one per AZ) |
| Network | OVNKubernetes |
| Machine CIDR | 10.0.0.0/16 |
| VPC ID | `<VPC_ID>` |
| AWS Account | <AWS_ACCOUNT_ID> |
| Billing Account | <BILLING_ACCOUNT_ID> |

---

## 11. Configuring Third-Party Operators on Disconnected ROSA HCP Clusters

> **Status:** Executed on 2026-03-17. Validated with NVIDIA GPU Operator v25.10.1. IDMS configured via `rosa create image-mirror` (ROSA CLI ≥ 1.2.57).

### The Problem

Red Hat mirrors its own Operators (from `redhat-operator-index`) to a managed ECR account (`<REDHAT_ECR_ACCOUNT_ID>`) for zero-egress clusters. However, **third-party operators** from the `certified-operator-index` or `community-operator-index` — such as the **NVIDIA GPU Operator** — are **not mirrored**. These operators and their operand images must be manually mirrored to a customer-owned ECR in the same region.

### ROSA HCP and ImageDigestMirrorSet (IDMS)

On ROSA HCP, the IDMS is managed by HyperShift (`hypershift.openshift.io/managed: "true"`). You **cannot** directly `oc apply` an IDMS YAML — a `ValidatingAdmissionPolicy` blocks it. However, **Red Hat added official support for customer-managed image mirrors via the ROSA CLI** (starting in ROSA CLI v1.2.57, OCM-17876).

The correct approach uses `rosa create image-mirror` which injects entries into the HyperShift-managed IDMS, enabling transparent redirect of image pulls at the node level — **no ClusterPolicy image overrides needed**.

**The supported workflow** is:
1. Mirror the operator catalog and images to your own ECR (using `oc-mirror`)
2. Create a `CatalogSource` pointing to the mirrored catalog in ECR
3. **Configure IDMS via `rosa create image-mirror`** to redirect source registries to your ECR
4. Install the operator normally — operand images are transparently pulled from ECR via IDMS

### Mirroring Workflow Diagram

```
                Internet-Connected Host
                (Temp EC2 or Workstation)
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
 registry.redhat.io   nvcr.io    registry.connect.redhat.com
 (certified-op-index) (NVIDIA    (gpu-operator-bundle)
                       operands)
        │                │                │
        └────────┬───────┘────────────────┘
                 ▼
          ┌─────────────┐
          │  oc-mirror   │ ── Step 1: Mirror to disk
          │  --v2        │    (file:///mirror-output)
          └──────┬──────┘
                 │ mirror_000001.tar (13 GB)
                 ▼
          ┌─────────────┐
          │  S3 Bucket   │ ── Step 2: Upload archive
          │  (staging)   │    (aws s3 cp)
          └──────┬──────┘
                 │
                 ▼
          ┌─────────────┐
          │  oc-mirror   │ ── Step 3: Push to ECR
          │  --from disk │    (disk-to-mirror)
          └──────┬──────┘
                 │ Generates: CatalogSource YAML, IDMS YAML
                 ▼
    ┌────────────────────────┐
    │  Customer ECR          │
    │  <AWS_ACCOUNT_ID>.dkr.ecr  │
    │  .ap-southeast-1       │
    │  .amazonaws.com/       │
    │  openshift-mirror/*    │ ◄── 14 repositories, 16 images
    └────────────┬───────────┘
                 │ (via ECR VPC Endpoints)
                 ▼
    ┌────────────────────────┐
    │  ROSA HCP Cluster      │
    │  ► CatalogSource →     │ ── Step 4: Apply CatalogSource
    │    ECR catalog index   │    (oc apply from bastion)
    │  ► IDMS via rosa CLI   │ ── Step 5: rosa create image-mirror
    │    (nvcr.io→ECR)       │    (redirects operand pulls)
    │  ► OLM sees GPU Op     │
    │    in OperatorHub       │ ── Step 6: Install operator
    └────────────────────────┘
```

### Step-by-Step Instructions

#### Prerequisites

- A running ROSA HCP zero-egress cluster with `oc` access (via bastion)
- An S3 bucket in the same region (for staging)
- Worker IAM role has `AmazonEC2ContainerRegistryReadOnly` (standard for zero-egress)
- Red Hat pull secret (download from <https://console.redhat.com/openshift/install/pull-secret>)

#### Step 1: Launch a Temporary Linux Mirror Host

`oc-mirror` is a Linux x86_64 binary. Create a temporary EC2 in a **separate internet-connected VPC** in the same region.

```bash
# Create a simple VPC with internet (IGW + public subnet)
MIRROR_VPC=$(aws ec2 create-vpc --cidr-block 10.99.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $MIRROR_VPC --enable-dns-hostnames '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $MIRROR_VPC --enable-dns-support '{"Value":true}'

MIRROR_SUBNET=$(aws ec2 create-subnet --vpc-id $MIRROR_VPC --cidr-block 10.99.1.0/24 \
  --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)

MIRROR_IGW=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $MIRROR_IGW --vpc-id $MIRROR_VPC

MIRROR_RTB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$MIRROR_VPC" \
  --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-route --route-table-id $MIRROR_RTB --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $MIRROR_IGW
aws ec2 modify-subnet-attribute --subnet-id $MIRROR_SUBNET --map-public-ip-on-launch

# Create IAM role with SSM + S3 + ECR push access
aws iam create-role --role-name mirror-temp-role --assume-role-policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
aws iam create-instance-profile --instance-profile-name mirror-temp-profile
aws iam add-role-to-instance-profile --instance-profile-name mirror-temp-profile \
  --role-name mirror-temp-role
sleep 10

# Launch instance (Amazon Linux 2023, m5.xlarge, 200GB disk)
AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

MIRROR_SG=$(aws ec2 create-security-group --group-name mirror-temp-sg \
  --description "Temp mirror host" --vpc-id $MIRROR_VPC --query 'GroupId' --output text)

MIRROR_INST=$(aws ec2 run-instances --image-id $AMI_ID --instance-type m5.xlarge \
  --subnet-id $MIRROR_SUBNET --security-group-ids $MIRROR_SG \
  --iam-instance-profile Name=mirror-temp-profile \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mirror-temp-host}]' \
  --query 'Instances[0].InstanceId' --output text)
```

Wait for SSM to come online, then install tools via `aws ssm send-command`:

```bash
# Install oc-mirror and oc CLI
curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.18/oc-mirror.tar.gz \
  | tar xz && mv oc-mirror /usr/local/bin/
curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.18/openshift-client-linux.tar.gz \
  | tar xz && mv oc kubectl /usr/local/bin/
```

#### Step 2: Prepare the Pull Secret

`oc-mirror` needs credentials for both source registries and ECR.

```bash
# Get Red Hat pull secret via OCM API
ACCESS_TOKEN=$(curl -s https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
  -d grant_type=refresh_token -d client_id=cloud-services \
  -d "refresh_token=<YOUR_OCM_OFFLINE_TOKEN>" | jq -r .access_token)

curl -s https://api.openshift.com/api/accounts_mgmt/v1/access_token \
  -H "Authorization: Bearer $ACCESS_TOKEN" --data '{}' -X POST > /root/pull-secret.json

# Get ECR auth and merge
ECR_REGISTRY="<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com"
ECR_TOKEN=$(aws ecr get-login-password --region <REGION>)
ECR_AUTH=$(printf "AWS:%s" "$ECR_TOKEN" | base64 -w0)

jq --arg reg "$ECR_REGISTRY" --arg auth "$ECR_AUTH" \
  '.auths[$reg] = {"auth": $auth}' /root/pull-secret.json > /root/.docker/config.json
```

#### Step 3: Discover Available Operator Channels

```bash
oc-mirror list operators --v1 \
  --catalog=registry.redhat.io/redhat/certified-operator-index:v4.18 \
  --package=gpu-operator-certified
```

Output shows all channels. Use the `defaultChannel` value in the next step.

#### Step 4: Create ImageSetConfiguration

```yaml
# imageset-config-gpu.yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/certified-operator-index:v4.18
      packages:
        - name: gpu-operator-certified
          defaultChannel: v25.10
          channels:
            - name: v25.10
              minVersion: "25.10.1"
              maxVersion: "25.10.1"
```

Key points:
- **`defaultChannel` must match** the catalog's actual default, or oc-mirror fails with a filtering error
- Use `minVersion`/`maxVersion` to pin a single version and minimize download size
- Omit NFD — it's already mirrored by Red Hat for zero-egress clusters

#### Step 5: Mirror to Disk

```bash
oc-mirror --v2 --config imageset-config-gpu.yaml file:///root/mirror-output
```

This pulls the filtered catalog and all 16 operand images (~13 GB archive).

#### Step 6: Upload Archive to S3

```bash
aws s3 cp /root/mirror-output/mirror_000001.tar \
  s3://<STAGING_BUCKET>/mirror/mirror_000001.tar
aws s3 sync /root/mirror-output/working-dir/ \
  s3://<STAGING_BUCKET>/mirror/working-dir/
```

#### Step 7: Pre-Create ECR Repositories and Push to ECR

ECR requires repositories to exist before push. Create them based on the images discovered by oc-mirror:

```bash
ECR_REGISTRY="<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com"

for repo in \
  "openshift-mirror/nvidia/cloud-native/gdrdrv" \
  "openshift-mirror/nvidia/cloud-native/k8s-mig-manager" \
  "openshift-mirror/nvidia/cloud-native/k8s-driver-manager" \
  "openshift-mirror/nvidia/cloud-native/vgpu-device-manager" \
  "openshift-mirror/nvidia/cloud-native/dcgm" \
  "openshift-mirror/nvidia/cuda" \
  "openshift-mirror/nvidia/driver" \
  "openshift-mirror/nvidia/gpu-operator" \
  "openshift-mirror/nvidia/gpu-operator-bundle" \
  "openshift-mirror/nvidia/k8s-device-plugin" \
  "openshift-mirror/nvidia/k8s/container-toolkit" \
  "openshift-mirror/nvidia/k8s/dcgm-exporter" \
  "openshift-mirror/nvidia/kubevirt-gpu-device-plugin" \
  "openshift-mirror/redhat/certified-operator-index"; do
  aws ecr create-repository --repository-name "$repo" --region <REGION> 2>/dev/null || true
done
```

Then push from disk to ECR:

```bash
# Refresh ECR token in docker config before pushing
ECR_TOKEN=$(aws ecr get-login-password --region <REGION>)
ECR_AUTH=$(printf "AWS:%s" "$ECR_TOKEN" | base64 -w0)
jq --arg reg "$ECR_REGISTRY" --arg auth "$ECR_AUTH" \
  '.auths[$reg] = {"auth": $auth}' /root/pull-secret.json > /root/.docker/config.json

oc-mirror --v2 \
  --config imageset-config-gpu.yaml \
  --from file:///root/mirror-output \
  docker://${ECR_REGISTRY}/openshift-mirror
```

This generates three manifest files in `mirror-output/working-dir/cluster-resources/`:
- `idms-oc-mirror.yaml` — ImageDigestMirrorSet (cannot apply on ROSA HCP)
- `cs-certified-operator-index-v4-18.yaml` — **CatalogSource** (apply this)
- `cc-certified-operator-index-v4-18.yaml` — ClusterCatalog

#### Step 8: Apply CatalogSource on the Cluster

Upload the CatalogSource manifest to S3, then apply from the bastion:

```bash
# From the mirror host / internet-connected machine:
aws s3 cp mirror-output/working-dir/cluster-resources/cs-certified-operator-index-v4-18.yaml \
  s3://<STAGING_BUCKET>/manifests/cs-catalog.yaml
```

```powershell
# From the Windows bastion (via SSM):
Read-S3Object -BucketName <STAGING_BUCKET> -Key manifests/cs-catalog.yaml -File C:\manifests\cs.yaml
oc apply -f C:\manifests\cs.yaml
```

> **Do NOT apply `idms-oc-mirror.yaml` directly with `oc apply`** — ROSA HCP blocks it with a ValidatingAdmissionPolicy. Instead, use the ROSA CLI to configure image mirrors (see Step 9 below).

#### Step 9: Configure Image Mirrors via ROSA CLI

The ROSA CLI (v1.2.57+) supports `rosa create image-mirror`, which injects entries into the HyperShift-managed IDMS. Use the source-to-mirror mappings from the `oc-mirror`-generated `idms-oc-mirror.yaml` to create image mirror rules.

**Requires:** ROSA CLI ≥ 1.2.57 (check with `rosa version`; upgrade from [GitHub releases](https://github.com/openshift/rosa/releases/))

```bash
# From a machine with ROSA CLI access (e.g., admin workstation):
# Create one mirror rule per source→mirror mapping in the generated IDMS YAML.
# Add mirrors one at a time with ~30 second waits (HyperShift needs time to reconcile).

rosa create image-mirror --cluster=<CLUSTER_NAME> \
  --source=nvcr.io/nvidia/cloud-native \
  --mirrors=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/cloud-native -y

sleep 30

rosa create image-mirror --cluster=<CLUSTER_NAME> \
  --source=nvcr.io/nvidia \
  --mirrors=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia -y

sleep 30

rosa create image-mirror --cluster=<CLUSTER_NAME> \
  --source=nvcr.io/nvidia/k8s \
  --mirrors=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/k8s -y

sleep 30

rosa create image-mirror --cluster=<CLUSTER_NAME> \
  --source=registry.connect.redhat.com/nvidia \
  --mirrors=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia -y

# Verify all mirrors are configured
rosa list image-mirrors --cluster=<CLUSTER_NAME>
```

Expected output:
```
ID                                    TYPE    SOURCE                              MIRRORS
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  digest  nvcr.io/nvidia/k8s                  <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/k8s
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  digest  registry.connect.redhat.com/nvidia  <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  digest  nvcr.io/nvidia                      <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  digest  nvcr.io/nvidia/cloud-native         <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/cloud-native
```

Verify propagation to the cluster IDMS:
```bash
# From the bastion:
oc get imagedigestmirrorset cluster -o jsonpath='{.spec.imageDigestMirrors[*].source}'
# Should include: nvcr.io/nvidia, nvcr.io/nvidia/cloud-native, nvcr.io/nvidia/k8s, registry.connect.redhat.com/nvidia
```

#### Step 10: Verify and Install

```bash
# Verify CatalogSource is READY
oc get catalogsource cs-certified-operator-index-v4-18 -n openshift-marketplace

# Verify GPU Operator is visible
oc get packagemanifest | grep gpu-operator-certified

# Install the operator (when GPU nodes are available)
oc create namespace nvidia-gpu-operator

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
    - nvidia-gpu-operator
EOF

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: v25.10
  name: gpu-operator-certified
  source: cs-certified-operator-index-v4-18
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

#### Step 11: (Optional) Configure Operand Images via ClusterPolicy

> **Note:** With IDMS configured via `rosa create image-mirror` (Step 9), operand image pulls from `nvcr.io` are **automatically redirected** to your ECR by the container runtime. You typically do **not** need to set repository overrides in the ClusterPolicy. This step is only needed if IDMS is not redirecting certain images correctly (e.g., images pulled by tag instead of digest).

```yaml
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
  driver:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia
    image: driver
  toolkit:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/k8s
    image: container-toolkit
  devicePlugin:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia
    image: k8s-device-plugin
  dcgmExporter:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/k8s
    image: dcgm-exporter
  dcgm:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/cloud-native
    image: dcgm
  migManager:
    repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/openshift-mirror/nvidia/cloud-native
    image: k8s-mig-manager
```

#### Step 12: Clean Up the Mirror Host

```bash
aws ec2 terminate-instances --instance-ids $MIRROR_INST
# Wait for termination, then:
aws ec2 delete-security-group --group-id $MIRROR_SG
aws ec2 delete-subnet --subnet-id $MIRROR_SUBNET
aws ec2 detach-internet-gateway --internet-gateway-id $MIRROR_IGW --vpc-id $MIRROR_VPC
aws ec2 delete-internet-gateway --internet-gateway-id $MIRROR_IGW
aws ec2 delete-vpc --vpc-id $MIRROR_VPC
aws iam remove-role-from-instance-profile --instance-profile-name mirror-temp-profile \
  --role-name mirror-temp-role
aws iam delete-instance-profile --instance-profile-name mirror-temp-profile
aws iam detach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam detach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam detach-role-policy --role-name mirror-temp-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
aws iam delete-role --role-name mirror-temp-role
```

### Key Findings & Lessons Learned

1. **`oc-mirror` is Linux x86_64 only** — it does not run on macOS (even via Rosetta). Use a Linux EC2 instance.

2. **`defaultChannel` must be set correctly** in the ImageSetConfiguration. If you filter to a channel that isn't the catalog default, you must explicitly set `defaultChannel` or oc-mirror fails with: *"the default channel was filtered out"*.

3. **`oc-mirror --v2 --from` requires `--config`** — even for disk-to-mirror operations, the `--config` flag is mandatory.

4. **`--from` requires `file://` prefix** — use `file:///path/to/mirror-output`, not just `/path/to/mirror-output`.

5. **ECR repositories must be pre-created** — unlike Docker Hub or Quay, ECR does not auto-create repositories on push. Pre-create them before running disk-to-mirror.

6. **ECR tokens expire every 12 hours** — refresh the token in docker config before the push step if the mirror-to-disk took a long time.

7. **Direct `oc apply` of IDMS is blocked on ROSA HCP** — but `rosa create image-mirror` (CLI ≥ v1.2.57) correctly injects entries into the HyperShift-managed IDMS. Use `rosa create image-mirror` for each source→mirror mapping from the `oc-mirror`-generated `idms-oc-mirror.yaml`. This eliminates the need for operator-level image path overrides in most cases.

8. **Worker nodes can pull from customer ECR** — the `AmazonEC2ContainerRegistryReadOnly` IAM policy on the worker role allows pulls from any ECR repo in the same account without additional pull secrets.

9. **S3 Gateway endpoint is free** — use S3 to stage everything (archives, manifests, CLI binaries) between the internet and the zero-egress VPC.

### ECR Repositories Created

| ECR Repository | Source Registry |
|---|---|
| `openshift-mirror/redhat/certified-operator-index` | `registry.redhat.io/redhat/certified-operator-index` |
| `openshift-mirror/nvidia/gpu-operator` | `nvcr.io/nvidia/gpu-operator` |
| `openshift-mirror/nvidia/gpu-operator-bundle` | `registry.connect.redhat.com/nvidia/gpu-operator-bundle` |
| `openshift-mirror/nvidia/driver` | `nvcr.io/nvidia/driver` |
| `openshift-mirror/nvidia/cuda` | `nvcr.io/nvidia/cuda` |
| `openshift-mirror/nvidia/k8s-device-plugin` | `nvcr.io/nvidia/k8s-device-plugin` |
| `openshift-mirror/nvidia/k8s/container-toolkit` | `nvcr.io/nvidia/k8s/container-toolkit` |
| `openshift-mirror/nvidia/k8s/dcgm-exporter` | `nvcr.io/nvidia/k8s/dcgm-exporter` |
| `openshift-mirror/nvidia/cloud-native/dcgm` | `nvcr.io/nvidia/cloud-native/dcgm` |
| `openshift-mirror/nvidia/cloud-native/gdrdrv` | `nvcr.io/nvidia/cloud-native/gdrdrv` |
| `openshift-mirror/nvidia/cloud-native/k8s-mig-manager` | `nvcr.io/nvidia/cloud-native/k8s-mig-manager` |
| `openshift-mirror/nvidia/cloud-native/k8s-driver-manager` | `nvcr.io/nvidia/cloud-native/k8s-driver-manager` |
| `openshift-mirror/nvidia/cloud-native/vgpu-device-manager` | `nvcr.io/nvidia/cloud-native/vgpu-device-manager` |
| `openshift-mirror/nvidia/kubevirt-gpu-device-plugin` | `nvcr.io/nvidia/kubevirt-gpu-device-plugin` |

### Applying This Process to Other Third-Party Operators

The same workflow applies to any third-party operator. Replace the package name and catalog:

```yaml
# Example: Mirroring the Datadog Operator
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/certified-operator-index:v4.18
      packages:
        - name: datadog-operator-certified
          defaultChannel: <check-with-oc-mirror-list>
          channels:
            - name: <channel>
              minVersion: "<version>"
              maxVersion: "<version>"
```

The steps remain identical: mirror → S3 → ECR → `rosa create image-mirror` → CatalogSource → subscribe. With IDMS handling the image redirect, operator-level image overrides are typically unnecessary.

---

## References

- [Red Hat Docs: Creating ROSA clusters with egress zero](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-egress-zero-install)
- [Red Hat Docs: Egress lockdown install](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-egress-lockdown-install)
- [Red Hat Docs: oc-mirror v2 for disconnected environments](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/disconnected_environments/about-installing-oc-mirror-v2)
- [NVIDIA: Deploy GPU Operators in disconnected/airgapped environments](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.3.0/mirror-gpu-ocp-disconnected.html)
- [NVIDIA: Install GPU Operator in Air-Gapped Environments](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html)
- [Red Hat: Supportability of ImageContentSourcePolicy in ROSA](https://access.redhat.com/solutions/6967643)
- [Red Hat Docs: Image registry mirroring for ROSA HCP (`rosa create image-mirror`)](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/images/image-configuration-hcp)
- [AWS: Configuring ROSA for ECR repository access](https://aws.amazon.com/blogs/ibm-redhat/configuring-rosa-for-fine-grained-ecr-repository-access/)
- [Terraform VPC Example — zero-egress](https://github.com/openshift-cs/terraform-vpc-example/tree/main/zero-egress)
- [AWS ECR Documentation](https://aws.amazon.com/ecr/)
- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)

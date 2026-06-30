## Additional Considerations for Private Clusters

### Network Requirements Summary

#### Private Cluster Characteristics
- **API Server**: Internal load balancer only (no public access)
- **Applications**: Internal ingress only (no public access)  
- **Nodes**: All in private subnets
- **Internet Access**: Via NAT Gateway for pulling images/updates
- **DNS**: Public DNS records resolve to private IPs

#### Access Methods Comparison

| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **Bastion Host** | Simple, cost-effective | Requires SSH tunneling | Development/Testing |
| **VPN Connection** | Direct access, secure | More complex setup | Production |
| **Direct Connect** | High bandwidth, reliable | Expensive, complex | Enterprise |
| **Transit Gateway** | Multi-VPC connectivity | Complex networking | Large organizations |

### Private Cluster Use Cases

#### When to Use Private Clusters
- **High Security Requirements**: Financial services, healthcare
- **Compliance**: HIPAA, SOC 2, PCI-DSS requirements
- **Internal Applications**: No external user access needed  
- **Network Policies**: Strict network segmentation required
- **Data Sovereignty**: Keep all traffic within private networks

#### When to Use Public Clusters
- **Internet-Facing Applications**: Web applications, APIs
- **Development/Testing**: Easy access for developers
- **CI/CD Integration**: External tools need access
- **Simple Setup**: Minimal networking complexity

### Cost Implications

#### Private Cluster Additional Costs
- **NAT Gateway**: ~$45-90/month per AZ
- **VPN Connection**: ~$36/month + data transfer
- **Bastion Host**: ~$8-15/month for t3.micro
- **Data Transfer**: Private subnets may have higher transfer costs

#### Cost Optimization Tips
```bash
# Use single NAT Gateway for development (not recommended for production)
# Consider AWS VPC Endpoints for S3, ECR to reduce NAT Gateway usage
aws ec2 create-vpc-endpoint --vpc-id vpc-xxxxxxxxx --service-name com.amazonaws.region.s3
```## Step 5B: Private Cluster Pre-Installation Setup

If you're installing a **Private Cluster**, you need to set up access methods before installation:

### Method 1: Create Bastion Host (Recommended)

#### Create Bastion Host
```bash
# Create a key pair for bastion
aws ec2 create-key-pair --key-name bastion-key --query 'KeyMaterial' --output text > bastion-key.pem
chmod 400 bastion-key.pem

# Create bastion host in public subnet
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --count 1 \
  --instance-type t3.micro \
  --key-name bastion-key \
  --security-group-ids sg-xxxxxxxxx \
  --subnet-id subnet-xxxxxxxxx \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=OCP-Bastion}]'
```

#### Configure Bastion Security Group
```bash
# Create security group for bastion
aws ec2 create-security-group \
  --group-name ocp-bastion-sg \
  --description "Security group for OCP bastion host"

# Allow SSH access to bastion (replace with your IP)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_PUBLIC_IP/32
```

### Method 2: Use Existing VPN/Direct Connect

If you have existing VPN or Direct Connect:
```bash
# Verify connectivity to AWS VPC
ping 10.0.0.1  # Test internal VPC connectivity

# Ensure DNS resolution works for internal resources
nslookup internal.example.com
```

### Method 3: AWS VPN Client (Alternative)
```bash
# Create Client VPN endpoint (if needed)
aws ec2 create-client-vpn-endpoint \
  --client-cidr-block 192.168.0.0/22 \
  --server-certificate-arn arn:aws:acm:region:account:certificate/certificate-id \
  --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=arn:aws:acm:region:account:certificate/certificate-id}
```# OpenShift Container Platform (OCP) Installation Guide on AWS

## Prerequisites

### 1. Required Accounts and Tools
- AWS Account with appropriate permissions
- Red Hat Account (for pulling container images)
- Domain: `nedoshi.mobb.cloud` (already configured)

### 2. Install Required Tools

#### Install AWS CLI
```bash
# Download and install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
```

#### Install OpenShift Installer
```bash
# Download the OpenShift installer (replace with latest version)
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz
sudo mv openshift-install /usr/local/bin/
chmod +x /usr/local/bin/openshift-install

# Verify installation
openshift-install version
```

#### Install OpenShift CLI (oc)
```bash
# Download OpenShift CLI
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/
chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

# Verify installation
oc version
```

## Step 1: AWS Configuration and Permissions

### Configure AWS CLI
```bash
# Configure AWS credentials
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter your default region (e.g., us-east-1)
# Enter output format: json
```

### Verify AWS Configuration
```bash
# Test AWS connectivity
aws sts get-caller-identity
aws ec2 describe-regions --region us-east-1
```

### Required AWS Permissions
Your AWS user/role needs the following permissions:
- EC2 (full access)
- VPC (full access)
- IAM (full access)
- Route53 (full access)
- S3 (full access)
- CloudFormation (full access)
- ELB (full access)

## Step 2: DNS Configuration Deep Dive

### Understanding DNS for OpenShift

OpenShift requires several DNS records for proper operation:

1. **Base Domain**: `nedoshi.mobb.cloud` (your hosted zone)
2. **Cluster Domain**: `<cluster-name>.nedoshi.mobb.cloud`
3. **API Endpoint**: `api.<cluster-name>.nedoshi.mobb.cloud`
4. **Apps Wildcard**: `*.apps.<cluster-name>.nedoshi.mobb.cloud`

### Verify Your Hosted Zone
```bash
# List your hosted zones
aws route53 list-hosted-zones

# Get details of your hosted zone
aws route53 list-resource-record-sets --hosted-zone-id <your-hosted-zone-id>
```

### DNS Records That Will Be Created
The installer will automatically create:
- A record for API load balancer
- A record for apps wildcard (*.apps)
- Associated load balancers in AWS

## Step 3: Generate SSH Key Pair

```bash
# Generate SSH key for cluster access
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ocp-key
# Press Enter for no passphrase (or set one if preferred)

# Display public key (you'll need this)
cat ~/.ssh/ocp-key.pub
```

## Step 4: Get Red Hat Pull Secret

1. Go to: https://console.redhat.com/openshift/install/pull-secret
2. Login with your Red Hat account
3. Copy the pull secret (it's a JSON string)
4. Save it to a file:

```bash
# Save pull secret to file
cat > pull-secret.txt << 'EOF'
# Paste your pull secret JSON here
EOF
```

## Step 5: Create Installation Configuration

You can install OpenShift in two modes: **Public** or **Private**. Choose based on your security requirements:

- **Public Cluster**: API and applications accessible from the internet
- **Private Cluster**: API and applications only accessible from within VPC or connected networks

### Create Install Directory
```bash
mkdir ocp-install
cd ocp-install
```

### Generate Install Config
```bash
# Create the install-config.yaml
openshift-install create install-config --dir=.
```

You'll be prompted for:
- **SSH Public Key**: Paste the content from `~/.ssh/ocp-key.pub`
- **Platform**: Select `aws`
- **Region**: Choose your AWS region (e.g., `us-east-1`)
- **Base Domain**: Enter `nedoshi.mobb.cloud`
- **Cluster Name**: Choose a name (e.g., `ocp-cluster`)
- **Pull Secret**: Paste the content from `pull-secret.txt`

### Option A: Public Cluster Configuration

```bash
# Backup the generated config
cp install-config.yaml install-config.yaml.backup

# Edit if needed (worker nodes, master nodes, instance types)
vi install-config.yaml
```

Example Public Cluster `install-config.yaml`:
```yaml
apiVersion: v1
baseDomain: nedoshi.mobb.cloud
compute:
- hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.large
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
metadata:
  creationTimestamp: null
  name: ocp-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
publish: External  # This makes it public
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: 'YOUR_SSH_PUBLIC_KEY_HERE'
```

### Option B: Private Cluster Configuration

For a private cluster, you'll need additional setup and configuration:

#### Private Cluster Requirements
1. **Existing VPC** (optional but recommended)
2. **VPN or Direct Connect** for access
3. **Bastion Host** or **VPN** for management access
4. **NAT Gateway** for outbound internet access

#### Private Cluster Install Config
```yaml
apiVersion: v1
baseDomain: nedoshi.mobb.cloud
compute:
- hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.large
      zones:
      - us-east-1a
      - us-east-1b
      - us-east-1c
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
      zones:
      - us-east-1a
      - us-east-1b
      - us-east-1c
  replicas: 3
metadata:
  creationTimestamp: null
  name: ocp-private-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
  machineNetwork:
  - cidr: 10.0.0.0/16
platform:
  aws:
    region: us-east-1
    # Optional: Use existing VPC
    # subnets:
    # - subnet-xxxxxxxxx  # private subnet 1
    # - subnet-yyyyyyyyy  # private subnet 2
    # - subnet-zzzzzzzzz  # private subnet 3
publish: Internal  # This makes it private - key difference!
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: 'YOUR_SSH_PUBLIC_KEY_HERE'
```

## Step 6: Install OpenShift Cluster

### Start Installation
```bash
# This will take 30-45 minutes
openshift-install create cluster --dir=. --log-level=info
```

### Monitor Installation Progress
The installer will show progress. Key phases:
1. **Bootstrap**: Creates bootstrap node
2. **Control Plane**: Sets up master nodes
3. **Workers**: Configures worker nodes
4. **Complete**: Finalizes installation

### Installation Output
Upon success, you'll see:
```
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/path/to/ocp-install/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ocp-cluster.nedoshi.mobb.cloud
INFO Login to the console with user: "kubeadmin", password: "xxxxx-xxxxx-xxxxx-xxxxx"
```

## Step 7: DNS Verification Steps

### For Public Clusters

#### Check DNS Records Created
```bash
# Check API endpoint
nslookup api.ocp-cluster.nedoshi.mobb.cloud

# Check apps wildcard
nslookup console-openshift-console.apps.ocp-cluster.nedoshi.mobb.cloud

# Check if DNS resolves to AWS load balancers
dig api.ocp-cluster.nedoshi.mobb.cloud
dig console-openshift-console.apps.ocp-cluster.nedoshi.mobb.cloud
```

### For Private Clusters

#### Check Private DNS Records
```bash
# From inside VPC (bastion host or VPN connected machine)
nslookup api.ocp-private-cluster.nedoshi.mobb.cloud

# Check apps wildcard (private)
nslookup console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud

# Verify private load balancers
dig api.ocp-private-cluster.nedoshi.mobb.cloud
dig console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud
```

#### Private Cluster DNS Behavior
- DNS records are created in Route53 but resolve to **private IP addresses**
- External DNS queries will return private IPs (10.x.x.x, 172.x.x.x, 192.168.x.x)
- Only accessible from within VPC or connected networks

### Verify Load Balancers in AWS
```bash
# List all load balancers created by OpenShift
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `ocp`) == `true`]'

# For private clusters, check scheme is "internal"
aws elbv2 describe-load-balancers --query 'LoadBalancers[?Scheme==`internal`]'
```

### Test DNS Resolution From Different Locations
```bash
# Test from multiple DNS servers (public cluster)
nslookup api.ocp-cluster.nedoshi.mobb.cloud 8.8.8.8
nslookup api.ocp-cluster.nedoshi.mobb.cloud 1.1.1.1

# For private clusters, test from within VPC only
nslookup api.ocp-private-cluster.nedoshi.mobb.cloud
```

## Step 8: Post-Installation Verification

### For Public Clusters

#### Set Up Cluster Access
```bash
# Export kubeconfig
export KUBECONFIG=$PWD/auth/kubeconfig

# Verify cluster access
oc whoami
oc get nodes
oc get co  # Check cluster operators
```

#### Access Web Console
1. Open browser to: `https://console-openshift-console.apps.ocp-cluster.nedoshi.mobb.cloud`
2. Login with:
   - Username: `kubeadmin`
   - Password: (from installation output or `auth/kubeadmin-password`)

### For Private Clusters

#### Set Up Cluster Access via Bastion Host

```bash
# Copy kubeconfig to bastion host
scp -i bastion-key.pem auth/kubeconfig ec2-user@<bastion-ip>:~/kubeconfig

# SSH to bastion host
ssh -i bastion-key.pem ec2-user@<bastion-ip>

# On bastion host - install oc client
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Set kubeconfig
export KUBECONFIG=~/kubeconfig

# Verify cluster access
oc whoami
oc get nodes
oc get co
```

#### Access Private Web Console

**Option 1: SSH Tunnel**
```bash
# From your local machine, create SSH tunnel through bastion
ssh -i bastion-key.pem -L 8443:console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud:443 ec2-user@<bastion-ip>

# Access via: https://localhost:8443
```

**Option 2: SOCKS Proxy**
```bash
# Create SOCKS proxy through bastion
ssh -i bastion-key.pem -D 1080 ec2-user@<bastion-ip>

# Configure browser to use SOCKS proxy localhost:1080
# Then access: https://console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud
```

**Option 3: VPN Access**
If using VPN, directly access: `https://console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud`

### Verify All Components
```bash
# Check cluster status
oc get clusterversion

# Check cluster operators
oc get co

# Check nodes
oc get nodes -o wide

# Check pods in all namespaces
oc get pods --all-namespaces

# For private clusters, verify internal load balancers
oc get svc -n openshift-ingress
```

## Step 9: Network Troubleshooting Guide

### For Public Clusters

#### If DNS Issues Occur

##### Check Route53 Records
```bash
# Verify hosted zone
aws route53 list-hosted-zones --query 'HostedZones[?Name==`nedoshi.mobb.cloud.`]'

# Check all records in your hosted zone
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

##### Common DNS Problems and Solutions

1. **API Endpoint Not Resolving**
```bash
# Check if A record exists
dig api.ocp-cluster.nedoshi.mobb.cloud A

# If missing, the installation may have failed
# Check installer logs: .openshift_install.log
```

2. **Apps Wildcard Not Working**
```bash
# Test various app subdomains
nslookup oauth-openshift.apps.ocp-cluster.nedoshi.mobb.cloud
nslookup monitoring-openshift-monitoring.apps.ocp-cluster.nedoshi.mobb.cloud
```

### For Private Clusters

#### Private Cluster Specific Issues

1. **Cannot Access from Internet (Expected Behavior)**
```bash
# This should NOT work from public internet
curl -k https://api.ocp-private-cluster.nedoshi.mobb.cloud:6443/version
# Expected: Connection timeout or refused
```

2. **DNS Resolves to Private IPs (Expected)**
```bash
# Should return private IP addresses
nslookup api.ocp-private-cluster.nedoshi.mobb.cloud
# Expected: 10.x.x.x, 172.x.x.x, or 192.168.x.x
```

3. **Access Issues from Within VPC**
```bash
# From bastion host or VPN-connected machine
curl -k https://api.ocp-private-cluster.nedoshi.mobb.cloud:6443/version
# Should return OpenShift version information

# Check security groups allow traffic
aws ec2 describe-security-groups --filters "Name=group-name,Values=*ocp-private-cluster*"
```

4. **Bastion Host Connectivity Issues**
```bash
# Test bastion connectivity
ssh -i bastion-key.pem ec2-user@<bastion-ip>

# From bastion, test cluster connectivity
curl -k https://api.ocp-private-cluster.nedoshi.mobb.cloud:6443/version
telnet api.ocp-private-cluster.nedoshi.mobb.cloud 6443
```

#### TTL Issues
```bash
# If DNS changes aren't propagating, check TTL values
dig api.ocp-cluster.nedoshi.mobb.cloud | grep TTL
```

### Network Connectivity Tests

#### Public Cluster Tests
```bash
# Test API connectivity
curl -k https://api.ocp-cluster.nedoshi.mobb.cloud:6443/version

# Test if you can reach the console
curl -k https://console-openshift-console.apps.ocp-cluster.nedoshi.mobb.cloud
```

#### Private Cluster Tests (from within VPC)
```bash
# Test API connectivity (from bastion/VPN)
curl -k https://api.ocp-private-cluster.nedoshi.mobb.cloud:6443/version

# Test console accessibility
curl -k https://console-openshift-console.apps.ocp-private-cluster.nedoshi.mobb.cloud

# Test internal service mesh
oc get svc -n openshift-ingress-operator
```

## Step 10: Security Groups and Network Verification

### For Public Clusters

#### Check Security Groups
```bash
# List security groups created by OpenShift
aws ec2 describe-security-groups --filters "Name=group-name,Values=*ocp-cluster*"

# Verify required ports are open:
# - 6443 (API server)
# - 443 (HTTPS applications)
# - 80 (HTTP applications)
```

#### Verify VPC and Subnets
```bash
# Check VPC created for cluster
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*ocp-cluster*"

# Check subnets
aws ec2 describe-subnets --filters "Name=tag:Name,Values=*ocp-cluster*"
```

### For Private Clusters

#### Check Private Security Groups
```bash
# List security groups for private cluster
aws ec2 describe-security-groups --filters "Name=group-name,Values=*ocp-private-cluster*"

# Verify master security group allows:
# - 6443 from VPC CIDR (API server)
# - 22623 from VPC CIDR (machine config server)
# - 2379-2380 (etcd)

# Verify worker security group allows:
# - 443 from VPC CIDR (ingress)
# - 80 from VPC CIDR (ingress)
# - 10250-10259 (kubelet)
# - 30000-32767 (NodePort services)
```

#### Private Cluster Network Architecture
```bash
# Check private subnets (no internet gateway route)
aws ec2 describe-subnets --filters "Name=tag:Name,Values=*ocp-private-cluster*" \
  --query 'Subnets[?MapPublicIpOnLaunch==`false`]'

# Verify NAT Gateway for outbound traffic
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-xxxxxxxxx"

# Check route tables for private subnets
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"
```

#### Private Load Balancer Verification
```bash
# Verify internal load balancers
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Scheme==`internal` && contains(LoadBalancerName, `ocp-private-cluster`)]'

# Check target health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## Step 11: Creating Additional Users (Optional)

### Create HTPasswd Identity Provider
```bash
# Create htpasswd file
htpasswd -c -B -b users.htpasswd admin password123
htpasswd -B -b users.htpasswd developer devpass123

# Create secret
oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config

# Create OAuth configuration
cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF
```

## Cleanup (If Installation Fails)

### Destroy Failed Installation
```bash
# If installation fails, clean up resources
openshift-install destroy cluster --dir=. --log-level=info

# This removes all AWS resources created by the installer
```

### Manual Cleanup (If Needed)
```bash
# Check for remaining resources
aws ec2 describe-instances --filters "Name=tag:Name,Values=*ocp-cluster*"
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `ocp-cluster`)]'
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

## Important Notes

1. **Cost Management**: OpenShift on AWS incurs costs for EC2 instances, load balancers, and storage. Monitor your AWS billing.

2. **DNS Propagation**: DNS changes can take 5-15 minutes to propagate globally.

3. **Certificate Management**: OpenShift automatically manages certificates using Let's Encrypt.

4. **Backup**: Save your `install-config.yaml` and authentication files in a secure location.

5. **Updates**: Use `oc adm upgrade` to update your cluster to newer OpenShift versions.

## Support and Documentation

- OpenShift Documentation: https://docs.openshift.com/
- AWS Documentation: https://docs.aws.amazon.com/
- Community Support: https://community.openshift.com/

This completes your OpenShift installation on AWS with proper DNS configuration!
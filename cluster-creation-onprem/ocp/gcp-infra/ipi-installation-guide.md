# OpenShift IPI Installation on GCP Infrastructure

Complete guide for installing self-managed OpenShift Container Platform on Google Cloud Platform using the Installer Provisioned Infrastructure (IPI) method.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Prepare GCP Environment](#prepare-gcp-environment)
3. [Download Installation Tools](#download-installation-tools)
4. [Configure Installation](#configure-installation)
5. [Run Installation](#run-installation)
6. [Post-Installation](#post-installation)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### GCP Requirements
- Active GCP project with billing enabled
- Sufficient quotas:
  - CPUs: 28+ (3 control plane + workers)
  - In-use IP addresses: 10+
  - Persistent Disk SSD (GB): 900+
- gcloud CLI installed and configured
- Service account with required permissions

### Local Machine Requirements
- Linux, macOS, or WSL2
- 4 GB RAM minimum
- Internet connectivity

### Red Hat Requirements
- Red Hat account
- Valid OpenShift subscription or evaluation
- Pull secret from https://console.redhat.com/openshift/install/pull-secret

## Prepare GCP Environment

### 1. Install and Configure gcloud CLI

```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Initialize gcloud
gcloud init

# Set your project
export GCP_PROJECT_ID="your-project-id"
gcloud config set project $GCP_PROJECT_ID
```

### 2. Enable Required APIs

```bash
# Enable necessary GCP APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudapis.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable servicemanagement.googleapis.com
gcloud services enable serviceusage.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable storage-component.googleapis.com
```

### 3. Create Service Account

```bash
# Create service account
export SERVICE_ACCOUNT_NAME="openshift-installer"
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
  --display-name="OpenShift Installer"

export SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Grant required roles
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/iam.securityAdmin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/iam.serviceAccountKeyAdmin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/dns.admin"

# Create and download service account key
gcloud iam service-accounts keys create ~/osServiceAccount.json \
  --iam-account="${SERVICE_ACCOUNT_EMAIL}"
```

### 4. Set Up DNS

```bash
# Create Cloud DNS managed zone
export BASE_DOMAIN="example.com"
export CLUSTER_NAME="ocp"

gcloud dns managed-zones create ${CLUSTER_NAME}-zone \
  --dns-name="${CLUSTER_NAME}.${BASE_DOMAIN}." \
  --description="OpenShift cluster DNS zone"

# Note the name servers
gcloud dns managed-zones describe ${CLUSTER_NAME}-zone
```

Configure your domain registrar to use the GCP name servers shown above.

## Download Installation Tools

```bash
# Set OpenShift version
export OCP_VERSION="4.15.0"

# Download openshift-install
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz
sudo mv openshift-install /usr/local/bin/

# Download oc CLI
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Verify installation
openshift-install version
oc version
```

## Configure Installation

### 1. Create Installation Directory

```bash
mkdir ~/ocp-gcp-install
cd ~/ocp-gcp-install
```

### 2. Create install-config.yaml

```bash
# Generate SSH key if needed
ssh-keygen -t ed25519 -N '' -f ~/.ssh/ocp-gcp

# Download pull secret
# Save from https://console.redhat.com/openshift/install/pull-secret to ~/pull-secret.txt

# Create install-config.yaml
cat <<EOF > install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    gcp:
      type: n2-standard-4
      zones:
      - us-central1-a
      - us-central1-b
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    gcp:
      type: n2-standard-4
      zones:
      - us-central1-a
      - us-central1-b
      - us-central1-c
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  gcp:
    projectID: ${GCP_PROJECT_ID}
    region: us-central1
publish: External
pullSecret: '$(cat ~/pull-secret.txt)'
sshKey: '$(cat ~/.ssh/ocp-gcp.pub)'
EOF

# Backup the config
cp install-config.yaml install-config.yaml.backup
```

### 3. Review Configuration

```bash
cat install-config.yaml
```

## Run Installation

### 1. Create Cluster

```bash
# Start installation (takes 30-45 minutes)
openshift-install create cluster --dir ~/ocp-gcp-install --log-level=info
```

The installer will:
1. Validate configuration
2. Create GCP resources (VPC, instances, load balancers, DNS)
3. Bootstrap the cluster
4. Deploy control plane
5. Deploy workers
6. Finalize configuration

### 2. Monitor Installation

```bash
# In another terminal, watch progress
tail -f ~/ocp-gcp-install/.openshift_install.log
```

### 3. Installation Complete

When successful, you'll see:
```
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/user/ocp-gcp-install/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ocp.example.com
INFO Login to the console with user: "kubeadmin", and password: "XXXXX-XXXXX-XXXXX-XXXXX"
```

## Post-Installation

### 1. Access the Cluster

```bash
# Set kubeconfig
export KUBECONFIG=~/ocp-gcp-install/auth/kubeconfig

# Verify cluster
oc whoami
oc get nodes
oc get co  # cluster operators
```

### 2. Access Web Console

```bash
# Get console URL
oc whoami --show-console

# Get kubeadmin password
cat ~/ocp-gcp-install/auth/kubeadmin-password
```

### 3. Create Admin User

```bash
# Install htpasswd
sudo yum install httpd-tools -y

# Create htpasswd file
htpasswd -c -B -b users.htpasswd admin YourSecurePassword

# Create secret
oc create secret generic htpass-secret \
  --from-file=htpasswd=users.htpasswd \
  -n openshift-config

# Create OAuth provider
cat <<EOF | oc apply -f -
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

# Grant cluster-admin role
oc adm policy add-cluster-role-to-user cluster-admin admin
```

### 4. Delete kubeadmin User (After Creating Admin)

```bash
# After confirming admin user works
oc delete secrets kubeadmin -n kube-system
```

## Troubleshooting

### Installation Fails

```bash
# Check installation log
cat ~/ocp-gcp-install/.openshift_install.log

# Check GCP quotas
gcloud compute project-info describe --project=$GCP_PROJECT_ID

# Destroy and retry
openshift-install destroy cluster --dir ~/ocp-gcp-install
# Fix issues, then retry installation
```

### DNS Issues

```bash
# Verify DNS zone
gcloud dns managed-zones list

# Check DNS records
gcloud dns record-sets list --zone=${CLUSTER_NAME}-zone

# Test DNS resolution
nslookup api.${CLUSTER_NAME}.${BASE_DOMAIN}
```

### Access Issues

```bash
# Check load balancers
gcloud compute forwarding-rules list

# Check firewall rules
gcloud compute firewall-rules list

# Verify kubeconfig
echo $KUBECONFIG
cat $KUBECONFIG
```

### Cluster Not Healthy

```bash
# Check cluster operators
oc get co

# Check nodes
oc get nodes

# Check machine sets
oc get machinesets -n openshift-machine-api

# Check events
oc get events -A
```

## Cleanup

### Destroy Cluster

```bash
# Delete the cluster (removes all GCP resources)
openshift-install destroy cluster --dir ~/ocp-gcp-install

# Manually delete DNS zone if needed
gcloud dns managed-zones delete ${CLUSTER_NAME}-zone

# Delete service account
gcloud iam service-accounts delete ${SERVICE_ACCOUNT_EMAIL}

# Remove service account key
rm ~/osServiceAccount.json
```

## Next Steps

- Set up [monitoring](../../../operations/monitoring/)
- Configure [backup and restore](../../../operations/backup-restore/)
- Review [troubleshooting guides](../../../operations/troubleshooting/)
- Configure [networking strategies](../../../docs/architecture/networking/)

## References

- [Official OpenShift IPI on GCP Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_gcp/installing-gcp-default.html)
- [GCP OpenShift Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_gcp/installing-gcp-account.html)
- [OpenShift Architecture](https://docs.openshift.com/container-platform/latest/architecture/architecture.html)

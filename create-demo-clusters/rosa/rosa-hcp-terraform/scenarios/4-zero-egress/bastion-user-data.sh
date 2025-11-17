#!/bin/bash
# Bastion host user data script

set -e

# Update system
dnf update -y

# Install required tools
dnf install -y \
    git \
    jq \
    wget \
    unzip \
    python3-pip

# Install AWS CLI v2
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install oc CLI
cd /tmp
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | tar xvz
mv oc kubectl /usr/local/bin/
rm -f README.md

# Install ROSA CLI
cd /tmp
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar xvz
chmod +x rosa
mv rosa /usr/local/bin/

# Configure motd
cat > /etc/motd << 'EOF'
================================================================================
ROSA HCP Zero Egress Cluster - Bastion Host
================================================================================

This bastion provides access to the private ROSA cluster with zero egress.

Available tools:
- oc (OpenShift CLI)
- kubectl
- rosa (ROSA CLI)
- aws (AWS CLI)

Cluster: ${cluster_name}
Region: ${aws_region}

To access the cluster:
  1. Get admin password: terraform output -raw admin_password
  2. Login: oc login <api-url> -u kubeadmin -p <password>

For ECR access:
  aws ecr get-login-password --region ${aws_region} | \\
    docker login --username AWS --password-stdin <ecr-url>

================================================================================
EOF

# Create helper scripts
cat > /usr/local/bin/cluster-login << 'EOFSCRIPT'
#!/bin/bash
# Helper script to login to cluster

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: cluster-login <api-url> <password>"
    exit 1
fi

oc login $1 -u kubeadmin -p $2
EOFSCRIPT

chmod +x /usr/local/bin/cluster-login

echo "Bastion host setup complete" > /var/log/user-data-complete.log
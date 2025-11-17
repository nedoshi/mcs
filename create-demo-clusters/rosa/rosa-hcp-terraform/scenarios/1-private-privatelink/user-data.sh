#!/bin/bash
set -e -x

# Update system
sudo dnf update -y

# Install useful packages
sudo dnf install -y wget curl python3 python3-pip net-tools bind-utils jq

# Install OpenShift CLI (oc) and kubectl
wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -O /tmp/oc.tar.gz
mkdir -p /tmp/oc
tar -xzf /tmp/oc.tar.gz -C /tmp/oc
sudo install /tmp/oc/oc /usr/local/bin/oc
sudo install /tmp/oc/kubectl /usr/local/bin/kubectl

# Cleanup
rm -rf /tmp/oc /tmp/oc.tar.gz

# Log cluster name for reference
echo "Cluster name: ${cluster_name}" | sudo tee /etc/cluster-info


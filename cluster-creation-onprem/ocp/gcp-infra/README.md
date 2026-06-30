# OpenShift on GCP Infrastructure (Self-Managed)

This directory contains guides for installing self-managed OpenShift Container Platform on Google Cloud Platform infrastructure.

## Important Distinction

This is for **self-managed OpenShift on GCP**, not OSD on GCP (OpenShift Dedicated on GCP).

- **Use these guides** if you want full control and are managing the cluster yourself
- **Use OSD on GCP** (see [cluster-creation-cloud/gcp/](../../../cluster-creation-cloud/gcp/)) if you want a fully managed service

## Installation Methods

### [IPI (Installer Provisioned Infrastructure)](ipi-installation-guide.md)
The OpenShift installer automatically provisions:
- VPC network, subnets, firewall rules
- Compute Engine instances for control plane and workers
- Load balancers (TCP/HTTP(S))
- Cloud DNS records
- Service accounts and IAM bindings

**When to use IPI:**
- You want quick, automated deployment
- You're comfortable with OpenShift managing GCP resources
- You don't need highly customized networking
- You have GCP credentials with sufficient permissions

### [UPI (User Provisioned Infrastructure)](upi-installation-guide.md)
You manually provision all GCP resources before installation.

**When to use UPI:**
- You need complete control over GCP infrastructure
- You have strict networking/security requirements
- You're integrating with existing VPCs/networks
- You need air-gapped or disconnected installations
- Your security policies require manual resource provisioning

## Prerequisites

### GCP Account Requirements
- Active GCP project
- gcloud CLI configured (`gcloud init`)
- Sufficient compute quotas
- Cloud DNS zone (or ability to create one)
- Billing enabled on project

### Required IAM Permissions
Service account with:
- Compute Admin
- Security Admin
- Service Account Admin
- DNS Administrator

### Network Requirements
- Internet connectivity (or mirror registry for disconnected)
- DNS resolution
- Network bandwidth for image pulls

## Quick Start

### IPI Installation
```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# Download the installer
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz

# Follow the IPI guide
See: ipi-installation-guide.md
```

### UPI Installation
```bash
# Provision GCP infrastructure manually
# Follow the UPI guide
See: upi-installation-guide.md
```

## Cost Considerations

Self-managed OpenShift on GCP incurs:
- Compute Engine costs (control plane + workers)
- Persistent disks
- Load balancers
- Network egress
- Cloud DNS zone

Estimate: ~$350-550/month for a minimal 3-node cluster

## Next Steps

1. Review [IPI Installation Guide](ipi-installation-guide.md) or [UPI Installation Guide](upi-installation-guide.md)
2. Prepare your GCP project and credentials
3. Follow the step-by-step installation process
4. Configure post-installation settings
5. Set up monitoring and backups (see [operations/](../../../operations/))

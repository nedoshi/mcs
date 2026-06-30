# OpenShift on Azure Infrastructure (Self-Managed)

This directory contains guides for installing self-managed OpenShift Container Platform on Azure infrastructure.

## Important Distinction

This is for **self-managed OpenShift on Azure**, not ARO (Azure Red Hat OpenShift).

- **Use these guides** if you want full control and are managing the cluster yourself
- **Use ARO** (see [cluster-creation-cloud/azure/](../../../cluster-creation-cloud/azure/)) if you want a fully managed service

## Installation Methods

### [IPI (Installer Provisioned Infrastructure)](ipi-installation-guide.md)
The OpenShift installer automatically provisions:
- Virtual Network (VNet), subnets, NSGs
- Virtual Machines for control plane and workers
- Azure Load Balancers
- Azure DNS records
- Managed identities and service principals

**When to use IPI:**
- You want quick, automated deployment
- You're comfortable with OpenShift managing Azure resources
- You don't need highly customized networking
- You have Azure credentials with sufficient permissions

### [UPI (User Provisioned Infrastructure)](upi-installation-guide.md)
You manually provision all Azure resources before installation.

**When to use UPI:**
- You need complete control over Azure infrastructure
- You have strict networking/security requirements
- You're integrating with existing VNets/networks
- You need air-gapped or disconnected installations
- Your security policies require manual resource provisioning

## Prerequisites

### Azure Account Requirements
- Active Azure subscription
- Azure CLI configured (`az login`)
- Sufficient VM quotas (especially for D-series VMs)
- Resource group permissions
- Azure DNS zone (or ability to create one)

### Required Permissions
Service Principal with:
- Contributor role on subscription
- User Access Administrator (for managed identities)

### Network Requirements
- Internet connectivity (or mirror registry for disconnected)
- DNS resolution
- Network bandwidth for image pulls

## Quick Start

### IPI Installation
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Download the installer
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz

# Follow the IPI guide
See: ipi-installation-guide.md
```

### UPI Installation
```bash
# Provision Azure infrastructure manually
# Follow the UPI guide
See: upi-installation-guide.md
```

## Cost Considerations

Self-managed OpenShift on Azure incurs:
- VM costs (control plane + workers)
- Managed disks
- Load balancers
- Network bandwidth
- Azure DNS zone

Estimate: ~$400-600/month for a minimal 3-node cluster

## Next Steps

1. Review [IPI Installation Guide](ipi-installation-guide.md) or [UPI Installation Guide](upi-installation-guide.md)
2. Prepare your Azure subscription and credentials
3. Follow the step-by-step installation process
4. Configure post-installation settings
5. Set up monitoring and backups (see [operations/](../../../operations/))

# OpenShift on AWS Infrastructure (Self-Managed)

This directory contains guides for installing self-managed OpenShift Container Platform on AWS infrastructure.

## Important Distinction

This is for **self-managed OpenShift on AWS**, not ROSA (Red Hat OpenShift Service on AWS).

- **Use these guides** if you want full control and are managing the cluster yourself
- **Use ROSA** (see [cluster-creation-cloud/aws/](../../../cluster-creation-cloud/aws/)) if you want a fully managed service

## Installation Methods

### [IPI (Installer Provisioned Infrastructure)](ipi-installation-guide.md)
The OpenShift installer automatically provisions:
- VPC, subnets, security groups
- EC2 instances for control plane and workers
- Load balancers (NLB/CLB)
- Route53 DNS records
- IAM roles and policies

**When to use IPI:**
- You want quick, automated deployment
- You're comfortable with OpenShift managing AWS resources
- You don't need highly customized networking
- You have AWS API credentials with sufficient permissions

### [UPI (User Provisioned Infrastructure)](upi-installation-guide.md)
You manually provision all AWS resources before installation.

Terraform automation: [`terraform-upi/`](terraform-upi/)

**When to use UPI:**
- You need complete control over AWS infrastructure
- You have strict networking/security requirements
- You're integrating with existing VPCs/networks
- You need air-gapped or disconnected installations
- Your security policies require manual resource provisioning

## Prerequisites

### AWS Account Requirements
- Active AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Sufficient EC2 instance quotas
- Available Elastic IPs
- Route53 hosted zone (or ability to create one)

### Required IAM Permissions
For IPI, see: https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-account.html

### Network Requirements
- Internet connectivity (or mirror registry for disconnected)
- DNS resolution
- Network bandwidth for image pulls

## Quick Start

### IPI Installation
```bash
# Download the installer
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz

# Follow the IPI guide
See: ipi-installation-guide.md
```

### UPI Installation
```bash
# Download installation materials
# Provision infrastructure manually
# Follow the UPI guide
See: upi-installation-guide.md
```

## Cost Considerations

Self-managed OpenShift on AWS incurs:
- EC2 costs (control plane + workers)
- EBS volumes
- Load balancers (NLB/CLB)
- Data transfer
- Route53 hosted zone

Estimate: ~$300-500/month for a minimal 3-node cluster

## Next Steps

1. Review [IPI Installation Guide](ipi-installation-guide.md) or [UPI Installation Guide](upi-installation-guide.md)
2. Prepare your AWS account and credentials
3. Follow the step-by-step installation process
4. Configure post-installation settings
5. Set up monitoring and backups (see [operations/](../../../operations/))

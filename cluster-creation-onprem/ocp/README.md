# OpenShift Container Platform (OCP) On-Premises Installation Guides

This directory contains comprehensive guides for installing self-managed OpenShift Container Platform on various infrastructure providers using on-premises deployment models.

## Overview

OpenShift can be deployed on-premises using different infrastructure platforms. These guides focus on:

- **IPI (Installer Provisioned Infrastructure)**: OpenShift installer automates infrastructure provisioning
- **UPI (User Provisioned Infrastructure)**: You manually provision infrastructure before installation

## Installation Options by Infrastructure

### AWS Infrastructure
On-premises OpenShift running on AWS infrastructure (not managed ROSA)

- [IPI Installation Guide](aws-infra/ipi-installation-guide.md) - Automated infrastructure provisioning
- [UPI Installation Guide](aws-infra/upi-installation-guide.md) - Manual infrastructure setup

### Azure Infrastructure  
On-premises OpenShift running on Azure infrastructure (not managed ARO)

- [IPI Installation Guide](azure-infra/ipi-installation-guide.md) - Automated infrastructure provisioning
- [UPI Installation Guide](azure-infra/upi-installation-guide.md) - Manual infrastructure setup

### GCP Infrastructure
On-premises OpenShift running on GCP infrastructure

- [IPI Installation Guide](gcp-infra/ipi-installation-guide.md) - Automated infrastructure provisioning
- [UPI Installation Guide](gcp-infra/upi-installation-guide.md) - Manual infrastructure setup

### VMware vSphere
On-premises OpenShift on VMware vSphere

- [IPI Installation Guide](vsphere/ipi-installation-guide.md) - Automated VM provisioning
- [UPI Installation Guide](vsphere/upi-installation-guide.md) - Manual VM setup

### Bare Metal
OpenShift on physical servers

- [UPI Installation Guide](bare-metal/upi-installation-guide.md) - Physical server deployment

## Choosing Between IPI and UPI

### Use IPI When:
- You want automation and simplicity
- Infrastructure provider has supported automation APIs
- You're comfortable with OpenShift managing infrastructure lifecycle
- You want easier upgrades and cluster management
- You have API credentials with sufficient permissions

### Use UPI When:
- You need fine-grained control over infrastructure
- Network/security policies require manual provisioning
- IPI doesn't support your specific configuration
- You're using custom networking or storage
- You need air-gapped or disconnected installations

## Prerequisites (All Platforms)

### Required Tools
- OpenShift installer (version matching your target OCP version)
- OpenShift CLI (`oc`)
- Platform-specific CLI tools (aws-cli, az-cli, gcloud, etc.)
- Pull secret from Red Hat (https://console.redhat.com/openshift/install/pull-secret)
- SSH key pair for cluster access

### Common Requirements
- Valid Red Hat subscription or evaluation
- DNS domain you can manage
- Sufficient resource quotas
- Network connectivity requirements met
- Load balancer configuration (varies by platform)

## Related Documentation

### Managed OpenShift Services
For fully managed OpenShift, see:
- **AWS**: [cluster-creation-cloud/aws/](../../cluster-creation-cloud/aws/) - ROSA (Red Hat OpenShift Service on AWS)
- **Azure**: [cluster-creation-cloud/azure/](../../cluster-creation-cloud/azure/) - ARO (Azure Red Hat OpenShift)
- **GCP**: [cluster-creation-cloud/gcp/](../../cluster-creation-cloud/gcp/) - OSD (OpenShift Dedicated)

### Operations
- **Monitoring**: [operations/monitoring/](../../operations/monitoring/)
- **Backup & Restore**: [operations/backup-restore/](../../operations/backup-restore/)
- **Troubleshooting**: [operations/troubleshooting/](../../operations/troubleshooting/)

### Architecture
- **Networking**: [docs/architecture/networking/](../../docs/architecture/networking/)

## Support and Resources

- [Official OpenShift Documentation](https://docs.openshift.com/)
- [Red Hat Customer Portal](https://access.redhat.com/)
- [OpenShift Commons](https://commons.openshift.org/)

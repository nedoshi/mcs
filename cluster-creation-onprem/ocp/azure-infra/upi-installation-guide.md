# OpenShift UPI Installation on Azure Infrastructure

Guide for installing self-managed OpenShift Container Platform on Azure using the User Provisioned Infrastructure (UPI) method.

> **Note**: UPI installation requires you to manually provision all Azure infrastructure before running the OpenShift installer.

## Coming Soon

This guide is under development. For UPI installation on Azure, refer to:

- [Official OpenShift UPI on Azure Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_azure/installing-azure-user-infra.html)
- [Azure ARM Templates](https://github.com/openshift/installer/tree/master/upi/azure)

## When to Use UPI

Use UPI installation when:
- You need complete control over Azure infrastructure
- You have strict networking/security requirements
- You're integrating with existing VNets/networks
- You need air-gapped or disconnected installations
- IPI doesn't support your specific configuration

## High-Level Steps

1. Provision VNet, subnets, and network security groups
2. Create managed identities and service principals
3. Set up Azure load balancers
4. Configure Azure DNS
5. Create VMs for bootstrap, control plane, and workers
6. Generate ignition configs
7. Bootstrap the cluster
8. Complete installation

## Quick Start (Until Full Guide Available)

For now, consider:
- Using [IPI installation](ipi-installation-guide.md) if possible
- Following the official Red Hat UPI documentation
- Reviewing ARM template/Terraform examples

Check back for the complete UPI guide coming soon.

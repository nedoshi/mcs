# OpenShift UPI Installation on GCP Infrastructure

Guide for installing self-managed OpenShift Container Platform on Google Cloud Platform using the User Provisioned Infrastructure (UPI) method.

> **Note**: UPI installation requires you to manually provision all GCP infrastructure before running the OpenShift installer.

## Coming Soon

This guide is under development. For UPI installation on GCP, refer to:

- [Official OpenShift UPI on GCP Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_gcp/installing-gcp-user-infra.html)
- [GCP Deployment Manager Templates](https://github.com/openshift/installer/tree/master/upi/gcp)

## When to Use UPI

Use UPI installation when:
- You need complete control over GCP infrastructure
- You have strict networking/security requirements
- You're integrating with existing VPCs/networks
- You need air-gapped or disconnected installations
- IPI doesn't support your specific configuration

## High-Level Steps

1. Provision VPC, subnets, and firewall rules
2. Create service accounts and IAM bindings
3. Set up load balancers
4. Configure Cloud DNS
5. Create compute instances for bootstrap, control plane, and workers
6. Generate ignition configs
7. Bootstrap the cluster
8. Complete installation

## Quick Start (Until Full Guide Available)

For now, consider:
- Using [IPI installation](ipi-installation-guide.md) if possible
- Following the official Red Hat UPI documentation
- Reviewing Terraform/Deployment Manager examples

Check back for the complete UPI guide coming soon.

# OpenShift Home Lab Setup

Complete guide and infrastructure-as-code for building an OpenShift home lab environment.

## Overview

This directory contains everything needed to build a production-like OpenShift environment in your home lab, following industry best practices and inspired by successful community implementations.

## Architecture Options

### Option 1: Single Node OpenShift (SNO) - Recommended for Beginners
**Best for**: Learning, testing, minimal hardware
- **Hardware**: 8 vCPU (4-core with hyperthreading), 32GB RAM, 120GB storage
- **Cost**: ~$280 (refurbished ThinkCentre M910 Tiny or Intel NUC)
- **Setup Time**: 2-3 hours
- **Use Cases**: Development, learning, CI/CD testing

### Option 2: Compact Cluster (3 Nodes)
**Best for**: High availability testing, realistic production simulation
- **Hardware**: 3 nodes with 8 vCPU each, 32GB RAM each
- **Cost**: ~$900-1200
- **Setup Time**: 4-6 hours
- **Use Cases**: HA testing, multi-node workloads, production simulation

### Option 3: Full Cluster with Separate Workers
**Best for**: Advanced testing, performance benchmarking
- **Hardware**: 3 control plane + 2+ workers
- **Cost**: $1500+
- **Setup Time**: 6-8 hours
- **Use Cases**: Capacity planning, performance testing, full production simulation

## Directory Structure

```
homelab/
├── README.md                          # This file
├── docs/                              # Documentation
│   ├── hardware-recommendations.md    # Hardware buying guide
│   ├── network-setup.md               # Network architecture
│   ├── installation-walkthrough.md    # Step-by-step guide
│   └── troubleshooting.md             # Common issues
├── infrastructure/                    # Infrastructure as Code
│   ├── kickstart/                     # OS installation configs
│   ├── terraform/                     # Infrastructure provisioning
│   └── pki/                           # Certificate management
├── ansible/                           # Ansible playbooks
│   ├── bootstrap/                     # Initial host setup
│   ├── openshift/                     # OpenShift deployment
│   └── services/                      # Additional services
├── network/                           # Network configuration
│   ├── dns/                           # DNS setup (dnsmasq, Pi-hole)
│   ├── dhcp/                          # DHCP configuration
│   └── firewall/                      # Firewall rules
└── services/                          # Additional services
    ├── auth/                          # Keycloak SSO
    ├── monitoring/                    # Prometheus, Grafana
    ├── registry/                      # Container registry
    └── storage/                       # NFS, Ceph, etc.
```

## Quick Start

### Prerequisites

1. **Hardware**: One of the architecture options above
2. **Network**: Home router with admin access
3. **Software**:
   - Linux laptop/workstation for setup
   - Red Hat account (free): https://console.redhat.com
   - Pull secret: https://console.redhat.com/openshift/install/pull-secret

### Single Node OpenShift (Fastest Path)

```bash
# 1. Download this repository
git clone <repo-url>
cd homelab

# 2. Follow the installation walkthrough
cat docs/installation-walkthrough.md

# 3. Start with SNO installation
# See: docs/sno-installation.md
```

## Best Practices

### Infrastructure as Code
All configuration should be version-controlled and repeatable:
- Use Ansible for configuration management
- Use Terraform/Kickstart for infrastructure provisioning
- Store secrets in Ansible Vault or external secret managers
- Document everything in Git

### Network Architecture
```
Internet
  │
  ├─ Home Router (192.168.1.1)
  │   └─ DHCP Reservations for lab hosts
  │
  ├─ DNS/DHCP Server (192.168.1.10)
  │   ├─ Pi-hole for recursive DNS + ad blocking
  │   └─ Dnsmasq for DHCP/TFTP (PXE boot)
  │
  ├─ Bastion/Jump Host (192.168.1.20)
  │   └─ Ansible control node
  │
  └─ OpenShift Nodes
      ├─ SNO: 192.168.1.100 (all-in-one)
      OR
      ├─ Control Plane 1: 192.168.1.101
      ├─ Control Plane 2: 192.168.1.102
      ├─ Control Plane 3: 192.168.1.103
      ├─ Worker 1: 192.168.1.111
      └─ Worker 2: 192.168.1.112
```

### Essential Services

1. **DNS** (Critical)
   - Internal DNS for cluster communication
   - External DNS for applications
   - Consider Pi-hole for ad-blocking + recursive DNS

2. **Load Balancer** (For multi-node)
   - HAProxy or Nginx
   - Required for API and ingress traffic
   - Can run as container or VM

3. **Storage**
   - NFS for simple persistent volumes
   - Local storage for performance
   - OpenShift Data Foundation (ODF) for advanced features

4. **Monitoring**
   - Built-in Prometheus + Grafana
   - External Grafana for long-term metrics
   - Alertmanager for notifications

5. **Authentication**
   - Keycloak for SSO
   - LDAP/Active Directory integration
   - OAuth providers (GitHub, Google)

### Security Best Practices

1. **Network Segmentation**
   - Separate VLAN for lab (optional but recommended)
   - Firewall rules to isolate from home network
   - VPN access for remote management

2. **Certificate Management**
   - Use Let's Encrypt for public certs
   - Internal PKI with Step-CA or similar
   - Automate cert renewal with Ansible

3. **Access Control**
   - SSH key-based authentication only
   - Regular credential rotation
   - Multi-factor authentication where possible

### GitOps Workflow

```bash
# Make infrastructure changes
vim ansible/bootstrap/vars.yml

# Commit to Git
git add .
git commit -m "Update DNS configuration"

# Push triggers automation
git push

# Ansible Tower/AAP watches repo and deploys changes
```

## Hardware Recommendations

### Budget Option (~$300)
- **Mini PC**: Refurbished Lenovo ThinkCentre M910 Tiny
- **CPU**: Intel i7-7700T (4 cores, 8 threads)
- **RAM**: 32GB DDR4
- **Storage**: 256GB NVMe SSD
- **Use**: Single Node OpenShift

### Mid-Range (~$600-800)
- **Mini PC**: Intel NUC 10i7FNK or equivalent
- **CPU**: Intel i7-10710U (6 cores, 12 threads)
- **RAM**: 64GB DDR4
- **Storage**: 512GB NVMe SSD
- **Use**: SNO + additional VMs for services

### Advanced (~$1500+)
- **Server**: Dell PowerEdge R720xd or HP DL380 Gen9
- **CPU**: Dual Xeon (12+ cores total)
- **RAM**: 128GB+ ECC RAM
- **Storage**: Multiple SSDs + RAID
- **Use**: Full multi-node cluster

## Installation Methods

### Method 1: Assisted Installer (Easiest)
1. Go to https://console.redhat.com/openshift/create
2. Select "Datacenter" → "Bare Metal" → "Interactive"
3. Download discovery ISO
4. Boot nodes from ISO
5. Complete installation via web UI

### Method 2: IPI (Automated)
- Not available for bare metal (use for cloud providers)
- See: [cluster-creation-onprem/ocp/](../cluster-creation-onprem/ocp/)

### Method 3: UPI (Full Control)
- Manual infrastructure provisioning
- Most flexible but most complex
- Recommended for advanced users

## Common Services to Add

### After Initial Install

1. **OpenShift Virtualization**
   - Run VMs alongside containers
   - Requires 14+ vCPU for SNO

2. **OpenShift Data Foundation**
   - Software-defined storage
   - Requires 3+ nodes for HA

3. **OpenShift GitOps (ArgoCD)**
   - Declarative application deployment
   - GitOps workflow automation

4. **OpenShift Pipelines (Tekton)**
   - CI/CD pipelines
   - Cloud-native builds

5. **OpenShift Service Mesh**
   - Istio-based service mesh
   - Advanced traffic management

### External Services

1. **Identity Provider**
   - Keycloak (self-hosted)
   - GitHub OAuth
   - Google OAuth

2. **Container Registry**
   - Quay (Red Hat's registry)
   - Harbor
   - Docker Registry v2

3. **Backup Solution**
   - Velero/OADP
   - Restic for persistent volumes

## Inspiration & References

This setup is inspired by:
- [Ken Moini's Homelab](https://github.com/kenmoini/homelab) - Comprehensive infrastructure-as-code example
- [OKD4 UPI Lab Setup](https://cgruver.github.io/okd4-upi-lab-setup/LabIntro.html) - Detailed UPI walkthrough
- [Red Hat Single Node OpenShift Guide](https://community.veeam.com/kubernetes-korner-90/how-to-create-a-red-hat-single-node-openshift-cluster-for-a-home-lab-beginners-guide-7540)
- [OpenShift Virtualization Lab Build](https://www.stb.id.au/blog/openshift-virt-lab)
- [Upstream Without A Paddle - Home Lab Series](https://upstreamwithoutapaddle.com/openshift/home%20lab/kubernetes/2021/08/01/Blog-Introduction.html)

## Community Resources

- [OpenShift Commons](https://commons.openshift.org/) - Community and events
- [Red Hat Developer](https://developers.redhat.com/) - Free developer subscriptions
- [r/openshift](https://reddit.com/r/openshift) - Reddit community
- [Kubernetes Slack #openshift](https://kubernetes.slack.com) - Real-time help

## Next Steps

1. Review [Hardware Recommendations](docs/hardware-recommendations.md)
2. Plan your [Network Setup](docs/network-setup.md)
3. Follow the [Installation Walkthrough](docs/installation-walkthrough.md)
4. Set up [Monitoring](../operations/monitoring/)
5. Configure [Backup & Restore](../operations/backup-restore/)

## Cost Breakdown

### One-Time Costs
- Hardware: $300-1500+
- Networking gear (if needed): $50-200
- UPS (recommended): $100-300

### Ongoing Costs
- Electricity: ~$10-30/month (depending on hardware)
- Internet bandwidth: Included in home internet
- Red Hat subscription: Free for developers (60-day eval renewals)

### Free Red Hat Subscriptions
- **Developer Subscription**: https://developers.redhat.com/register
  - 16 free RHEL subscriptions
  - Access to OpenShift, Ansible, and more
  - Self-supported (community only)

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues and solutions.

## Contributing

This is a living repository. Contributions welcome:
1. Fork the repo
2. Create a feature branch
3. Submit a pull request

## Sources

- [How I created a Red Hat OpenShift cluster on tiny hardware](https://www.redhat.com/en/blog/low-cost-openshift-cluster)
- [Building an OpenShift - OKD 4.X Lab, Soup to Nuts](https://cgruver.github.io/okd4-upi-lab-setup/LabIntro.html)
- [How to Create a Red Hat Single Node OpenShift Cluster for a Home Lab](https://community.veeam.com/kubernetes-korner-90/how-to-create-a-red-hat-single-node-openshift-cluster-for-a-home-lab-beginners-guide-7540)
- [OpenShift Virtualization Lab Build](https://www.stb.id.au/blog/openshift-virt-lab)
- [Let's build an OpenShift Home Lab! - Upstream](https://upstreamwithoutapaddle.com/openshift/home%20lab/kubernetes/2021/08/01/Blog-Introduction.html)
- [Ken Moini's Homelab Repository](https://github.com/kenmoini/homelab)

# AKS to ARO Migration Guide

## Overview

This repository provides a comprehensive, production-ready migration guide for transitioning containerized applications from **Azure Kubernetes Service (AKS)** to **Azure Red Hat OpenShift (ARO)**. This guide includes architecture definitions, pre-migration checklists, detailed runbooks, and automation scripts to ensure a successful migration.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Prerequisites](#prerequisites)
- [Migration Phases](#migration-phases)
- [Support and Contribution](#support-and-contribution)

## Architecture Overview

### Sample Application Architecture (AKS)

This migration guide is based on a representative three-tier application running on AKS:

```
┌─────────────────────────────────────────────────────────────┐
│                     Azure Cloud                              │
│                                                               │
│  ┌────────────────────────────────────────────────────┐     │
│  │              AKS Cluster                           │     │
│  │                                                     │     │
│  │  ┌──────────────┐      ┌──────────────┐          │     │
│  │  │   Ingress    │──────│  Frontend    │          │     │
│  │  │  Controller  │      │   Service    │          │     │
│  │  └──────────────┘      └──────┬───────┘          │     │
│  │                               │                   │     │
│  │                        ┌──────▼───────┐          │     │
│  │                        │   Backend    │          │     │
│  │                        │   Service    │──┐       │     │
│  │                        └──────────────┘  │       │     │
│  └────────────────────────────────────┼─────┼───────┘     │
│                                        │     │             │
│  ┌────────────────┐   ┌───────────────▼─────▼───┐         │
│  │  Azure Key     │   │  Azure Database for     │         │
│  │    Vault       │   │     PostgreSQL          │         │
│  │  (Secrets)     │   │  (Managed Database)     │         │
│  └────────────────┘   └─────────────────────────┘         │
│                                                             │
│  ┌────────────────┐   ┌─────────────────────────┐         │
│  │ Azure Monitor  │   │  Azure Container        │         │
│  │ (Observability)│   │  Registry (ACR)         │         │
│  └────────────────┘   └─────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- **Frontend**: React/Angular application served via NGINX
- **Backend**: REST API (Node.js/Python/Java)
- **Database**: Azure Database for PostgreSQL (Flexible Server)
- **Secrets Management**: Azure Key Vault for connection strings, API keys
- **Container Registry**: Azure Container Registry (ACR)
- **Networking**: Azure VNET with NSGs, Application Gateway/NGINX Ingress
- **Observability**: Azure Monitor, Log Analytics, Application Insights

### Target Architecture (ARO)

After migration, the application will run on ARO with OpenShift-native components:

```
┌─────────────────────────────────────────────────────────────┐
│                     Azure Cloud                              │
│                                                               │
│  ┌────────────────────────────────────────────────────┐     │
│  │              ARO Cluster (OpenShift 4.x)           │     │
│  │                                                     │     │
│  │  ┌──────────────┐      ┌──────────────┐          │     │
│  │  │  OpenShift   │──────│  Frontend    │          │     │
│  │  │    Route     │      │     Pod      │          │     │
│  │  └──────────────┘      └──────┬───────┘          │     │
│  │                               │                   │     │
│  │                        ┌──────▼───────┐          │     │
│  │                        │   Backend    │          │     │
│  │                        │     Pod      │──┐       │     │
│  │                        └──────────────┘  │       │     │
│  └────────────────────────────────────┼─────┼───────┘     │
│                                        │     │             │
│  ┌────────────────┐   ┌───────────────▼─────▼───┐         │
│  │  Azure Key     │   │  Azure Database for     │         │
│  │  Vault CSI     │   │     PostgreSQL          │         │
│  │  (Secrets)     │   │  (Same Instance)        │         │
│  └────────────────┘   └─────────────────────────┘         │
│                                                             │
│  ┌────────────────┐   ┌─────────────────────────┐         │
│  │ Prometheus +   │   │  Azure Container        │         │
│  │ Grafana (OCP)  │   │  Registry (ACR)         │         │
│  └────────────────┘   └─────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

**Key Differences:**
- **Ingress → Routes**: OpenShift Routes replace Kubernetes Ingress
- **Security Context Constraints (SCCs)**: Stricter pod security policies
- **Integrated Monitoring**: Built-in Prometheus, Grafana, and cluster logging
- **Service Mesh**: Option to use OpenShift Service Mesh (Istio-based)
- **Developer Tools**: Integrated CI/CD with OpenShift Pipelines (Tekton)

## Repository Structure

```
aks-to-aro-migration/
├── README.md                          # This file
├── docs/
│   ├── 01-PRE-MIGRATION-CHECKLIST.md # Prerequisites and validation
│   ├── 02-MIGRATION-RUNBOOK.md       # Step-by-step execution guide
│   ├── 03-TROUBLESHOOTING.md         # Common issues and solutions
│   ├── 04-ROLLBACK-PLAN.md           # Rollback procedures
│   └── 05-POST-MIGRATION.md          # Validation and optimization
├── manifests/
│   ├── aks/                           # Original AKS manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── configmap.yaml
│   └── aro/                           # Converted ARO manifests
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       ├── configmap.yaml
│       └── scc.yaml
├── scripts/
│   ├── 01-export-aks-resources.sh    # Export configurations from AKS
│   ├── 02-convert-manifests.sh       # Convert Ingress to Routes
│   ├── 03-deploy-to-aro.sh           # Deploy to ARO cluster
│   ├── 04-validate-deployment.sh     # Post-deployment validation
│   └── helpers/
│       ├── database-connectivity.sh  # Test DB connections
│       ├── acr-integration.sh        # Configure ACR pull secrets
│       └── dns-update.sh             # Update DNS records
└── examples/
    ├── sample-app/                    # Complete example application
    │   ├── frontend/
    │   ├── backend/
    │   └── database/
    └── terraform/                     # IaC for ARO provisioning
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Quick Start

### For Immediate Migration

```bash
# 1. Clone this repository
git clone <repository-url>
cd aks-to-aro-migration

# 2. Review the pre-migration checklist
cat docs/01-PRE-MIGRATION-CHECKLIST.md

# 3. Set environment variables
export AKS_CLUSTER_NAME="my-aks-cluster"
export AKS_RESOURCE_GROUP="aks-rg"
export ARO_CLUSTER_NAME="my-aro-cluster"
export ARO_RESOURCE_GROUP="aro-rg"

# 4. Export AKS resources
./scripts/01-export-aks-resources.sh

# 5. Convert manifests for ARO
./scripts/02-convert-manifests.sh

# 6. Deploy to ARO
./scripts/03-deploy-to-aro.sh

# 7. Validate deployment
./scripts/04-validate-deployment.sh
```

## Documentation

### Core Migration Documents

1. **[Pre-Migration Checklist](docs/01-PRE-MIGRATION-CHECKLIST.md)**
   - ARO cluster provisioning requirements
   - Network connectivity validation
   - Database access configuration
   - Azure service integration checks

2. **[Migration Runbook](docs/02-MIGRATION-RUNBOOK.md)**
   - Detailed step-by-step execution guide
   - CLI commands for each phase
   - Validation checkpoints
   - Timing and dependencies

3. **[Troubleshooting Guide](docs/03-TROUBLESHOOTING.md)**
   - Common migration issues
   - Security Context Constraint problems
   - Networking and DNS issues
   - Database connectivity problems

4. **[Rollback Plan](docs/04-ROLLBACK-PLAN.md)**
   - Emergency rollback procedures
   - Traffic redirection strategies
   - Data consistency verification

5. **[Post-Migration Guide](docs/05-POST-MIGRATION.md)**
   - Performance validation
   - Security hardening
   - Monitoring setup
   - Cost optimization

## Prerequisites

### Required Tools

- **Azure CLI** (`az`) - v2.50.0+
- **kubectl** - v1.28.0+
- **OpenShift CLI** (`oc`) - v4.13.0+
- **jq** - for JSON processing
- **yq** - for YAML processing (optional but recommended)
- **git** - for version control

### Azure Permissions

- **AKS Cluster**: Reader access to source cluster
- **ARO Cluster**: Contributor access to target cluster
- **Azure Database**: Contributor access for firewall rules
- **Azure Key Vault**: Key Vault Administrator (or Secrets User)
- **Azure Container Registry**: AcrPull role assignment
- **Virtual Network**: Network Contributor for VNET peering/routing

### Access Requirements

- AKS cluster admin kubeconfig
- ARO cluster admin credentials
- Azure subscription with sufficient quota
- Database admin credentials for firewall rule updates

## Migration Phases

### Phase 1: Assessment and Planning (Days 1-3)
- Application dependency mapping
- Network topology documentation
- Database migration strategy
- Security and compliance review

### Phase 2: ARO Cluster Preparation (Days 4-5)
- Provision ARO cluster
- Configure networking and connectivity
- Set up Azure service integrations
- Establish monitoring and logging

### Phase 3: Application Migration (Days 6-8)
- Export AKS configurations
- Convert manifests for ARO compatibility
- Deploy and test in ARO staging environment
- Validate database connectivity

### Phase 4: Cutover and Validation (Days 9-10)
- Execute production cutover
- Update DNS records
- Perform smoke testing
- Monitor application health

### Phase 5: Post-Migration Optimization (Days 11-15)
- Performance tuning
- Cost analysis and optimization
- Security hardening
- Documentation and knowledge transfer

## Key Differences: AKS vs ARO

| Feature | AKS | ARO |
|---------|-----|-----|
| **Kubernetes Distribution** | Upstream Kubernetes | Red Hat OpenShift (Kubernetes + extensions) |
| **Ingress** | NGINX/Application Gateway | OpenShift Routes (HAProxy-based) |
| **Security** | Pod Security Standards | Security Context Constraints (SCCs) |
| **Registry Integration** | ACR with managed identity | ACR with pull secrets or managed identity |
| **Monitoring** | Azure Monitor | Prometheus + Grafana (built-in) |
| **Networking** | Azure CNI / Kubenet | OpenShift SDN / OVN-Kubernetes |
| **Load Balancer** | Azure Load Balancer | Azure Load Balancer (managed by OpenShift) |
| **Image Streams** | N/A | Native OpenShift feature |
| **Operators** | Helm / Kustomize | Operator Lifecycle Manager (OLM) |

## Migration Checklist Summary

- [ ] ARO cluster provisioned and accessible
- [ ] Network connectivity established (VNET peering or VPN)
- [ ] Azure Database firewall rules updated for ARO subnet
- [ ] ACR integration configured (pull secrets or managed identity)
- [ ] Azure Key Vault CSI driver installed on ARO
- [ ] Application manifests converted and tested
- [ ] Database connection strings updated
- [ ] DNS records prepared for cutover
- [ ] Rollback plan documented and tested
- [ ] Monitoring and alerting configured

## Support and Contribution

### Getting Help

- **Issues**: Report bugs or request features via GitHub Issues
- **Discussions**: Join community discussions for Q&A
- **Documentation**: Refer to inline documentation in scripts and manifests

### Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Submit a pull request with a detailed description

### License

This project is licensed under the MIT License - see LICENSE file for details.

## Acknowledgments

- Red Hat OpenShift Documentation
- Microsoft Azure Documentation
- Kubernetes Migration Best Practices
- Community contributors

---

**Next Steps**: Begin with the [Pre-Migration Checklist](docs/01-PRE-MIGRATION-CHECKLIST.md) to validate your environment readiness.

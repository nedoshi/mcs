# OpenShift Demos

This directory contains demonstration examples and tutorials for various OpenShift features and use cases.

## Available Demos

### [Enterprise Retail Hub](./enterprise-retail-hub/)

Multi-tier enterprise e-commerce microservices demo for ROSA/ARO workshops. Inspired by [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo).

**Features:**
- 4 Node.js microservices + API gateway + PostgreSQL
- OpenShift BuildConfigs, Routes, Secrets, HPA
- One-command `./deploy.sh` for live cluster deploy
- Enterprise IT procurement storefront (browse → cart → checkout)

**Use Cases:**
- Demonstrating OpenShift Topology and multi-service apps
- Developer advocacy for Routes, builds, and internal service mesh
- Scaling, health probes, and persistent state on managed OpenShift

### [ROSA 101 Welcome](./rosa-101-welcome/)

Minimal single-service web app for ROSA 101 workshops. Deploy via **Import from Git** in the Developer Console.

**Features:**
- Dockerfile-based build on UBI9 Node.js (optional, under `docker/`)
- Node.js S2I import-from-git (recommended)
- Static catalog UI with live pod/namespace info
- Health probes and optional Kubernetes manifests

**Use Cases:**
- First app deploy on ROSA
- Demonstrating routes, scaling, and builds
- Lightweight alternative to multi-service CoolStore demos

### [Deploying GitOps on ROSA or ARO](./deploying-gitops-on-rosa-or-aro/)

Automated deployment of a ROSA (Red Hat OpenShift Service on AWS) or ARO (Azure Red Hat OpenShift) cluster with OpenShift GitOps (Argo CD) pre-installed and configured.

**Features:**
- Terraform-based cluster provisioning
- Automated GitOps installation
- Route configuration with edge reencrypt

**Use Cases:**
- Setting up GitOps workflows on managed OpenShift
- Learning Argo CD integration
- CI/CD pipeline setup

### [Octopus Deploy + Argo CD on ARO](./octopus-argocd-aro-integration/)

Guide and tutorial for integrating Octopus Deploy with Argo CD (OpenShift GitOps) on Azure Red Hat OpenShift during a phased migration.

**Features:**
- Architecture overview (Octopus orchestration + Argo CD sync)
- Step-by-step tutorial with sample manifests and Octopus annotations
- Comparative analysis: Octopus + Argo CD vs Argo CD alone
- Curated official documentation links (verified)

**Use Cases:**
- Hybrid CD while moving workloads to ARO
- Enterprise approvals and audit with GitOps reconciliation
- Customer workshops on unified Octopus + GitOps workflows

### [Deploying an Application with Service Mesh](./demo-deploying-an-app-with-service-mesh/)

Demonstrates how to deploy an application and integrate it with OpenShift Service Mesh (based on Istio).

**Features:**
- Service Mesh namespace configuration
- Example application deployment
- Sidecar injection verification

**Use Cases:**
- Understanding Service Mesh integration
- Microservices communication patterns
- Traffic management and observability

## Getting Started

Each demo includes its own README with:
- Prerequisites
- Step-by-step instructions
- Configuration options
- Troubleshooting guides

Navigate to the specific demo directory for detailed instructions.

## Prerequisites

Common prerequisites across demos:

- OpenShift cluster access (or ability to create one)
- OpenShift CLI (`oc`) installed
- `kubectl` (optional, for some operations)
- Basic understanding of Kubernetes/OpenShift concepts

## Structure

```
openshift-demos/
├── README.md                                    # This file
├── enterprise-retail-hub/                      # Multi-tier e-commerce microservices demo
│   ├── README.md
│   ├── deploy.sh
│   ├── services/
│   ├── openshift/
│   └── database/
├── rosa-101-welcome/                           # ROSA 101 import-from-git demo
│   ├── README.md
│   ├── package.json
│   ├── server.js
│   ├── public/
│   ├── docker/Dockerfile
│   ├── openshift/buildconfig-nodejs.yaml
│   └── kubernetes/deployment.yaml
├── deploying-gitops-on-rosa-or-aro/            # GitOps deployment demo
│   ├── README.md
│   ├── main.tf
│   ├── terraform.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── install-gitops.sh
│   └── .gitignore
├── octopus-argocd-aro-integration/             # Octopus + Argo CD on ARO guide
│   ├── README.md
│   └── examples/
└── demo-deploying-an-app-with-service-mesh/    # Service Mesh demo
    ├── README.md
    ├── servicemeshroll.yaml
    ├── servicemeshmember.yaml
    └── app-deployment.yaml
```

## Contributing

When adding new demos:

1. Create a descriptive directory name
2. Include a comprehensive README.md
3. Provide example configurations
4. Add troubleshooting sections
5. Include cleanup instructions
6. Follow existing patterns and structure

## Additional Resources

- [OpenShift Documentation](https://docs.openshift.com/)
- [Red Hat OpenShift Service on AWS (ROSA)](https://docs.openshift.com/rosa/)
- [Azure Red Hat OpenShift (ARO)](https://docs.openshift.com/aro/)
- [OpenShift GitOps](https://docs.openshift.com/gitops/)
- [OpenShift Service Mesh](https://docs.openshift.com/container-platform/latest/service_mesh/v2x/ossm-about.html)

## Support

For issues or questions:
- Check the specific demo's README and troubleshooting sections
- Review OpenShift documentation
- Consult Red Hat support resources


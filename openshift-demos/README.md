# OpenShift Demos

This directory contains demonstration examples and tutorials for various OpenShift features and use cases.

## Available Demos

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
├── deploying-gitops-on-rosa-or-aro/            # GitOps deployment demo
│   ├── README.md
│   ├── main.tf
│   ├── terraform.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── install-gitops.sh
│   └── .gitignore
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


# Deploying GitOps on ROSA or ARO

This Terraform configuration automates the deployment of a ROSA (Red Hat OpenShift Service on AWS) or ARO (Azure Red Hat OpenShift) cluster with OpenShift GitOps (Argo CD) pre-installed and configured.

## Overview

This demo creates:
- A ROSA/ARO cluster with VPC networking
- OpenShift GitOps (Argo CD) operator installation
- GitOps route configuration with edge reencrypt termination

## Prerequisites

Before you begin, ensure you have:

1. **AWS Account** with appropriate permissions
2. **OCM Token** - Get from [Red Hat OpenShift Cluster Manager](https://console.redhat.com/openshift/token/rosa/show)
3. **Terraform** >= 1.0 installed
4. **OpenShift CLI (oc)** installed and in your PATH
5. **AWS CLI** configured with appropriate credentials
6. **Bash** shell (for the installation script)

## Required Variables

The following variables must be provided (see `terraform.tfvars.example` for format):

- `admin_username` - OpenShift cluster admin username
- `admin_password` - OpenShift cluster admin password (sensitive)
- `cluster_name` - Name for your ROSA/ARO cluster
- `aws_region` - AWS region where the cluster will be deployed
- `default_aws_tags` - Map of default tags for AWS resources

## Usage

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
admin_username = "admin"
admin_password = "your-secure-password-here"
cluster_name   = "my-rosa-gitops-cluster"
aws_region     = "us-east-1"

default_aws_tags = {
  Environment = "dev"
  Owner       = "your-email@example.com"
  Project     = "gitops-demo"
  CostCenter  = "468"
  ManagedBy   = "terraform"
}
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Apply the Configuration

```bash
terraform apply
```

This will:
1. Create the ROSA/ARO cluster (takes approximately 30-45 minutes)
2. Wait for the cluster to be ready
3. Automatically install OpenShift GitOps
4. Configure the GitOps route

### 5. Access GitOps

After the deployment completes, get the GitOps route URL:

```bash
oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'
```

Or use the Terraform output:

```bash
terraform output gitops_info
```

Access the GitOps UI in your browser using the route URL. The default admin username is typically `admin` and the password can be retrieved with:

```bash
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
```

## Module Source

The ROSA cluster module is sourced from a local path. You may need to adjust the `source` path in `main.tf` to match your environment:

```hcl
source = "../../../terraform_ocm_rosa_sts/rosa_sts_managed_oidc"
```

Alternatively, you can use the GitHub source (commented in the file):

```hcl
source = "github.com/rh-mobb/terraform_rhcs_rosa_sts//rosa_sts_managed_oidc"
```

## Outputs

After successful deployment, Terraform will output:

- `api_url` - OpenShift API URL for cluster access
- `gitops_route_command` - Command to get the GitOps route URL
- `gitops_info` - Instructions for accessing GitOps

## Post-Deployment Steps

1. **Verify GitOps Installation**:
   ```bash
   oc get pods -n openshift-gitops
   ```

2. **Get GitOps Admin Password**:
   ```bash
   oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
   ```

3. **Access GitOps UI**:
   - Get the route: `oc get route -n openshift-gitops openshift-gitops-server`
   - Open the URL in your browser
   - Login with username `admin` and the password from step 2

4. **Create Your First Application**:
   - Use the GitOps UI or CLI to create Argo CD applications
   - Connect to your Git repository
   - Start managing your applications with GitOps

## Troubleshooting

### Cluster Creation Fails

- Verify your AWS credentials are configured correctly
- Check that your OCM token is valid and has appropriate permissions
- Ensure the AWS region supports ROSA/ARO
- Review AWS service quotas for your account

### GitOps Installation Fails

- Check that the cluster is fully ready: `oc get nodes`
- Verify cluster connectivity: `oc cluster-info`
- Review installation logs in the script output
- Check GitOps operator status: `oc get csv -n openshift-gitops`

### Cannot Access GitOps UI

- Verify the route exists: `oc get route -n openshift-gitops`
- Check route status: `oc describe route openshift-gitops-server -n openshift-gitops`
- Ensure GitOps server pod is running: `oc get pods -n openshift-gitops`
- Check for firewall or network restrictions

### Login Retry Issues

The installation script will retry OpenShift login up to 30 times (with 60-second intervals). If login continues to fail:

- Verify cluster API URL is correct
- Check that admin credentials are valid
- Ensure cluster is fully provisioned (may take 30-45 minutes)
- Review cluster status in OCM console

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete the entire cluster and all associated resources. Ensure you have backups of any important data.

## Additional Resources

- [OpenShift GitOps Documentation](https://docs.openshift.com/gitops/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [ROSA Documentation](https://docs.openshift.com/rosa/)
- [ARO Documentation](https://docs.openshift.com/aro/)

## Support

For issues or questions:
- Check the troubleshooting section above
- Review Terraform and script logs
- Consult OpenShift and GitOps documentation
- Contact your Red Hat support representative


# Scenario 3: Public Cluster with Identity Providers and Machine Pools

## Overview

This scenario creates a ROSA HCP cluster with:
- Public API and console endpoints
- Multiple identity provider options
- Auto-scaling machine pools for different workload types
- Development-friendly configuration

## Prerequisites

1. Red Hat account with ROSA access
2. AWS account with appropriate permissions
3. OAuth applications configured (GitHub, Google, etc.)

## Identity Provider Setup

### GitHub OAuth

1. Go to GitHub Settings → Developer Settings → OAuth Apps
2. Create new OAuth App:
   - Name: `ROSA Dev Cluster`
   - Homepage URL: `https://console-openshift-console.apps.<your-cluster-domain>`
   - Callback URL: `https://oauth-openshift.apps.<your-cluster-domain>/oauth2callback/github`
3. Copy Client ID and generate Client Secret
4. Add to terraform.tfvars

### Google OAuth

1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID
3. Application type: Web application
4. Authorized redirect URIs: `https://oauth-openshift.apps.<your-cluster-domain>/oauth2callback/google`
5. Copy Client ID and Secret

### GitLab OAuth

1. Go to GitLab (or self-hosted) → User Settings → Applications
2. Create new application:
   - Name: `ROSA Cluster`
   - Redirect URI: `https://oauth-openshift.apps.<your-cluster-domain>/oauth2callback/gitlab`
   - Scopes: `read_user`, `openid`
3. Copy Application ID and Secret

## Deployment
```bash
cd scenarios/3-public-idp-pools

# Copy example vars
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

## Post-Deployment

### Grant Admin Access
```bash
# Get HTPasswd password
HTPASSWD_PASSWORD=$(terraform output -raw htpasswd_password)

# Login
oc login $(terraform output -raw cluster_api_url) -u kubeadmin -p $HTPASSWD_PASSWORD

# Grant cluster-admin to GitHub user
oc adm policy add-cluster-role-to-user cluster-admin github:your-username

# Grant to Google user
oc adm policy add-cluster-role-to-user cluster-admin google:user@company.com
```

### Create Developer Role
```bash
# Create role
oc create clusterrole developer-extended \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=pods,services,deployments,configmaps,secrets

# Bind to GitHub org
oc adm policy add-cluster-role-to-group developer-extended github:your-org
```

## Machine Pool Usage

### Schedule Pods to Specific Pools
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dev-app
spec:
  nodeSelector:
    pool-type: dev
  containers:
  - name: app
    image: myapp:latest
```

### Production Workloads
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-app
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        pool-type: prod
      containers:
      - name: app
        image: myapp:latest
        resources:
          requests:
            cpu: 2
            memory: 4Gi
```

## Cost Optimization

- Development pool auto-scales from 1-5 nodes
- Production pool scales 2-10 nodes based on load
- Single NAT gateway for cost savings
- Consider using Spot instances for dev pool

## Cleanup
```bash
terraform destroy
```
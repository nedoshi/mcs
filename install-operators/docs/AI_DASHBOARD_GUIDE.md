# Red Hat OpenShift AI - Dashboard Access Guide

This guide explains how to install and access the Red Hat OpenShift AI dashboard after installing the operator.

## Overview

Red Hat OpenShift AI (RHOAI) provides a platform for data scientists and ML engineers to build, train, and deploy AI/ML models. The dashboard is the main interface for accessing these capabilities.

## Prerequisites

1. OpenShift AI Operator installed and CSV in `Succeeded` phase
2. Access to the OpenShift cluster
3. Appropriate permissions to create resources in `redhat-ods-operator` namespace

## Step 1: Verify Operator is Ready

```bash
# Check operator status
make validate-csv-ai

# Or check manually
oc get csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator=
```

The CSV should be in `Succeeded` phase before proceeding.

## Step 2: Install DataScienceCluster

The DataScienceCluster custom resource enables the dashboard and other AI components.

```bash
# Install DataScienceCluster (takes 10-15 minutes)
make install-ai-datasciencecluster
```

This will:
- Create the DataScienceCluster CR
- Deploy dashboard component
- Deploy workbenches (Jupyter notebooks)
- Deploy data science pipelines
- Deploy model registry
- Wait for all components to be ready

### What Gets Installed

The default configuration installs:
- **Dashboard**: Main UI for accessing AI capabilities
- **Workbenches**: Jupyter notebook environments
- **Data Science Pipelines**: ML workflow orchestration
- **Model Registry**: Model versioning and management

Optional components (set to `Removed` by default):
- KServe (model serving)
- ModelMesh (alternative serving)
- CodeFlare (job scheduling)
- Ray (distributed computing)
- Kueue (job queue)
- Training Operator (distributed training)

## Step 3: Get Dashboard Information

```bash
# Get all AI dashboard info (route, status)
make ai-info

# Or get just the route
make ai-route
```

## Step 4: Access the Dashboard

### Option A: Via Route URL

```bash
# Get the route
ROUTE=$(make ai-route)

# Access in browser
echo "OpenShift AI Dashboard: https://$ROUTE"
```

### Option B: Via OpenShift Console

1. Login to OpenShift Console
2. Click the **application launcher** (grid icon) in the top-right corner
3. Select **Red Hat OpenShift AI**
4. A new tab will open with the dashboard

### Option C: Direct Route Access

```bash
# Get route directly
oc get route rhods-dashboard -n redhat-ods-applications

# Access the URL shown in the output
```

## Step 5: Login

Use your **OpenShift credentials** to login to the dashboard:
- Username: Your OpenShift username
- Password: Your OpenShift password

## Dashboard Features

Once logged in, you can:

1. **Create Workbenches**: Launch Jupyter notebook environments
2. **Manage Models**: View and manage ML models in the model registry
3. **Create Pipelines**: Build and run data science pipelines
4. **Monitor Resources**: View GPU resources, storage, and compute
5. **Access Documentation**: Built-in guides and tutorials

## Customizing DataScienceCluster

To enable additional components, edit `operators/ai/datasciencecluster.yaml`:

```yaml
spec:
  components:
    # Enable KServe for model serving
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
    
    # Enable ModelMesh
    modelmeshserving:
      managementState: Managed
    
    # Enable CodeFlare
    codeflare:
      managementState: Managed
```

Then apply the changes:

```bash
oc apply -f operators/ai/datasciencecluster.yaml
```

## Troubleshooting

### Dashboard Route Not Available

```bash
# Check DataScienceCluster status
oc get datasciencecluster default-dsc -n redhat-ods-operator

# Check dashboard pods
oc get pods -n redhat-ods-applications -l app=odh-dashboard

# Check dashboard logs
oc logs -n redhat-ods-applications -l app=odh-dashboard --tail=100

# Wait for route
oc wait --for=jsonpath='{.spec.host}' route/rhods-dashboard -n redhat-ods-applications --timeout=5m
```

### DataScienceCluster Not Ready

```bash
# Check DataScienceCluster conditions
oc describe datasciencecluster default-dsc -n redhat-ods-operator

# Check component status
oc get datasciencecluster default-dsc -n redhat-ods-operator -o jsonpath='{.status.components[*]}' | jq

# Check operator logs
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=100
```

### Dashboard Pods Not Starting

```bash
# Check pod status
oc get pods -n redhat-ods-applications

# Check pod events
oc describe pod <pod-name> -n redhat-ods-applications

# Check resource quotas
oc describe quota -n redhat-ods-applications

# Check node resources
oc top nodes
```

### Cannot Access Dashboard

1. **Check route exists:**
   ```bash
   oc get route rhods-dashboard -n redhat-ods-applications
   ```

2. **Check route is accessible:**
   ```bash
   curl -k https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')
   ```

3. **Check network policies:**
   ```bash
   oc get networkpolicies -n redhat-ods-applications
   ```

4. **Check service:**
   ```bash
   oc get svc odh-dashboard -n redhat-ods-applications
   ```

## Common Commands

```bash
# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-operator

# Check dashboard route
oc get route rhods-dashboard -n redhat-ods-applications

# Check dashboard pods
oc get pods -n redhat-ods-applications -l app=odh-dashboard

# Check workbenches
oc get pods -n redhat-ods-applications -l app=notebook-controller

# View dashboard logs
oc logs -n redhat-ods-applications -l app=odh-dashboard --tail=100

# Get all AI components
oc get all -n redhat-ods-applications
```

## Creating Your First Workbench

1. **Access the Dashboard** (see Step 4)
2. **Navigate to "Workbenches"** in the left sidebar
3. **Click "Create workbench"**
4. **Configure:**
   - Name: e.g., `my-notebook`
   - Image: Select a Jupyter image
   - Resources: CPU/Memory requirements
   - Storage: Persistent storage size
5. **Click "Create"**
6. **Wait for workbench to start**
7. **Click "Open"** to launch Jupyter

## Next Steps

1. **Create Workbenches**: Start Jupyter notebooks for development
2. **Upload Models**: Use the model registry to manage ML models
3. **Create Pipelines**: Build ML workflows with data science pipelines
4. **Deploy Models**: Use KServe or ModelMesh for model serving (if enabled)
5. **Monitor Resources**: Track GPU usage and compute resources

## Additional Resources

- [Red Hat OpenShift AI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [OpenShift AI User Guide](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai/2.9/html/red_hat_openshift_ai_user_guide/)
- [Data Science Cluster Configuration](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai/2.9/html/installing_and_configuring_red_hat_openshift_ai/installing-openshift-ai#installing-datasciencecluster)

## Quick Reference

```bash
# Install DataScienceCluster
make install-ai-datasciencecluster

# Get dashboard info
make ai-info

# Get dashboard route
make ai-route

# Check operator status
make validate-csv-ai

# Check DataScienceCluster
oc get datasciencecluster default-dsc -n redhat-ods-operator

# Get dashboard URL
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}'
```


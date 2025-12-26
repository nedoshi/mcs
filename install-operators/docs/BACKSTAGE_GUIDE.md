# Red Hat Developer Hub (Backstage) - Installation Guide

This guide explains how to install and access Red Hat Developer Hub (Backstage) after installing the operator.

## Overview

Red Hat Developer Hub (RHDH) is an internal developer platform built on Backstage that provides:
- **Software Catalog**: Centralized view of all services, applications, and resources
- **Software Templates**: Scaffold new projects with best practices
- **TechDocs**: Technical documentation integrated into the platform
- **API Documentation**: Discover and use APIs across your organization

## Prerequisites

1. Developer Hub Operator installed and CSV in `Succeeded` phase
2. Access to the OpenShift cluster
3. Appropriate permissions to create resources in `rhdh-operator` namespace

## Step 1: Verify Operator is Ready

```bash
# Check operator status
make validate-csv-developer-hub

# Or check manually
oc get csv -n rhdh-operator -l operators.coreos.com/rhdh.rhdh-operator=
```

The CSV should be in `Succeeded` phase before proceeding.

## Step 2: Install Backstage Instance

```bash
# Install Backstage (takes 5-10 minutes)
make install-backstage
```

This will:
- Create the Backstage CR
- Deploy Backstage application
- Create PostgreSQL database
- Enable route for external access
- Wait for all components to be ready

## Step 3: Get Backstage Information

```bash
# Get all Backstage info (route, status)
make backstage-info

# Or get just the route
make backstage-route
```

## Step 4: Access Developer Hub

### Option A: Via Route URL

```bash
# Get the route
ROUTE=$(make backstage-route)

# Access in browser
echo "Developer Hub: https://$ROUTE"
```

### Option B: Via OpenShift Console

1. Login to OpenShift Console
2. Click the **application launcher** (grid icon) in the top-right corner
3. Look for **Developer Hub** or **Backstage**
4. Click to open in a new tab

### Option C: Direct Route Access

```bash
# Get route directly
oc get route -n rhdh-operator -l app.kubernetes.io/name=backstage

# Or by name
oc get route backstage-developer-hub -n rhdh-operator

# Access the URL shown in the output
```

## Step 5: Login

Use your **OpenShift credentials** to login to Developer Hub:
- Username: Your OpenShift username
- Password: Your OpenShift password

## Backstage Features

Once logged in, you can:

1. **Browse Software Catalog**: View all services, applications, and resources
2. **Create New Components**: Use software templates to scaffold projects
3. **View Documentation**: Access TechDocs and API documentation
4. **Manage APIs**: Discover and integrate with APIs
5. **Track Dependencies**: Understand relationships between services

## Customizing Backstage

### Basic Configuration

The default Backstage instance includes:
- Local PostgreSQL database (10Gi)
- Route enabled for external access
- Resource limits configured

### Advanced Configuration

To customize Backstage, edit `operators/developer-hub/backstage.yaml`:

```yaml
spec:
  application:
    # Custom resource requirements
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    
    # Custom app configuration via ConfigMap
    appConfig:
      mountPath: /opt/app-root/src
      configMaps:
        - name: backstage-config
  
  # External database (optional)
  database:
    enableLocalDb: false
  postgres:
    enabled: false
```

### Adding Custom Configuration

1. **Create ConfigMap with app-config.yaml:**

```bash
oc create configmap backstage-config -n rhdh-operator \
  --from-file=app-config.yaml=path/to/app-config.yaml
```

2. **Update Backstage CR to reference ConfigMap:**

```yaml
spec:
  application:
    appConfig:
      mountPath: /opt/app-root/src
      configMaps:
        - name: backstage-config
```

3. **Apply changes:**

```bash
oc apply -f operators/developer-hub/backstage.yaml
```

## Troubleshooting

### Backstage Route Not Available

```bash
# Check Backstage status
oc get backstage developer-hub -n rhdh-operator

# Check Backstage pods
oc get pods -n rhdh-operator -l app.kubernetes.io/name=backstage

# Check route creation
oc get route -n rhdh-operator

# Check route labels
oc get route -n rhdh-operator --show-labels

# Wait for route
oc wait --for=jsonpath='{.spec.host}' route -n rhdh-operator -l app.kubernetes.io/name=backstage --timeout=5m
```

### Backstage Not Ready

```bash
# Check Backstage conditions
oc describe backstage developer-hub -n rhdh-operator

# Check pod status
oc get pods -n rhdh-operator

# Check pod logs
oc logs -n rhdh-operator -l app.kubernetes.io/name=backstage --tail=100

# Check database status
oc get pods -n rhdh-operator -l app.kubernetes.io/name=postgres
```

### Database Issues

```bash
# Check PostgreSQL pods
oc get pods -n rhdh-operator -l app.kubernetes.io/name=postgres

# Check database logs
oc logs -n rhdh-operator -l app.kubernetes.io/name=postgres --tail=100

# Check PVC
oc get pvc -n rhdh-operator

# Check database connection
oc exec -n rhdh-operator -it $(oc get pod -n rhdh-operator -l app.kubernetes.io/name=postgres -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -d backstage
```

### Cannot Access Backstage

1. **Check route exists:**
   ```bash
   oc get route -n rhdh-operator -l app.kubernetes.io/name=backstage
   ```

2. **Check route is accessible:**
   ```bash
   curl -k https://$(oc get route -n rhdh-operator -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].spec.host}')
   ```

3. **Check network policies:**
   ```bash
   oc get networkpolicies -n rhdh-operator
   ```

4. **Check service:**
   ```bash
   oc get svc -n rhdh-operator -l app.kubernetes.io/name=backstage
   ```

## Common Commands

```bash
# Check Backstage status
oc get backstage -n rhdh-operator

# Check Backstage route
oc get route -n rhdh-operator -l app.kubernetes.io/name=backstage

# Check Backstage pods
oc get pods -n rhdh-operator -l app.kubernetes.io/name=backstage

# Check database pods
oc get pods -n rhdh-operator -l app.kubernetes.io/name=postgres

# View Backstage logs
oc logs -n rhdh-operator -l app.kubernetes.io/name=backstage --tail=100

# Get all Developer Hub components
oc get all -n rhdh-operator
```

## Configuring Software Catalog

To populate the software catalog, you need to configure catalog locations:

1. **Access Backstage UI**
2. **Navigate to: Settings > Software Catalog > Locations**
3. **Add catalog locations:**
   - GitHub repositories
   - GitLab repositories
   - Local file systems
   - Custom integrations

4. **Or configure via ConfigMap:**

```yaml
catalog:
  locations:
    - type: url
      target: https://github.com/your-org/your-repo/blob/main/catalog-info.yaml
```

## Next Steps

1. **Configure Software Catalog**: Add your services and applications
2. **Create Software Templates**: Build templates for common project types
3. **Set up TechDocs**: Integrate documentation
4. **Configure Integrations**: Add GitHub, GitLab, Jira, etc.
5. **Customize UI**: Brand and customize the interface

## Additional Resources

- [Red Hat Developer Hub Documentation](https://access.redhat.com/documentation/en-us/red_hat_developer_hub)
- [Backstage Documentation](https://backstage.io/docs)
- [Backstage Software Catalog](https://backstage.io/docs/features/software-catalog/)

## Quick Reference

```bash
# Install Backstage
make install-backstage

# Get Backstage info
make backstage-info

# Get Backstage route
make backstage-route

# Check operator status
make validate-csv-developer-hub

# Check Backstage status
oc get backstage developer-hub -n rhdh-operator

# Get Backstage URL
oc get route -n rhdh-operator -l app.kubernetes.io/name=backstage -o jsonpath='https://{.items[0].spec.host}'
```


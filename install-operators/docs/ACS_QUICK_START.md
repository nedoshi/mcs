# ACS Quick Start Guide

Quick reference for installing and connecting to Red Hat Advanced Cluster Security (ACS).

## Installation Steps

### 1. Install ACS Operator

The operator should already be installed via the Makefile:

```bash
# Verify operator is installed
make validate-csv-acs

# Or check manually
oc get csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator=
```

### 2. Install ACS Central

```bash
# Install Central (takes 10-15 minutes)
make install-acs-central
```

This will:
- Deploy Central with route enabled
- Create 20Gi PVC for database
- Deploy Scanner for image scanning
- Wait for Central to be ready

### 3. Get Connection Information

```bash
# Get all ACS info (route, password, status)
make acs-info

# Or get individual components
make acs-route      # Get Central URL
make acs-password   # Get admin password
```

### 4. Access ACS Central UI

```bash
# Get the route
ROUTE=$(make acs-route)

# Get the password
PASSWORD=$(make acs-password)

echo "ACS Central: https://$ROUTE"
echo "Username: admin"
echo "Password: $PASSWORD"
```

### 5. Connect Cluster (Optional)

To connect this cluster to Central for monitoring:

```bash
# Install SecuredCluster
make install-acs-secured-cluster
```

## Connecting Additional Clusters

See [ACS_CLUSTER_CONNECTION.md](./ACS_CLUSTER_CONNECTION.md) for detailed instructions.

Quick steps:
1. Generate init bundle from Central UI
2. Apply init bundle to target cluster
3. Install ACS Operator on target cluster
4. Create SecuredCluster CR on target cluster

## Common Commands

```bash
# Check Central status
oc get central -n rhacs-operator

# Check Central pods
oc get pods -n rhacs-operator -l app=central

# Check Scanner pods
oc get pods -n rhacs-operator -l app=scanner

# Check SecuredCluster status
oc get securedcluster -n rhacs-operator

# View Central logs
oc logs -n rhacs-operator -l app=central --tail=100

# Get Central route
oc get route central -n rhacs-operator

# Get admin password
oc get secret central-htpasswd -n rhacs-operator -o jsonpath='{.data.password}' | base64 -d
```

## Troubleshooting

### Central Not Deploying

```bash
# Check operator status
oc get csv -n rhacs-operator

# Check Central CR events
oc describe central stackrox-central-services -n rhacs-operator

# Check pods
oc get pods -n rhacs-operator

# Check PVC
oc get pvc -n rhacs-operator
```

### Route Not Available

```bash
# Check if Central is deployed
oc get central stackrox-central-services -n rhacs-operator -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}'

# Wait for deployment
oc wait --for=condition=Deployed central/stackrox-central-services -n rhacs-operator --timeout=15m
```

## Next Steps

1. **Login to ACS Central UI**
2. **Generate API Token** for CI/CD integration
3. **Configure Security Policies**
4. **Set up Integrations** (Slack, email, etc.)
5. **Connect Additional Clusters** if needed

For detailed information, see:
- [ACS Cluster Connection Guide](./ACS_CLUSTER_CONNECTION.md)
- [Red Hat ACS Documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)


# Quick Start Guide - Keycloak on ROSA

This is a condensed guide for quickly deploying Keycloak. For detailed information, see [README.md](README.md).

## Prerequisites

1. ROSA cluster access with `oc` CLI installed
2. Logged in to your cluster: `oc login <cluster-api-url>`
3. Cluster admin permissions

## Quick Deployment

### Option 1: Automated Deployment (Recommended)

```bash
# Navigate to the directory
cd create-demo-clusters/aws/tf-rosa-keycloak

# Deploy everything (public route)
./deploy.sh public

# OR deploy with private route (internal only)
./deploy.sh private
```

The script will:
- Create namespace
- Install Keycloak Operator
- Deploy PostgreSQL
- Set up database
- Deploy Keycloak (via operator)
- Create route (if needed)
- Show you the access URL

### Option 2: Manual Deployment

```bash
# 1. Create namespace
oc apply -f 01-namespace.yaml

# 2. Install Keycloak Operator
oc apply -f 00-operator-subscription.yaml
# Wait for operator (2-5 minutes)
oc wait --for=condition=AtLatestKnown installplan -l operators.coreos.com/keycloak-operator.keycloak= -n keycloak --timeout=600s

# 3. Create secrets (⚠️ change passwords!)
oc apply -f 04-secrets.yaml

# 4. Deploy PostgreSQL
oc apply -f 02-postgresql.yaml
oc wait --for=condition=ready pod -l app=postgresql -n keycloak --timeout=300s

# 5. Setup database
./setup-database.sh

# 6. Deploy Keycloak (via operator)
oc apply -f 03-keycloak.yaml
# Wait for Keycloak to be ready (5-10 minutes)
oc wait --for=condition=ready keycloak/keycloak -n keycloak --timeout=900s

# 7. Check if route was created automatically, or create one manually
oc get route -n keycloak

# If no route exists, create one:
# Public route:
oc apply -f 05-route-public.yaml

# OR Private route:
# oc apply -f 05-route-private.yaml

# 8. Get the URL
oc get route keycloak -n keycloak
```

## Important: Update Route Hostname

Before creating the route, you need to update the hostname in the route file:

1. Get your cluster domain:
   ```bash
   oc get route -n openshift-console -o jsonpath='{.items[0].spec.host}' | sed 's/console-openshift-console\.//'
   ```

2. Edit `05-route-public.yaml` or `05-route-private.yaml`:
   ```yaml
   spec:
     host: keycloak-keycloak.apps.<your-cluster-domain>  # Replace <your-cluster-domain>
   ```

   OR let OpenShift generate it automatically by removing the `host` field:
   ```yaml
   spec:
     # host: keycloak-keycloak.apps.<your-cluster-domain>  # Commented out
     to:
       kind: Service
       name: keycloak
   ```

## First Access

1. Get the route URL:
   ```bash
   oc get route keycloak -n keycloak
   ```

2. Open the URL in your browser

3. Click "Administration Console"

4. Create your admin user (first-time setup)

5. Login and configure Keycloak

## Change Default Passwords

**CRITICAL**: Change default passwords before production use!

```bash
# Update PostgreSQL password
oc create secret generic postgresql-secret \
  --from-literal=username=postgres \
  --from-literal=password=<new-password> \
  --from-literal=database=postgres \
  -n keycloak \
  --dry-run=client -o yaml | oc apply -f -

# Update Keycloak database password
oc create secret generic keycloak-db-secret \
  --from-literal=username=keycloak \
  --from-literal=password=<new-password> \
  --from-literal=database=keycloak \
  -n keycloak \
  --dry-run=client -o yaml | oc apply -f -

# Restart deployments
oc rollout restart deployment/postgresql -n keycloak
# For Keycloak, delete the pod and let operator recreate it
oc delete pod -l app=keycloak -n keycloak
# Or update the Keycloak CR to trigger a restart
oc patch keycloak keycloak -n keycloak --type=json -p='[{"op": "replace", "path": "/spec/keycloakDeploymentSpec/image", "value": "quay.io/keycloak/keycloak:25.0.1"}]'
```

## Verify Deployment

```bash
# Check all resources
oc get all -n keycloak

# Check Keycloak CR status
oc get keycloak keycloak -n keycloak

# Check operator pod
oc get pods -n keycloak -l name=keycloak-operator

# Check Keycloak pods
oc get pods -n keycloak -l app=keycloak

# Check route
oc get route keycloak -n keycloak

# View Keycloak logs
oc logs -l app=keycloak -n keycloak -f

# View operator logs
oc logs -l name=keycloak-operator -n keycloak -f
```

## Troubleshooting

### Pods not starting
```bash
# Check Keycloak CR status
oc get keycloak keycloak -n keycloak -o yaml
oc describe keycloak keycloak -n keycloak

# Check operator logs
oc logs -l name=keycloak-operator -n keycloak

# Check pod status
oc describe pod <pod-name> -n keycloak
oc logs <pod-name> -n keycloak
```

### Database connection issues
```bash
# Test database connectivity
oc exec -it <keycloak-pod> -n keycloak -- nc -zv postgresql 5432

# Check PostgreSQL logs
oc logs -l app=postgresql -n keycloak
```

### Route not accessible
```bash
# Check route status
oc get route keycloak -n keycloak -o yaml

# Check if load balancer is created
oc get svc -n openshift-ingress
```

## Next Steps

1. ✅ Change default passwords
2. ✅ Configure your realm
3. ✅ Set up identity providers (LDAP, OAuth, etc.)
4. ✅ Configure clients and users
5. ✅ Set up backups (use `backup-database.sh`)
6. ✅ Configure monitoring and alerts

For detailed information, see [README.md](README.md).


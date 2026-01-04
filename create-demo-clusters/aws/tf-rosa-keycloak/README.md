# Keycloak Setup on ROSA with Private VPC

This guide provides a complete, production-ready setup for Keycloak on Red Hat OpenShift Service on AWS (ROSA) clusters with worker nodes in a private VPC. This solution addresses networking challenges by leveraging OpenShift Routes and provides a standalone, production-level Keycloak instance.

## Table of Contents

1. [Overview](#overview)
2. [Networking Solution for Private VPC](#networking-solution-for-private-vpc)
3. [Prerequisites](#prerequisites)
4. [Architecture](#architecture)
5. [Installation Steps](#installation-steps)
6. [Post-Installation Configuration](#post-installation-configuration)
7. [Accessing Keycloak](#accessing-keycloak)
8. [Production Considerations](#production-considerations)
9. [Troubleshooting](#troubleshooting)
10. [Additional Resources](#additional-resources)

## Overview

This setup deploys:
- **Keycloak Operator** - Manages Keycloak lifecycle automatically
- **Keycloak** - Production-ready identity and access management (managed by operator)
- **PostgreSQL Database** - Persistent storage for Keycloak data
- **OpenShift Routes** - External access without complex VPC networking (automatically created by operator)
- **Persistent Volumes** - Data persistence for both Keycloak and PostgreSQL
- **Production Configuration** - High availability, resource limits, and security best practices

### Why Keycloak Operator?

The Keycloak Operator provides:
- ✅ **Automated Lifecycle Management** - Handles deployments, updates, and scaling
- ✅ **Automatic Route Creation** - Creates OpenShift Routes automatically
- ✅ **Health Monitoring** - Built-in health checks and monitoring
- ✅ **Simplified Configuration** - Declarative configuration via Custom Resources
- ✅ **Production Ready** - Best practices built-in
- ✅ **Easy Updates** - Operator handles rolling updates

## Networking Solution for Private VPC

### The Challenge

When ROSA worker nodes are in a private VPC, accessing services from your internal network can be complex. Traditional solutions require:
- VPC peering
- VPN connections
- Transit Gateways
- Route table modifications
- Security group configurations

### Our Solution: OpenShift Routes

**OpenShift Routes solve this problem elegantly** by:
1. **Automatic Load Balancer Creation**: OpenShift automatically creates AWS Network Load Balancers (NLB) or Application Load Balancers (ALB) when you create Routes
2. **Public Endpoints**: Routes can be configured with public endpoints, making Keycloak accessible from anywhere (or private endpoints for internal-only access)
3. **No VPC Configuration Required**: You don't need to modify VPC settings, route tables, or security groups manually
4. **TLS Termination**: Routes handle SSL/TLS certificates automatically
5. **DNS Integration**: Routes can integrate with Route53 for custom domains

### How It Works

```
Internet/Internal Network
    ↓
AWS Load Balancer (created by OpenShift Route)
    ↓
OpenShift Router Pods (in public subnets)
    ↓
Keycloak Service (ClusterIP)
    ↓
Keycloak Pods (in private subnets)
```

The OpenShift Router pods run in public subnets and can receive traffic from the AWS Load Balancer. They then route traffic internally to your Keycloak service, which is accessible only within the cluster.

### Alternative: Private Route with VPN

If you need Keycloak accessible only from your internal network:
1. Configure the Route as private (internal load balancer)
2. Set up VPN or Direct Connect between your network and AWS VPC
3. Configure Route53 private hosted zones if needed

## Prerequisites

### Required Access

1. **ROSA Cluster Access**
   - Admin access to your ROSA cluster
   - `oc` CLI installed and configured
   - Cluster admin permissions

2. **AWS Permissions**
   - Load balancer creation permissions (handled by OpenShift)
   - Route53 permissions (if using custom domain)

3. **Storage**
   - StorageClass configured in your cluster
   - Sufficient persistent volume capacity (minimum 20GB recommended)

### Tools Required

```bash
# Install OpenShift CLI if not already installed
# macOS
brew install openshift-cli

# Linux
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Verify installation
oc version
```

### Verify Cluster Access

```bash
# Login to your cluster
oc login <your-cluster-api-url>

# Verify access
oc whoami
oc get nodes
oc get storageclass
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / Internal Network              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│         AWS Network Load Balancer (Public/Private)          │
│         (Automatically created by OpenShift Route)          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│              OpenShift Router Pods (Public Subnets)         │
│              - Handles TLS termination                      │
│              - Routes traffic to services                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                    Keycloak Service (ClusterIP)              │
└───────────┬───────────────────────────────────┬─────────────┘
            │                                   │
            ↓                                   ↓
┌──────────────────────┐          ┌──────────────────────┐
│   Keycloak Pod 1     │          │   Keycloak Pod 2     │
│   (Private Subnet)   │          │   (Private Subnet)   │
└──────────┬───────────┘          └──────────┬───────────┘
           │                                  │
           └──────────────┬───────────────────┘
                          │
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              PostgreSQL Service (ClusterIP)                 │
└───────────┬───────────────────────────────────┬─────────────┘
            │                                   │
            ↓                                   ↓
┌──────────────────────┐          ┌──────────────────────┐
│  PostgreSQL Pod 1    │          │  PostgreSQL Pod 2     │
│  (Private Subnet)   │          │  (Private Subnet)     │
│  + Persistent Volume │          │  + Persistent Volume  │
└──────────────────────┘          └──────────────────────┘
```

## Installation Steps

### Step 1: Create Namespace

```bash
# Create the keycloak namespace
oc create namespace keycloak

# Or use the provided manifest
oc apply -f 01-namespace.yaml
```

### Step 2: Install Keycloak Operator

The Keycloak Operator manages Keycloak lifecycle automatically:

```bash
# Install the Keycloak Operator
oc apply -f 00-operator-subscription.yaml

# Wait for the operator to be installed (this may take 2-5 minutes)
oc wait --for=condition=AtLatestKnown installplan -l operators.coreos.com/keycloak-operator.keycloak= -n keycloak --timeout=600s

# Verify operator is running
oc get pods -n keycloak -l name=keycloak-operator
```

**Note**: The operator is installed from the `community-operators` catalog. If this catalog is not available, you may need to enable it in OperatorHub or use a different catalog source.

### Step 3: Create PostgreSQL Database

Keycloak requires a database for persistent storage. We'll use PostgreSQL:

```bash
# Deploy PostgreSQL
oc apply -f 02-postgresql.yaml

# Wait for PostgreSQL to be ready
oc wait --for=condition=ready pod -l app=postgresql -n keycloak --timeout=300s

# Verify PostgreSQL is running
oc get pods -n keycloak
```

### Step 4: Initialize PostgreSQL Database

```bash
# Use the provided script (recommended)
chmod +x setup-database.sh
./setup-database.sh

# Or manually:
# Get the PostgreSQL pod name
POSTGRES_POD=$(oc get pod -l app=postgresql -n keycloak -o jsonpath='{.items[0].metadata.name}')

# Create Keycloak database
oc exec -it $POSTGRES_POD -n keycloak -- psql -U postgres -c "CREATE DATABASE keycloak;"

# Create Keycloak user
oc exec -it $POSTGRES_POD -n keycloak -- psql -U postgres -c "CREATE USER keycloak WITH PASSWORD 'keycloak';"

# Grant privileges
oc exec -it $POSTGRES_POD -n keycloak -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;"
```

**⚠️ Security Note**: Change the default password in production! Update the password in `04-secrets.yaml` before deploying.

### Step 5: Create Database Secret

```bash
# Create secret for database connection
oc apply -f 04-secrets.yaml

# Or manually:
oc create secret generic keycloak-db-secret \
  --from-literal=username=keycloak \
  --from-literal=password=keycloak \
  --from-literal=database=keycloak \
  -n keycloak
```

### Step 6: Deploy Keycloak (via Operator)

Deploy Keycloak using the Custom Resource. The operator will handle everything:

```bash
# Deploy Keycloak Custom Resource
oc apply -f 03-keycloak.yaml

# Wait for Keycloak to be ready (this may take 5-10 minutes)
oc wait --for=condition=ready keycloak/keycloak -n keycloak --timeout=900s

# Check Keycloak status
oc get keycloak keycloak -n keycloak

# Check pods (operator will create the deployment)
oc get pods -n keycloak

# Check services (operator creates the service automatically)
oc get svc -n keycloak
```

The Keycloak Operator will automatically:
- Create the Keycloak deployment
- Create the Keycloak service
- Create an OpenShift Route (if hostname is configured)
- Manage health checks and monitoring
- Handle rolling updates

### Step 7: Verify Route Creation

The operator may create a route automatically, or you can create one manually:

```bash
# Check if route was created automatically
oc get route -n keycloak

# If no route exists, create one manually:
# Public route (accessible from internet)
oc apply -f 05-route-public.yaml

# OR private route (internal only)
# oc apply -f 05-route-private.yaml

# Get the route URL
oc get route keycloak -n keycloak
```

**Note**: If you configured a hostname in the Keycloak CR (`03-keycloak.yaml`), the operator may create the route automatically. Otherwise, create it manually using the route manifests.

### Step 8: Verify Installation

```bash
# Check all resources
oc get all -n keycloak

# Check Keycloak Custom Resource status
oc get keycloak keycloak -n keycloak -o yaml

# Check persistent volumes
oc get pvc -n keycloak

# Check route
oc get route keycloak -n keycloak

# Check operator pod
oc get pods -n keycloak -l name=keycloak-operator

# Test connectivity (replace with your route URL)
curl -k https://keycloak-keycloak.apps.<your-cluster-domain>/health
```

## Post-Installation Configuration

### Initial Keycloak Setup

1. **Access Keycloak Console**
   ```bash
   # Get the route URL
   KEYCLOAK_URL=$(oc get route keycloak -n keycloak -o jsonpath='{.spec.host}')
   echo "Access Keycloak at: https://$KEYCLOAK_URL"
   ```

2. **Create Admin User**
   - Navigate to the Keycloak URL
   - Click "Administration Console"
   - First-time setup will prompt you to create an admin user
   - **Username**: `admin` (or your preferred username)
   - **Password**: Choose a strong password

3. **Configure Realm Settings**
   - Login to the administration console
   - Go to "Realm Settings" → "General"
   - Set your organization name
   - Configure email settings if needed

### Production Hardening

1. **Change Default Passwords**
   ```bash
   # Update PostgreSQL password
   oc set env deployment/postgresql -n keycloak \
     POSTGRES_PASSWORD=<new-secure-password>
   
   # Update Keycloak database secret
   oc create secret generic keycloak-db-secret \
     --from-literal=username=keycloak \
     --from-literal=password=<new-secure-password> \
     -n keycloak \
     --dry-run=client -o yaml | oc apply -f -
   
   # Restart Keycloak to pick up new secret
   oc rollout restart deployment/keycloak -n keycloak
   ```

2. **Enable HTTPS Only**
   - The Route already uses TLS termination
   - In Keycloak Admin Console: Realm Settings → Security → Require SSL: "All requests"

3. **Configure Resource Limits**
   - Review and adjust resource limits in `03-keycloak.yaml` based on your needs
   - Monitor resource usage: `oc top pods -n keycloak`

4. **Set Up Backups**
   ```bash
   # Backup PostgreSQL data
   oc exec -it <postgresql-pod> -n keycloak -- \
     pg_dump -U keycloak keycloak > keycloak-backup.sql
   ```

5. **Configure Monitoring**
   - Keycloak exposes metrics on `/metrics` endpoint
   - Configure Prometheus to scrape Keycloak metrics
   - Set up alerts for Keycloak availability

## Accessing Keycloak

### Public Access (Default)

If you used `05-route-public.yaml`:
```bash
# Get the public URL
oc get route keycloak -n keycloak

# Access in browser
https://keycloak-keycloak.apps.<your-cluster-domain>
```

### Private Access

If you used `05-route-private.yaml`:
- The load balancer will be internal-only
- Access from within the VPC or via VPN/Direct Connect
- Use the internal DNS name provided by the route

### Custom Domain (Optional)

To use a custom domain:

1. **Get the Load Balancer DNS Name**
   ```bash
   oc get route keycloak -n keycloak -o jsonpath='{.status.ingress[0].host}'
   ```

2. **Create Route53 Record**
   - Create a CNAME record pointing to the load balancer DNS name
   - Or use AWS Certificate Manager for custom SSL certificate

3. **Update Route with Custom Domain**
   ```bash
   oc patch route keycloak -n keycloak --type=json \
     -p='[{"op": "add", "path": "/spec/host", "value": "keycloak.yourdomain.com"}]'
   ```

## Production Considerations

### High Availability

The current setup includes:
- **Keycloak**: 2 replicas (can be increased)
- **PostgreSQL**: Consider using a managed database service (RDS) for production
- **Persistent Storage**: Uses ReadWriteMany or ReadWriteOnce volumes

### Scaling

```bash
# Scale Keycloak horizontally (update the CR)
oc patch keycloak keycloak -n keycloak --type=json \
  -p='[{"op": "replace", "path": "/spec/instances", "value": 3}]'

# Or edit the CR directly
oc edit keycloak keycloak -n keycloak
# Change: instances: 2 → instances: 3

# The operator will automatically scale the deployment

# Scale PostgreSQL (requires StatefulSet for proper scaling)
# Consider using RDS or managed PostgreSQL for production
```

### Database Options

For production, consider:
1. **AWS RDS PostgreSQL**: Managed, highly available, automated backups
2. **AWS RDS Multi-AZ**: Automatic failover
3. **AWS RDS Read Replicas**: For read scaling

To use RDS instead of in-cluster PostgreSQL:
1. Create RDS PostgreSQL instance
2. Update `keycloak-db-secret` with RDS connection details
3. Update `03-keycloak.yaml` with RDS hostname
4. Remove `02-postgresql.yaml` deployment

### Security Best Practices

1. **Network Policies**: Restrict pod-to-pod communication
2. **Service Mesh**: Consider using OpenShift Service Mesh for mTLS
3. **Secrets Management**: Use external secrets management (e.g., HashiCorp Vault)
4. **Regular Updates**: Keep Keycloak and PostgreSQL images updated
5. **Audit Logging**: Enable audit logging in Keycloak
6. **Backup Strategy**: Regular automated backups of PostgreSQL

### Performance Tuning

1. **JVM Settings**: Adjust memory settings in `03-keycloak.yaml` based on load
2. **Database Connection Pool**: Tune connection pool settings
3. **Caching**: Configure distributed caching for multi-instance deployments
4. **Load Testing**: Perform load testing before production deployment

## Troubleshooting

### Keycloak Pods Not Starting

```bash
# Check Keycloak CR status
oc get keycloak keycloak -n keycloak -o yaml
oc describe keycloak keycloak -n keycloak

# Check operator logs
oc logs -l name=keycloak-operator -n keycloak

# Check pod logs
oc logs -l app=keycloak -n keycloak

# Check pod events
oc describe pod <keycloak-pod-name> -n keycloak

# Common issues:
# - Database connection failures: Check PostgreSQL is running and secret is correct
# - Memory issues: Check resource limits in Keycloak CR
# - Volume mount issues: Check PVC status
# - Operator not ready: Check operator pod status
```

### Database Connection Issues

```bash
# Test database connectivity
oc exec -it <keycloak-pod> -n keycloak -- \
  nc -zv <postgresql-service> 5432

# Check PostgreSQL logs
oc logs -l app=postgresql -n keycloak

# Verify database exists
oc exec -it <postgresql-pod> -n keycloak -- \
  psql -U postgres -l
```

### Route Not Accessible

```bash
# Check route status
oc get route keycloak -n keycloak -o yaml

# Check load balancer
oc get svc -n openshift-ingress

# Check router pods
oc get pods -n openshift-ingress

# Verify DNS
nslookup <route-hostname>
```

### Persistent Volume Issues

```bash
# Check PVC status
oc get pvc -n keycloak

# Check PV details
oc describe pvc <pvc-name> -n keycloak

# Check storage class
oc get storageclass
```

### Performance Issues

```bash
# Check resource usage
oc top pods -n keycloak

# Check database performance
oc exec -it <postgresql-pod> -n keycloak -- \
  psql -U keycloak -d keycloak -c "SELECT * FROM pg_stat_activity;"
```

## Additional Resources

### Keycloak Documentation
- [Keycloak Official Documentation](https://www.keycloak.org/documentation)
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Keycloak Deployment Guide](https://www.keycloak.org/docs/latest/server_installation/)

### OpenShift Documentation
- [OpenShift Routes](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
- [OpenShift Persistent Storage](https://docs.openshift.com/container-platform/latest/storage/understanding-persistent-storage.html)
- [OpenShift Security](https://docs.openshift.com/container-platform/latest/security/)

### AWS Documentation
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [AWS VPC Networking](https://docs.aws.amazon.com/vpc/)
- [Route53 DNS](https://docs.aws.amazon.com/route53/)

### ROSA Documentation
- [ROSA Networking](https://docs.openshift.com/rosa/rosa_networking/rosa-networking-overview.html)
- [ROSA Cluster Administration](https://docs.openshift.com/rosa/rosa_cluster_admin/)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Keycloak and OpenShift logs
3. Consult the official documentation links
4. Contact your Red Hat support team for ROSA-specific issues

## Quick Reference Commands

```bash
# Get Keycloak URL
oc get route keycloak -n keycloak

# Check all resources
oc get all -n keycloak

# View Keycloak logs
oc logs -l app=keycloak -n keycloak -f

# Restart Keycloak
oc rollout restart deployment/keycloak -n keycloak

# Scale Keycloak
oc scale deployment/keycloak --replicas=3 -n keycloak

# Backup database
oc exec -it <postgresql-pod> -n keycloak -- \
  pg_dump -U keycloak keycloak > backup.sql

# Restore database
oc exec -i <postgresql-pod> -n keycloak -- \
  psql -U keycloak keycloak < backup.sql
```


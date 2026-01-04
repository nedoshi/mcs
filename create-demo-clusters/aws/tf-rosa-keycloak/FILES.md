# File Structure and Purpose

This document explains the purpose of each file in this Keycloak setup.

## Documentation Files

### README.md
**Main documentation** - Comprehensive guide covering:
- Overview and architecture
- Networking solution for private VPC
- Prerequisites and installation steps
- Post-installation configuration
- Production considerations
- Troubleshooting
- Additional resources

### QUICKSTART.md
**Quick start guide** - Condensed version for rapid deployment:
- Quick deployment steps
- Essential commands
- First access instructions
- Basic troubleshooting

### NETWORKING.md
**Networking deep dive** - Detailed explanation of:
- The private VPC networking challenge
- How OpenShift Routes solve the problem
- Architecture diagrams
- Public vs private routes
- DNS configuration
- Troubleshooting network issues

### FILES.md (this file)
**File structure reference** - Overview of all files

## Deployment Manifests

### 01-namespace.yaml
Creates the `keycloak` namespace for all Keycloak resources.

### 02-postgresql.yaml
PostgreSQL database deployment:
- PersistentVolumeClaim (20GB storage)
- PostgreSQL Deployment (PostgreSQL 15)
- PostgreSQL Service (ClusterIP)
- Health checks and resource limits

### 03-keycloak.yaml
Keycloak deployment:
- Keycloak Deployment (2 replicas, production-ready)
- Keycloak Service (ClusterIP with session affinity)
- Resource limits and security context
- Health checks
- Database connection configuration

### 04-secrets.yaml
Kubernetes secrets:
- `postgresql-secret`: PostgreSQL admin credentials
- `keycloak-db-secret`: Keycloak database user credentials
- **⚠️ Change default passwords before production!**

### 05-route-public.yaml
OpenShift Route with **public** load balancer:
- Accessible from internet
- TLS termination (edge)
- Automatically creates AWS public load balancer

### 05-route-private.yaml
OpenShift Route with **internal** load balancer:
- Accessible only from within VPC
- Requires VPN/Direct Connect for external access
- TLS termination (edge)
- Automatically creates AWS internal load balancer

## Scripts

### deploy.sh
**Automated deployment script** - Deploys everything:
- Creates namespace
- Deploys PostgreSQL
- Sets up database
- Deploys Keycloak
- Creates route (public or private)
- Shows deployment summary

Usage:
```bash
./deploy.sh public   # Deploy with public route
./deploy.sh private  # Deploy with private route
```

### setup-database.sh
**Database initialization script**:
- Creates Keycloak database
- Creates Keycloak database user
- Grants necessary privileges
- Verifies PostgreSQL is ready

### backup-database.sh
**Database backup script**:
- Creates SQL backup of Keycloak database
- Saves to `./backups/` directory
- Timestamped backup files
- Can be scheduled for automated backups

Usage:
```bash
./backup-database.sh
```

### restore-database.sh
**Database restore script**:
- Restores Keycloak database from backup
- Scales down Keycloak during restore
- Scales up Keycloak after restore
- Safety confirmation prompt

Usage:
```bash
./restore-database.sh ./backups/keycloak_backup_20240101_120000.sql
```

## Other Files

### .gitignore
Git ignore file for:
- Backup files (*.sql)
- Sensitive files (*.pem, *.key, *.crt)
- Terraform state files
- OS files

## Deployment Order

For manual deployment, follow this order:

1. `01-namespace.yaml` - Create namespace
2. `04-secrets.yaml` - Create secrets (change passwords!)
3. `02-postgresql.yaml` - Deploy PostgreSQL
4. `setup-database.sh` - Initialize database
5. `03-keycloak.yaml` - Deploy Keycloak
6. `05-route-public.yaml` OR `05-route-private.yaml` - Create route

Or use `deploy.sh` to automate all steps.

## Quick Reference

| File | Purpose | When to Use |
|------|---------|-------------|
| README.md | Full documentation | Read first for complete understanding |
| QUICKSTART.md | Quick deployment | Fast deployment reference |
| NETWORKING.md | Networking details | Understanding VPC networking solution |
| deploy.sh | Automated deployment | Easiest way to deploy everything |
| 01-05-*.yaml | Kubernetes manifests | Manual deployment or customization |
| *.sh scripts | Helper scripts | Database setup, backups, restores |

## Customization

All YAML files can be customized:
- Resource limits (CPU/memory)
- Replica counts
- Storage sizes
- Image versions
- Environment variables
- Security settings

Edit the files before deployment or patch after deployment.

## Security Notes

⚠️ **IMPORTANT**: 
- Change default passwords in `04-secrets.yaml` before production
- Review security contexts in deployment files
- Consider using external secrets management (Vault, etc.)
- Enable network policies for additional security
- Regular backups using `backup-database.sh`


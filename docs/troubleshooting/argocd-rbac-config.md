# ArgoCD RBAC Configuration with Azure AD

## Prerequisites
- ArgoCD installed in your ROSA cluster
- Azure AD application configured for authentication
- Access to ArgoCD's ConfigMap and Deployment

## Step-by-Step Configuration

### 1. Create ArgoCD RBAC ConfigMap
Edit the ArgoCD rbac ConfigMap to define group and user mappings:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Syntax: [role], [group/user], [action], [resource], [permission]
    
    # Full admin access for specific Azure AD group
    g, azure-ad-admins@yourcompany.com, role:admin
    
    # Read-only access for developers
    g, azure-dev-team@yourcompany.com, role:readonly
    
    # Specific project-level permissions
    g, project-alpha-team@yourcompany.com, role:admin, project/project-alpha, allow

  policy.default: role:readonly
```

### 2. Configure Authentication in ArgoCD Deployment
Modify the ArgoCD deployment to ensure group claims are processed:

```yaml
spec:
  template:
    spec:
      containers:
      - name: argocd-server
        args:
        - /usr/local/bin/argocd-server
        - --dex-disable-tls
        - --insecure
```

### 3. Azure AD Application Configuration
In your Azure AD application registration:
- Ensure group claims are enabled
- Set "Group membership claims" to "All groups" or "Security groups"

### 4. Advanced RBAC Mapping Example
```yaml
data:
  policy.csv: |
    # Granular role-based access
    g, azure-ops-team@yourcompany.com, role:admin, *, allow
    g, azure-dev-team@yourcompany.com, role:admin, project/dev-projects, allow
    g, azure-readonly-team@yourcompany.com, role:readonly, *, allow

  # Default access level for any unmatched users
  policy.default: role:none
```

## Important Considerations
- Use email addresses exactly as they appear in Azure AD
- Ensure group names match precisely
- Roles include: admin, readonly, none
- Use `*` for wildcard matching
- Test configurations incrementally

## Troubleshooting
- Verify group claims are being passed
- Check ArgoCD logs for authentication issues
- Confirm Azure AD application permissions

## Recommended Roles
- `role:admin`: Full cluster management
- `role:readonly`: View-only access
- `role:none`: No access
```

### Key Mapping Strategies
1. Direct Group Mapping
   - Map Azure AD groups directly to ArgoCD roles
   - Provides granular access control
   - Minimizes administrative overhead

2. Claim-Based Authorization
   - Leverage group claims from Azure AD
   - Configure precise permissions per group
   - Reduce need for broad directory permissions

### Best Practices
- Principle of Least Privilege
- Regular access reviews
- Use specific group claims
- Avoid overly broad permissions

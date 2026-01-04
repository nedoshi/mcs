# Keycloak Operator Notes

## Operator Version Compatibility

The Keycloak Operator from the `community-operators` catalog may have different API versions and CR structures depending on the version installed. This document provides guidance on handling version differences.

## Checking Your Operator Version

```bash
# Check installed operator version
oc get csv -n keycloak | grep keycloak

# Check CRD structure
oc get crd keycloaks.keycloak.org -o yaml

# Check available CR fields
oc explain keycloak.spec
```

## Common API Versions

### keycloak.org/v1alpha1 (Older/Common)
```yaml
apiVersion: keycloak.org/v1alpha1
kind: Keycloak
spec:
  instances: 2
  externalAccess:
    enabled: true
  db:
    vendor: postgres
    host: postgresql
    usernameSecret:
      name: keycloak-db-secret
      key: username
    passwordSecret:
      name: keycloak-db-secret
      key: password
```

### k8s.keycloak.org/v1alpha1 (Newer)
```yaml
apiVersion: k8s.keycloak.org/v1alpha1
kind: Keycloak
spec:
  instances: 2
  hostname:
    hostname: ""
  http:
    httpEnabled: true
  database:
    vendor: postgres
    host: postgresql
    databaseSecret:
      name: keycloak-db-secret
```

## Troubleshooting CR Issues

If the provided CR (`03-keycloak.yaml`) doesn't work:

1. **Check the CRD schema:**
   ```bash
   oc get crd keycloaks.keycloak.org -o jsonpath='{.spec.versions[*].name}'
   oc explain keycloak.spec
   ```

2. **Check operator logs:**
   ```bash
   oc logs -l name=keycloak-operator -n keycloak
   ```

3. **Check CR status:**
   ```bash
   oc get keycloak keycloak -n keycloak -o yaml
   oc describe keycloak keycloak -n keycloak
   ```

4. **Try a minimal CR first:**
   ```yaml
   apiVersion: keycloak.org/v1alpha1
   kind: Keycloak
   metadata:
     name: keycloak
     namespace: keycloak
   spec:
     instances: 1
     externalAccess:
       enabled: true
     db:
       vendor: postgres
       host: postgresql
       usernameSecret:
         name: keycloak-db-secret
         key: username
       passwordSecret:
         name: keycloak-db-secret
         key: password
   ```

## Alternative: Manual Deployment

If the operator doesn't work as expected, you can still deploy Keycloak manually using a Deployment. However, the operator approach is recommended for:
- Automatic lifecycle management
- Easier updates
- Built-in health monitoring
- Automatic route creation

## Updating the CR

If you need to update the CR structure:

1. Check the operator documentation for your version
2. Update `03-keycloak.yaml` with the correct structure
3. Apply the updated CR:
   ```bash
   oc apply -f 03-keycloak.yaml
   ```

## Operator Catalog Sources

The Keycloak Operator is available from:
- `community-operators` - Community maintained (default in our setup)
- `redhat-operators` - Red Hat certified (if available)

To check available catalogs:
```bash
oc get catalogsource -n openshift-marketplace
```

To switch catalog sources, update `00-operator-subscription.yaml`:
```yaml
spec:
  source: redhat-operators  # or community-operators
  sourceNamespace: openshift-marketplace
```


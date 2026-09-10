# ARO HCP External Authentication — Troubleshooting

Guide for Azure Red Hat OpenShift Hosted Control Planes (ARO HCP) with mandatory external authentication.

> **Preview:** API version `2024-06-10-preview` and procedures may change before GA. See [ARO HCP validation runbook](../guide/aro-hcp-validation/README.md).

## Table of Contents

- [Symptom index](#symptom-index)
- [Prerequisites checklist](#prerequisites-checklist)
- [Admin credential issues](#admin-credential-issues)
- [External auth deployment](#external-auth-deployment)
- [Console login failures](#console-login-failures)
- [CLI authentication](#cli-authentication)
- [RBAC and group claims](#rbac-and-group-claims)
- [API version drift](#api-version-drift)
- [Comparison with classic ARO mistakes](#comparison-with-classic-aro-mistakes)
- [References](#references)

---

## Symptom index

| Symptom | Likely cause | Section |
|---------|--------------|---------|
| `az aro list-credentials` fails | Using classic ARO command on HCP | [Classic ARO mistakes](#comparison-with-classic-aro-mistakes) |
| `requestAdminCredential` hangs | Async polling / token expiry | [Admin credential](#admin-credential-issues) |
| `oc get clusteroperators` forbidden | No admin kubeconfig or expired | [Admin credential](#admin-credential-issues) |
| Bicep deploy fails on `hcpOpenShiftClusters` | Wrong API version or cluster name | [External auth deployment](#external-auth-deployment) |
| Console redirect loop | Wrong RHBK redirect URI | [Console login](#console-login-failures) |
| Console loads but login fails | Missing or misnamed client secret | [Console login](#console-login-failures) |
| User logs in but no permissions | RBAC or groups claim | [RBAC](#rbac-and-group-claims) |
| `invalid audience` in token | `issuerAudiences` order wrong | [External auth deployment](#external-auth-deployment) |

---

## Prerequisites checklist

```bash
# Azure context
az account show --query '{name:name, id:id}' -o json

# Cluster exists (HCP API — not az aro show)
az rest --method GET \
  --uri "/subscriptions/${ARO_SUBSCRIPTION_ID}/resourceGroups/${ARO_RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${ARO_CLUSTER_NAME}?api-version=2024-06-10-preview" \
  | jq '{provisioningState: .properties.provisioningState, apiUrl: .properties.apiServer.url}'

# Admin kubeconfig
test -f "${KUBECONFIG}" && oc whoami
```

---

## Admin credential issues

### Credential script returns no kubeconfig

1. Confirm required env vars: `ARO_RESOURCE_GROUP`, `ARO_CLUSTER_NAME`
2. Verify cluster provisioning state is `Succeeded`
3. Check Azure RBAC — caller needs permission to POST `requestAdminCredential`
4. Re-authenticate: `az login` and clear stale token: `unset ACCESS_TOKEN`

### Async operation stuck

The script uses `watch` against `Azure-AsyncOperation`. If it never completes:

```bash
# Manual check — copy AsyncOperation URL from script verbose output
curl -s -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
  "<async-operation-url>" | jq .
```

Terminal states: `Succeeded`, `Failed`, `Canceled`.

### Credential expired mid-session

Admin kubeconfig TTL is **24 hours**. Re-run:

```bash
docs/guide/aro-hcp-validation/scripts/request-aro-admin-credential.sh
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
```

---

## External auth deployment

### Bicep template fails

| Error | Fix |
|-------|-----|
| Resource not found | `clusterName` param must match existing `hcpOpenShiftClusters` name |
| Invalid api-version | Update `FRONTEND_API_VERSION` when Microsoft publishes new preview/GA |
| Parent resource invalid | Cluster must be fully provisioned |

Deploy from [externalauth.bicep](../guide/aro-hcp-validation/scripts/externalauth.bicep):

```bash
az deployment group create \
  --resource-group "${ARO_RESOURCE_GROUP}" \
  --template-file externalauth.bicep \
  --parameters clusterName="${ARO_CLUSTER_NAME}" ...
```

### issuerAudiences misconfiguration

> First value in `issuerAudiences` **must** be the OpenShift Web Console OAuth client ID.

Correct example:

```bash
issuerAudiences='("openshift-console", "openshift-cli")'
```

Incorrect (CLI ID first):

```bash
issuerAudiences='("openshift-cli", "openshift-console")'  # WRONG
```

### Propagation delay

After successful Bicep deployment, external auth may take **several minutes**. Wait before testing console login.

---

## Console login failures

### Redirect URI mismatch

Get console host:

```bash
oc get route console -n openshift-console -o jsonpath='https://{.spec.host}/auth/callback'
```

Add exact URI to RHBK client `openshift-console` → Valid redirect URIs.

### Missing console client secret

Secret **must** be named:

```
{externalAuthName}-console-openshift-console
```

in namespace `openshift-config`, key `clientSecret`.

```bash
EXTERNAL_AUTH_NAME=aro-hcp-auth
oc get secret "${EXTERNAL_AUTH_NAME}-console-openshift-console" -n openshift-config
```

Create if missing — see [03-external-auth-rhbk.md](../guide/aro-hcp-validation/03-external-auth-rhbk.md).

---

## CLI authentication

ARO HCP does not support `oc login -u kubeadmin -p ...`.

Use OIDC token from RHBK per [RHAC access guide](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/06-access.html):

```bash
oc login "${OPENSHIFT_API_URL}" --token=<oidc-access-token>
oc whoami
```

For repeated use, configure credential plugin or `oc-oidc` flow documented in RHAC module 06.

---

## RBAC and group claims

### User authenticates but has no permissions

1. Confirm RHBK user is in group mapped to `groups` claim (e.g. `openshift_admins`)
2. Verify Bicep `groupsClaim` matches token claim name
3. Confirm ClusterRoleBinding exists:

```bash
oc get clusterrolebinding openshift-admins -o yaml
```

4. Decode JWT at [jwt.io](https://jwt.io) (lab only — do not paste production tokens into public tools) and verify `groups` claim

### Username claim mismatch

RHBK typically uses `preferred_username`. Bicep parameter:

```bicep
param usernameClaim string = 'preferred_username'
```

RBAC bindings must reference the mapped OpenShift username format.

---

## API version drift

Pin version in scripts and Bicep:

| Component | Current pin |
|-----------|-------------|
| ARM GET cluster | `2024-06-10-preview` |
| Bicep resource | `@2024-06-10-preview` |
| requestAdminCredential | `2024-06-10-preview` |

When Microsoft releases GA:

1. Update [request-aro-admin-credential.sh](../guide/aro-hcp-validation/scripts/request-aro-admin-credential.sh)
2. Update [externalauth.bicep](../guide/aro-hcp-validation/scripts/externalauth.bicep)
3. Re-run Path A checklist in [validation-report.md](../guide/aro-hcp-validation/validation-report.md)

---

## Comparison with classic ARO mistakes

| Classic ARO (wrong for HCP) | ARO HCP (correct) |
|------------------------------|-------------------|
| `az aro list-credentials` | `request-aro-admin-credential.sh` |
| `oc get oauth cluster` / OAuth CR | Bicep `externalAuths` resource |
| Azure AD via OAuth CR | RHBK (or OIDC) via ARM external auth |
| `az aro show` | `az rest` on `hcpOpenShiftClusters` |
| Permanent kubeadmin | 24h admin kubeconfig |

Workshop content in [bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb) uses classic patterns — do not copy IdP modules verbatim.

---

## References

- [RHAC — ARO HCP external auth](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html)
- [RHAC — Keycloak configuration](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/05-keycloak.html)
- [RHAC — Access with external credentials](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/06-access.html)
- [ARO HCP validation runbook](../guide/aro-hcp-validation/README.md)
- [ROSA HCP external auth (analogous patterns)](ROSA-HCP-External-auth.md)
- [Azure/ARO-HCP](https://github.com/Azure/ARO-HCP/)

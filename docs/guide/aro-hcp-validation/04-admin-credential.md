# ARO HCP Validation — Administrative Credential

ARO HCP clusters have **no kubeadmin**. Bootstrap tasks use a **24-hour cluster-admin kubeconfig** from the `requestAdminCredential` ARM action.

> Classic workshop step `az aro list-credentials` is invalid for HCP.

## When to use admin credential vs RHBK user

| Task | Credential |
|------|------------|
| Install operators, CRDs, cluster-scoped RBAC bootstrap | Admin kubeconfig (24h) |
| Day-to-day workshop labs as student | RHBK OIDC user |
| GitOps bootstrap (first Application/ArgoCD) | Admin kubeconfig, then hand off to RHBK admin user |

## Step 1 — Request kubeconfig

```bash
source docs/guide/aro-hcp-validation/scripts/env.sh
cd docs/guide/aro-hcp-validation/scripts

chmod +x request-aro-admin-credential.sh
./request-aro-admin-credential.sh
```

**Expected output:** `Wrote aro-cluster.kubeconfig`

The script POSTs to:

```
/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/{name}/requestAdminCredential
```

API version: `2024-06-10-preview` (override with `FRONTEND_API_VERSION`).

## Step 2 — Use kubeconfig

```bash
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
oc get clusteroperators
```

All operators should report `Available=True`. Mark **PA-04** and **PA-05**.

## Step 3 — Renewal during long test sessions

Admin credentials expire after **24 hours**. Re-run:

```bash
./request-aro-admin-credential.sh
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
oc whoami   # expect system:admin or equivalent cluster-admin identity
```

Mark **PA-11** after confirming re-issue works.

## Localhost / integration RP testing

If testing against a local resource provider frontend (`FRONTEND_HOST=*localhost*`), set:

```bash
export ARM_X_MS_IDENTITY_URL="https://dummyhost.identity.azure.net"
```

See script comments for correlation header behavior.

## Script location

[scripts/request-aro-admin-credential.sh](scripts/request-aro-admin-credential.sh) — adapted from [RHAC ARO HCP guide](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html).

## Next step

Configure external auth: [03-external-auth-rhbk.md](03-external-auth-rhbk.md)

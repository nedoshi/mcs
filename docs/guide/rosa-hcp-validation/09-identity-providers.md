# TC-08 — Identity providers (htpasswd / LDAP / OIDC)

**Provenance:** Inferred from repo (`rosa create idp`, [use-cases.md](../../../cluster-creation-cloud/aws/docs/use-cases.md) multiple-IDP example).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Adds and validates an **identity provider** on ROSA HCP via supported ROSA/OCM interfaces (not direct `oauth/cluster` patch), including RBAC for a non-admin test user.

## Why this matters

- Labs need htpasswd quickly; enterprises need Entra/Okta alongside external auth clusters.
- Validates HostedCluster OAuth reconciliation after IdP CR updates.
- Ensures `oc login` and console flows for multiple IdPs.

## Architecture

```
 rosa create idp ──► OCM / HostedCluster spec
                           │
                           ▼
                    OAuth server (managed)
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
         Console login              oc login --token
```

## Prerequisites

- Cluster without **exclusive** external-auth-only restriction blocking local IdPs—or use Entra path from TC-05.
- Cluster-admin `oc` context.

## Steps

1. Create htpasswd IdP (lab-friendly):

   ```bash
   htpasswd -c -B -b /tmp/htpasswd testuser 'ChangeMe-Now!'
   rosa create idp --cluster="${CLUSTER_NAME}" --type=htpasswd \
     --name=lab-htpasswd --from-file=/tmp/htpasswd
   ```

   > On ROSA HCP, prefer `rosa create idp` over editing `oauth/cluster` directly.

2. Bind test user:

   ```bash
   oc create clusterrolebinding lab-user-view \
     --clusterrole=view \
     --user="htpasswd:lab-htpasswd:testuser"
   ```

3. Login:

   ```bash
   oc login "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url')" \
     -u testuser -p 'ChangeMe-Now!'
   oc whoami
   oc auth can-i create deployment -n default
   ```

4. List IdPs:

   ```bash
   rosa list idps --cluster="${CLUSTER_NAME}"
   oc get oauthclient -A 2>/dev/null || true
   ```

5. (Optional) Second IdP—follow `tf-rosa/examples/rosa-hcp-public-with-multiple-machinepools-and-idps/`.

## Expected output

- `rosa list idps` shows `lab-htpasswd`.
- `oc whoami` returns `htpasswd:lab-htpasswd:testuser`.
- `can-i create deployment` is `no`; `get pods` is `yes` cluster-wide for view role.

## Success criteria

```bash
rosa list idps -c "${CLUSTER_NAME}" | grep -q lab-htpasswd
oc auth can-i get pods --all-namespaces --as="htpasswd:lab-htpasswd:testuser" | grep -q yes
oc auth can-i create deployment -n default --as="htpasswd:lab-htpasswd:testuser" | grep -q no
```

## Failure signals

- `oauth/cluster` patch forbidden → use `rosa create idp` only.
- Login 401 → htpasswd secret not synced; wait and check `authentication.operator` logs.
- External-auth-only cluster rejects local IdP → expected; use TC-05 Entra flow instead.

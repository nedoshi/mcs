# TC-05 — External authentication at cluster create

**Provenance:** Inferred from repo (`tf-rosa/examples/external-auth.tfvars.example`, [ROSA-HCP-External-auth.md](../../troubleshooting/ROSA/ROSA-HCP-External-auth.md), [ENTRA-ID-SETUP.md](../../../cluster-creation-cloud/aws/tf-rosa/docs/ENTRA-ID-SETUP.md)).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Creates ROSA HCP with **external authentication enabled at install** (irreversible), wires an IdP (e.g. Microsoft Entra ID), and validates console + `oc` login without relying on long-lived kubeadmin.

## Why this matters

- Matches ARO HCP and regulated customers who mandate corporate IdP from day 0.
- Catches RHCS API regressions for external auth CRs on HostedCluster.
- Validates break-glass admin credential still works alongside external users.

## Architecture

```
 User ──► Entra ID / Keycloak (OIDC)
              │
              ▼
        ROSA HCP OAuth (HostedCluster)
              │
              ├── Console (openshift-console client)
              └── CLI (openshift-cli public client)
```

## Prerequisites

- IdP tenant with clients pre-created (redirect URIs updated after console URL known).
- Terraform or `rosa`/RHCS API path with `external_auth_providers_enabled = true` **before** install.
- RHCS `client_id` / `client_secret` for Terraform path.

**Warning:** Cannot enable external auth post-install on HCP—cluster must be recreated if missed.

## Steps

### Path A — Terraform (`tf-rosa`)

1. Copy example:

   ```bash
   cd cluster-creation-cloud/aws/tf-rosa
   cp examples/external-auth.tfvars.example terraform.tfvars
   ```

2. Set `external_auth_providers_enabled = true` and cluster fields; `terraform apply`.

3. After apply, complete IdP secret wiring per [ENTRA-ID-SETUP.md](../../../cluster-creation-cloud/aws/tf-rosa/docs/ENTRA-ID-SETUP.md).

### Path B — ROSA CLI (if supported for your version)

Use flags from product docs for external auth at create; otherwise use Path A.

### IdP validation

1. Fetch console URL:

   ```bash
   oc get route console -n openshift-console -o jsonpath='https://{.spec.host}{"\n"}'
   ```

2. Log in via browser as test user in IdP group mapped to `cluster-admin` or `cluster-admins`.

3. CLI with OIDC token:

   ```bash
   oc login "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url')" --token="${OIDC_TOKEN}"
   oc whoami
   ```

4. Confirm external auth config exists:

   ```bash
   oc get authentication.config.openshift.io cluster -o yaml | grep -A5 external
   ```

5. Break-glass admin still works (if issued):

   ```bash
   rosa create admin --cluster="${CLUSTER_NAME}"
   ```

## Expected output

- Install completes with external auth enabled in cluster description / OCM JSON.
- IdP login succeeds; `oc whoami` shows IdP username.
- Unauthorized user cannot escalate without RBAC binding.

## Success criteria

```bash
# IdP user context
oc auth can-i create clusterrolebinding --all-namespaces   # expect no for non-admin user
# Admin group user
oc auth can-i '*' '*' --all-namespaces                     # expect yes for openshift_admins equivalent
```

Record IdP group → ClusterRoleBinding in validation report.

## Failure signals

- Redirect URI mismatch on console login → update IdP app registration with exact console host.
- `oauth/cluster` patch attempts fail on HCP → use `rosa create idp` / RHCS API only.
- External auth disabled in tfvars → destroy cluster and recreate with flag true.

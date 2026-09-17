# TC-02 — Public ROSA HCP cluster lifecycle

**Provenance:** Inferred from repo (`hcp-ansible/roles/rosa_hcp_public`, `tf-rosa/examples/standard.tfvars.example`).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Installs a **public** ROSA HCP cluster (API and routes reachable per ROSA public networking model), waits for `ready`, obtains admin credentials, and validates core operators.

## Why this matters

- Default MOBB/dev path; validates HyperShift + managed control plane without PrivateLink complexity.
- Regression signal for OCM install pipeline and default ingress (public ALB/NLB behavior).
- Baseline for day-2 tests (TC-10) before private/shared-VPC variants.

## Architecture

```
 Internet / corporate network
        │
        ▼
 ┌──────────────┐     ┌─────────────────────────┐
 │ Route53      │     │ ROSA Hosted Control Plane│
 │ api.* apps.* │────►│ (Red Hat managed)        │
 └──────────────┘     └───────────┬─────────────┘
                                  │ kube API
 ┌────────────────────────────────▼────────────┐
 │ Customer VPC — worker nodes (MachinePools)   │
 │ openshift-ingress / router-default           │
 └─────────────────────────────────────────────┘
```

## Prerequisites

- TC-01 complete (roles + OIDC).
- VPC with **public + private subnets** across ≥2 AZs (or ROSA-managed network).
- `BILLING_ACCOUNT_ID`, `OIDC_CONFIG_ID`, `OPERATOR_PREFIX` set.

```bash
export VERSION="$(rosa list versions --channel-group stable --hosted-cp -r "${AWS_DEFAULT_REGION}" -o json | jq -r '.[0].id')"
export REPLICAS=2
export COMPUTE_TYPE="m5.xlarge"
```

## Steps

1. (Optional) Create ROSA-managed network:

   ```bash
   rosa create network --region "${AWS_DEFAULT_REGION}" --yes
   # Capture subnet IDs from output for step 2
   ```

2. Create cluster:

   ```bash
   rosa create cluster \
     --cluster-name "${CLUSTER_NAME}" \
     --region "${AWS_DEFAULT_REGION}" \
     --version "${VERSION}" \
     --compute-machine-type "${COMPUTE_TYPE}" \
     --replicas "${REPLICAS}" \
     --hosted-cp \
     --oidc-config-id "${OIDC_CONFIG_ID}" \
     --operator-roles-prefix "${OPERATOR_PREFIX}" \
     --billing-account "${BILLING_ACCOUNT_ID}" \
     --mode auto \
     --yes
   ```

3. Watch state:

   ```bash
   watch -n 30 "rosa describe cluster -c ${CLUSTER_NAME} -o json | jq -r '.state,.status'"
   ```

4. On failure, inspect install logs:

   ```bash
   rosa logs install --cluster="${CLUSTER_NAME}"
   ```

5. Create admin credential and login:

   ```bash
   rosa create admin --cluster="${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"
   export KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}"
   oc login "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url')" \
     --username cluster-admin --password "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.admin_credentials.password')"
   ```

6. Core health:

   ```bash
   oc get clusterversion
   oc get clusteroperators
   oc get nodes
   ```

## Expected output

- Cluster `state` transitions: `pending` → `installing` → `ready`.
- `oc get clusteroperators` shows `AVAILABLE=True` for critical operators (within version skew).
- API URL resolves: `dig +short "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url' | sed 's|https://||')"`

## Success criteria

```bash
STATE=$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.state')
[[ "${STATE}" == "ready" ]]
oc get co -o json | jq -e '[.items[] | select(.status.conditions[]? | select(.type=="Available" and .status!="True"))] | length == 0'
oc get nodes --no-headers | wc -l | xargs test "${REPLICAS}" -le
```

## Failure signals

- Stuck in `installing` >90m → `rosa logs install`, check subnet tags, NAT, STS roles.
- `InvalidSubnet` → subnets lack `kubernetes.io/cluster/<tag>` or wrong AZ count.
- Operators `Degraded` → `oc describe co <name>`, check cloud credentials and ingress.

## Cleanup (optional)

```bash
rosa delete cluster -c "${CLUSTER_NAME}" --yes --watch
```

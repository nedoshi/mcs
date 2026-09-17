# TC-03 — Private ROSA HCP cluster lifecycle

**Provenance:** Inferred from repo (`hcp-ansible/roles/rosa_hcp_private`, `tf-rosa` private examples, troubleshooting guide).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Provisions a **private** ROSA HCP cluster (private API and/or private ingress per install flags), validates access from inside the VPC, and documents ingress scope.

## Why this matters

- Regulated workloads require no public API endpoint.
- Validates PrivateLink / internal NLB ingress—common enterprise default.
- Pairs with TC-09 when apps must be exposed outside the VPC.

## Architecture

```
 Corporate network / VPN / Direct Connect
        │
        ▼
 ┌─────────────────────────────────────────┐
 │ Customer VPC (private subnets only)      │
 │  ┌─────────┐   ┌──────────────────────┐ │
 │  │ Bastion │──►│ Private API + Ingress │ │
 │  └─────────┘   │ (NLB + VPC endpoints) │ │
 │                └──────────┬─────────────┘ │
 │                           ▼               │
 │                    Worker nodes           │
 └─────────────────────────────────────────┘
        ▲
        │ Hosted control plane (off-VPC)
        └──────── Red Hat / AWS managed
```

## Prerequisites

- TC-01 complete.
- VPC with **private subnets** in ≥2 AZs; NAT or egress for workers if pulling images.
- Bastion or VPN host in VPC for API/ingress tests.
- No public cluster with same name.

```bash
export PRIVATE_SUBNET_IDS="subnet-aaa,subnet-bbb,subnet-ccc"
```

## Steps

1. Create private cluster (adjust flags to match your QE doc / `rosa create cluster --help`):

   ```bash
   rosa create cluster \
     --cluster-name "${CLUSTER_NAME}" \
     --region "${AWS_DEFAULT_REGION}" \
     --version "${VERSION}" \
     --compute-machine-type "${COMPUTE_TYPE}" \
     --replicas "${REPLICAS}" \
     --subnet-ids "${PRIVATE_SUBNET_IDS}" \
     --private \
     --hosted-cp \
     --oidc-config-id "${OIDC_CONFIG_ID}" \
     --operator-roles-prefix "${OPERATOR_PREFIX}" \
     --billing-account "${BILLING_ACCOUNT_ID}" \
     --mode auto \
     --yes
   ```

2. Wait for `ready` (same as TC-02).

3. From **inside VPC**, describe ingress:

   ```bash
   rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq '{ingress, private_link, api}'
   ```

4. After admin login from bastion:

   ```bash
   oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.endpointPublishingStrategy}{"\n"}'
   oc get svc router-default -n openshift-ingress -o wide
   ```

5. Confirm API is not reachable from public internet (from laptop, expect timeout/refused):

   ```bash
   curl -k --connect-timeout 5 "https://$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url' | sed 's|https://||')/healthz" || true
   ```

## Expected output

- `rosa describe` shows private API / private link indicators consistent with install flags.
- `endpointPublishingStrategy` uses internal load balancer scope where applicable.
- API health check **fails** from outside VPC; **succeeds** from bastion.

## Success criteria

```bash
[[ "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.state')" == "ready" ]]
# From bastion only:
oc whoami
oc get co -o json | jq -e '[.items[] | select(.metadata.name=="ingress")] | .[0].status.conditions[] | select(.type=="Available").status' | grep -q True
```

Document public API reachability test as **FAIL** from internet, **PASS** from VPC.

## Failure signals

- Install fails on subnet routing → missing NAT gateway or S3/ECR VPC endpoints.
- Console unreachable from corp network without VPN → expected; not a fail if private design.
- `private_link` misconfigured → `rosa logs install` IAM errors on VPC endpoint roles.

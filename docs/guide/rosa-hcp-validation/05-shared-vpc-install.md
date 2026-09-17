# TC-04 — ROSA HCP Shared VPC installation

**Provenance:** Inferred from repo ([Shared VPC tutorial](../../../cluster-creation-cloud/aws/docs/hcp-shared-vpc/ROSA-HCP-SharedVPC-Installation-Tutorial.md), `shared-vpc/terraform`).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Installs ROSA HCP with worker subnets in a **Shared VPC** owned by a network account, including cross-account IAM (Route53, VPC endpoints) and RAM-shared subnets.

## Why this matters

- Enterprises centralize VPC ownership; cluster teams only get workload accounts.
- Validates DNS domain under `p3.openshiftapps.com` and hosted zone delegation.
- QE regression for cross-account `sts:AssumeRole` on shared VPC roles.

## Architecture

```
 ┌──────────────── Network account ────────────────┐
 │ VPC + private subnets (RAM share)                │
 │ Route53 private zones + Route53/VPC endpoint roles│
 └────────────────────┬────────────────────────────┘
                      │ RAM
 ┌────────────────────▼────────────────────────────┐
 │ Cluster account: STS roles, OIDC, workers       │
 │ ROSA HCP (HostedCluster) in shared subnets      │
 └─────────────────────────────────────────────────┘
```

## Prerequisites

- Two AWS accounts with credentials (`shared-vpc-account`, `cluster-account` profiles).
- RAM share accepted; subnets tagged for ROSA.
- DNS domain reserved:

  ```bash
  rosa create dns-domain --hosted-cp
  export DNS_DOMAIN="<from output>"
  ```

- Environment variables per tutorial Phase 1–3 (`VPC_ID`, `SUBNET_IDS`, `SHARED_VPC_ACCOUNT_ID`, `CLUSTER_ACCOUNT_ID`).

See full variable checklist in tutorial [Quick Reference](../../../cluster-creation-cloud/aws/docs/hcp-shared-vpc/ROSA-HCP-SharedVPC-Installation-Tutorial.md#quick-reference).

## Steps

1. **Network account:** deploy shared VPC, hosted zones, IAM roles (tutorial Phases 1–3). Confirm RAM resource share `ACTIVE`.

2. **Cluster account:** run TC-01 role bootstrap with cluster account profile.

3. **Cluster account:** create cluster with shared subnet IDs and shared VPC flags (exact flags depend on ROSA version—mirror tutorial Phase 4):

   ```bash
   rosa create cluster \
     --cluster-name "${CLUSTER_NAME}" \
     --region "${REGION}" \
     --version "${VERSION}" \
     --subnet-ids "${SUBNET_IDS}" \
     --hosted-cp \
     --oidc-config-id "${OIDC_ID}" \
     --operator-roles-prefix "${CLUSTER_NAME}" \
     --billing-account "${BILLING_ACCOUNT_ID}" \
     --shared-vpc \
     --hosted-zone-id "${PRIVATE_HOSTED_ZONE_ID}" \
     --vpc-endpoint-role-arn "${VPC_ENDPOINT_ROLE_ARN}" \
     --route53-role-arn "${ROUTE53_ROLE_ARN}" \
     --mode auto \
     --yes
   ```

   Adjust parameter names to match `rosa create cluster --help` for your CLI version.

4. **Post-install (tutorial Phase 5):**

   ```bash
   rosa describe cluster --cluster="${CLUSTER_NAME}" -o json | jq '.state,.dns,.network'
   rosa create admin --cluster="${CLUSTER_NAME}"
   oc get nodes -o wide
   ```

5. **Cross-account DNS:**

   ```bash
   aws route53 list-resource-record-sets --hosted-zone-id "${PRIVATE_HOSTED_ZONE_ID}" \
     --query "ResourceRecordSets[?Type=='A' || Type=='CNAME']" --profile shared-vpc-account
   ```

## Expected output

- Cluster reaches `ready`.
- Worker nodes use IPs from shared VPC CIDR.
- Route53 records created in network-account zones.

## Success criteria

```bash
[[ "$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.state')" == "ready" ]]
oc get nodes -o json | jq -e '.items[].metadata.labels["failure-domain.beta.kubernetes.io/zone"]'
aws ec2 describe-subnets --subnet-ids $(echo "${SUBNET_IDS}" | tr ',' ' ') \
  --query 'Subnets[].VpcId' --output text | tr '\t' '\n' | sort -u | wc -l | xargs test 1 -eq
```

All subnet VPC IDs must match shared `VPC_ID`.

## Failure signals

- `Domain 'X' is incompatible with architecture parent domain` → use `rosa create dns-domain --hosted-cp`.
- `failed to find dns domain` → domain not registered in OCM org.
- AssumeRole failures on Route53/VPC endpoint role → trust policy or externalId mismatch (see [Shared-VPC-IAM.md](../../../cluster-creation-cloud/aws/shared-vpc/terraform/Shared-VPC-IAM.md)).
- Workers in wrong VPC → subnet IDs from non-shared VPC.

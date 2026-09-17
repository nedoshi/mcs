# TC-01 — STS account and operator roles (Hosted CP)

**Provenance:** Inferred from repo (`rosa create account-roles`, `tf-rosa/roles.tf`, Shared VPC IAM docs).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Confirms STS **account roles**, **OIDC config/provider**, and **hosted-CP operator roles** exist and trust the correct OCM installer role before `rosa create cluster --hosted-cp`.

## Why this matters

- Every ROSA HCP cluster is STS-only; missing `AssumeRole` on operator roles blocks install at `validating`.
- Enterprises use a **prefix** per environment (`prod-rosa-account`); QE must prove prefix isolation across parallel tests.
- Shared VPC adds Route53/VPC endpoint roles in the network account—TC-04 builds on this baseline.

## Flow

```
 OCM / ROSA CLI                    AWS IAM (cluster account)
      │                                   │
      │ rosa create account-roles         │  Installer, Worker, Support roles
      │ rosa create oidc-config           │  S3 discovery + OIDC provider
      │ rosa create operator-roles        │  8× operator roles (hosted-cp)
      └──────────────────────────────────►│
```

## Prerequisites

- TC-01 prerequisites complete (`01-prerequisites.md`).
- `PREFIX` or cluster name chosen (≤15 chars for cluster name; prefix can be longer).
- `rosa verify quota --region <region>` (optional but recommended).

```bash
export AWS_DEFAULT_REGION="us-east-1"
export PREFIX="${CLUSTER_NAME}-account"
export OPERATOR_PREFIX="${CLUSTER_NAME}-operator"
```

## Steps

1. Create hosted-CP account roles:

   ```bash
   rosa create account-roles --prefix "${PREFIX}" --hosted-cp --mode auto --yes \
     --region "${AWS_DEFAULT_REGION}"
   ```

2. Create OIDC configuration:

   ```bash
   rosa create oidc-config --mode auto --yes --region "${AWS_DEFAULT_REGION}"
   ```

   Capture `OIDC_CONFIG_ID` from output or:

   ```bash
   export OIDC_CONFIG_ID="$(rosa list oidc-config -o json | jq -r '.[0].id')"
   ```

3. Create OIDC provider (if not created by prior step):

   ```bash
   rosa create oidc-provider --oidc-config-id "${OIDC_CONFIG_ID}" --mode auto --yes \
     --region "${AWS_DEFAULT_REGION}"
   ```

4. Create operator roles for HCP:

   ```bash
   INSTALLER_ROLE_ARN="$(aws iam list-roles --query "Roles[?contains(RoleName, '${PREFIX}') && contains(RoleName, 'Installer')].Arn" --output text)"
   rosa create operator-roles --prefix "${OPERATOR_PREFIX}" --oidc-config-id "${OIDC_CONFIG_ID}" \
     --installer-role-arn "${INSTALLER_ROLE_ARN}" --hosted-cp --mode auto --yes \
     --region "${AWS_DEFAULT_REGION}"
   ```

5. List resources:

   ```bash
   rosa list account-roles --prefix "${PREFIX}"
   rosa list operator-roles --prefix "${OPERATOR_PREFIX}"
   rosa list oidc-config
   rosa list oidc-provider
   ```

## Expected output

- Each `rosa create` subcommand completes with ARNs printed.
- `rosa list operator-roles` shows eight operator roles for hosted CP.
- `aws iam list-open-id-connect-providers` includes a provider URL matching the OIDC config.

## Success criteria

```bash
rosa list account-roles --prefix "${PREFIX}" | grep -E 'Installer|Worker|Support'
rosa list operator-roles --prefix "${OPERATOR_PREFIX}" | wc -l   # expect 8 role lines minimum
aws iam list-open-id-connect-providers --output text | grep -q oidc
```

All commands exit 0.

## Failure signals

- `InvalidParameter`: wrong `--hosted-cp` flag on classic roles.
- `EntityAlreadyExists`: prefix collision—pick new prefix or delete stale roles.
- Operator role create fails on `installer-role-arn` → account roles not created or wrong ARN.
- SCP denies `iam:CreateRole` → org policy block.

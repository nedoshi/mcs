# ROSA HCP Validation — Prerequisites

**Provenance:** Inferred from repo (`hcp-ansible`, `tf-rosa`, Shared VPC tutorial). **Not** copied from Google Docs.

**Source references:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Validates local tooling, Red Hat OCM/ROSA entitlements, AWS credentials, and quotas before any HCP install test case runs.

## Why this matters

- QE lab bring-up fails late when `rosa` or STS roles are missing—burning 45–90 minutes per failed install.
- Customers run the same checks before production cutover windows.
- Shared VPC tests need two AWS profiles; catching profile drift early avoids cross-account IAM debugging.

## Architecture / flow

```
 Engineer workstation
 ┌──────────────────────────────────────┐
 │ rosa CLI ──► OCM API (RHCS)          │
 │ aws CLI  ──► STS / IAM (cluster acct) │
 │ oc       ──► Cluster API (post-install) │
 └──────────────────────────────────────┘
          │
          ▼
   ROSA HCP install (HostedCluster + workers)
```

## Prerequisites

| Requirement | Verify |
|-------------|--------|
| ROSA enabled on Red Hat org | `rosa verify permissions --hosted-cp` |
| Billing account ID | Console → Account settings |
| AWS admin or scoped IAM for STS role creation | `aws sts get-caller-identity` |
| Region with HCP versions | `rosa list versions --channel-group stable --hosted-cp -r <region>` |
| Tools | `rosa version`, `aws --version`, `oc version`, `jq` |

### Environment variables

```bash
export ROSA_TOKEN="<token>"
export AWS_DEFAULT_REGION="us-east-1"
export CLUSTER_NAME="rosa-hcp-qe"   # max 15 chars
export BILLING_ACCOUNT_ID="<billing>"
```

### Optional Ansible gate

```bash
cd cluster-creation-cloud/aws/hcp-ansible
ansible-playbook playbooks/validate_prerequisites.yml
```

## Steps

1. Log in to OCM:

   ```bash
   rosa login --token="${ROSA_TOKEN}"
   rosa whoami
   ```

2. Confirm AWS identity:

   ```bash
   aws sts get-caller-identity
   ```

3. Verify hosted-CP permissions:

   ```bash
   rosa verify permissions --hosted-cp --region "${AWS_DEFAULT_REGION}"
   ```

4. List installable versions:

   ```bash
   rosa list versions --channel-group stable --hosted-cp -r "${AWS_DEFAULT_REGION}" | head
   ```

5. (Shared VPC tests only) Confirm second account profile:

   ```bash
   export AWS_PROFILE=shared-vpc-account
   aws sts get-caller-identity
   export AWS_PROFILE=cluster-account
   aws sts get-caller-identity
   ```

## Expected output

- `rosa whoami` prints org, user, and linked AWS account (if configured).
- `rosa verify permissions --hosted-cp` exits 0 with no blocking errors.
- `aws sts get-caller-identity` returns Account, Arn, UserId JSON.

## Success criteria

| Check | Command | Pass |
|-------|---------|------|
| OCM auth | `rosa whoami` | Exit 0 |
| HCP permissions | `rosa verify permissions --hosted-cp` | Exit 0 |
| AWS auth | `aws sts get-caller-identity` | Valid JSON |
| Version available | `rosa list versions ... --hosted-cp` | Target version listed |

## Failure signals

- `Error: Not logged in` → refresh `ROSA_TOKEN`.
- `AccessDenied` on `aws sts` → fix credentials or SSO session.
- `rosa verify permissions` lists missing IAM actions → run account/operator role creation (TC-01) or fix SCPs.
- No HCP versions in region → pick another region or channel.

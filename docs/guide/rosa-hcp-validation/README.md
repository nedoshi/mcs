---
date: '2026-09-17'
title: 'ROSA HCP Validation — Master Checklist'
tags: ["ROSA", "ROSA HCP", "HyperShift", "Validation", "QE"]
authors:
  - Red Hat Cloud Experts
related_guides:
  - source-doc-reconciliation.md
  - 01-prerequisites.md
  - gap-analysis.md
  - validation-report.md
---

# ROSA HCP Validation — Master Checklist

Validation runbook for **Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP)** clusters. Structure mirrors [ARO HCP validation](../aro-hcp-validation/README.md).

> **Source docs:** QE test plans live in Google Docs (see links below). They were **not machine-readable** when this folder was generated. Every procedure file states **Inferred from repo** until you reconcile per [source-doc-reconciliation.md](source-doc-reconciliation.md).

## Source Google Docs (authoritative QE catalog)

| ID | Link |
|----|------|
| Doc A | [ROSA HCP test plan (1ds3_F0GNj4…)](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) |
| Doc B | [ROSA HCP test plan (193yRGltNtK2…)](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit) |

## Scope

- STS account/operator roles and OIDC for `--hosted-cp`
- Public and private cluster install paths
- Shared VPC (network account + cluster account)
- External authentication (install-time, irreversible)
- Post-install health, DNS, IAM, networking
- Day-2 smoke (operators, sample app, scaling)

## Quick start

```bash
# Optional: Ansible prerequisite gate
cd cluster-creation-cloud/aws/hcp-ansible
ansible-playbook playbooks/validate_prerequisites.yml

export ROSA_TOKEN="<from console.redhat.com/openshift/token/rosa>"
rosa login --token="${ROSA_TOKEN}"
rosa whoami

export CLUSTER_NAME="<cluster>"
export AWS_DEFAULT_REGION="<region>"
export KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}"
rosa create admin --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"  # if needed
```

## Runbook index

| ID | Document | Primary repo reference |
|----|----------|------------------------|
| — | [01-prerequisites.md](01-prerequisites.md) | `hcp-ansible`, ROSA CLI docs |
| TC-01 | [02-sts-account-operator-roles.md](02-sts-account-operator-roles.md) | `rosa create account-roles --hosted-cp` |
| TC-02 | [03-public-cluster-lifecycle.md](03-public-cluster-lifecycle.md) | `hcp-ansible/roles/rosa_hcp_public` |
| TC-03 | [04-private-cluster-lifecycle.md](04-private-cluster-lifecycle.md) | `hcp-ansible/roles/rosa_hcp_private` |
| TC-04 | [05-shared-vpc-install.md](05-shared-vpc-install.md) | [Shared VPC tutorial](../../../cluster-creation-cloud/aws/docs/hcp-shared-vpc/ROSA-HCP-SharedVPC-Installation-Tutorial.md) |
| TC-05 | [06-external-authentication.md](06-external-authentication.md) | `tf-rosa/examples/external-auth.tfvars.example` |
| TC-06 | [07-post-install-cluster-review.md](07-post-install-cluster-review.md) | [Cluster review guide](../../troubleshooting/ROSA/rosa_cluster_review_guide.md) |
| TC-07 | [08-machine-pools-multi-az.md](08-machine-pools-multi-az.md) | `tf-rosa/examples/multi-az.tfvars.example` |
| TC-08 | [09-identity-providers.md](09-identity-providers.md) | `rosa create idp`, multiple-IDP example |
| TC-09 | [10-private-ingress-connectivity.md](10-private-ingress-connectivity.md) | [ROSA HCP troubleshooting](../../troubleshooting/ROSA/ROSA_HCP_Troubleshooting_Guide.md) |
| TC-10 | [11-day2-smoke-tests.md](11-day2-smoke-tests.md) | ARO HCP ST-* pattern |
| — | [gap-analysis.md](gap-analysis.md) | ARO vs ROSA HCP |
| — | [validation-report.md](validation-report.md) | Execution log |

## Pass/fail matrix

Record during live runs. Replace TC IDs with Google Doc IDs after [reconciliation](source-doc-reconciliation.md).

| ID | Test | Procedure | Result | Date | Notes |
|----|------|-----------|--------|------|-------|
| TC-01 | STS roles + OIDC bootstrap | [02-sts-account-operator-roles.md](02-sts-account-operator-roles.md) | | | |
| TC-02 | Public HCP install → ready | [03-public-cluster-lifecycle.md](03-public-cluster-lifecycle.md) | | | |
| TC-03 | Private HCP install → ready | [04-private-cluster-lifecycle.md](04-private-cluster-lifecycle.md) | | | |
| TC-04 | Shared VPC install | [05-shared-vpc-install.md](05-shared-vpc-install.md) | | | |
| TC-05 | External auth at create | [06-external-authentication.md](06-external-authentication.md) | | | |
| TC-06 | Cluster review (DNS/IAM/net) | [07-post-install-cluster-review.md](07-post-install-cluster-review.md) | | | |
| TC-07 | Machine pools / multi-AZ | [08-machine-pools-multi-az.md](08-machine-pools-multi-az.md) | | | |
| TC-08 | IDP login (console + oc) | [09-identity-providers.md](09-identity-providers.md) | | | |
| TC-09 | Private ingress behavior | [10-private-ingress-connectivity.md](10-private-ingress-connectivity.md) | | | |
| TC-10 | Day-2 smoke | [11-day2-smoke-tests.md](11-day2-smoke-tests.md) | | | |

**Result values:** `PASS` | `FAIL` | `BLOCKED` | `PENDING`

## Related repository documentation

| Topic | Path |
|-------|------|
| Ansible install automation | [cluster-creation-cloud/aws/hcp-ansible/](../../../cluster-creation-cloud/aws/hcp-ansible/) |
| Shared VPC tutorial | [ROSA-HCP-SharedVPC-Installation-Tutorial.md](../../../cluster-creation-cloud/aws/docs/hcp-shared-vpc/ROSA-HCP-SharedVPC-Installation-Tutorial.md) |
| Troubleshooting | [ROSA_HCP_Troubleshooting_Guide.md](../../troubleshooting/ROSA/ROSA_HCP_Troubleshooting_Guide.md) |
| External auth (Entra) | [ROSA-HCP-External-auth.md](../../troubleshooting/ROSA/ROSA-HCP-External-auth.md) |
| Terraform ROSA HCP | [cluster-creation-cloud/aws/tf-rosa/](../../../cluster-creation-cloud/aws/tf-rosa/) |
| Use-case map | [use-cases.md](../../../cluster-creation-cloud/aws/docs/use-cases.md) |

## Cross-links

- [ARO HCP validation](../aro-hcp-validation/README.md) (parallel checklist for Azure HCP)
- [Cross-cloud DR ARO ↔ ROSA HCP](../cross-cloud-dr-aro-rosa/README.md)

# Prerequisites — ROSA use-case validation

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) · [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) (cluster-ready assumptions).

## Summary

Confirms tooling, OCM/ROSA access, a **ready** cluster, and which **cluster profile** (standard vs bare metal) applies before UC/ING runbooks.

## Why this matters

- Use-case tests fail immediately if the cluster is not `ready` or `oc` lacks admin-equivalent rights.
- GPU and OpenShift Virtualization scenarios require **bare metal** workers—running them on a standard VM-only HCP lab wastes time.
- ALB and IRSA tests need AWS CLI credentials in the **cluster AWS account** with permissions to create ACM certs, IAM roles, or ELB resources.

## Architecture

```
 Workstation                    AWS / Red Hat
 ┌─────────────────┐           ┌──────────────────────────┐
 │ rosa → OCM      │──────────►│ ROSA HCP (ready)         │
 │ oc   → API      │──────────►│ Workers (VM or metal)    │
 │ aws  → IAM/ELB  │──────────►│ S3, ACM, ELB, EBS, …     │
 └─────────────────┘           └──────────────────────────┘
```

## Prerequisites

| Requirement | Verify |
|-------------|--------|
| ROSA cluster exists and is `ready` | `rosa describe cluster -c "${CLUSTER_NAME}"` |
| `oc` access | `oc whoami`, `oc get nodes` |
| AWS CLI (same account as cluster) | `aws sts get-caller-identity` |
| Tools | `rosa`, `oc`, `aws`, `jq`, `curl` |
| Billing / ROSA entitlement | `rosa whoami` |

### Environment variables

```bash
export ROSA_TOKEN="<token>"
export AWS_DEFAULT_REGION="us-east-1"
export CLUSTER_NAME="<cluster>"
export KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}"
```

### Cluster profiles

| Profile | Worker example | Required for |
|---------|----------------|--------------|
| **Standard** | `m5.xlarge`, `m6i.large`, … | UC-01–04, UC-06, ING-01, ING-02, ING-06 |
| **Bare metal** | `m5zn.metal`, `m5.metal` + IMDSv2 | UC-05, UC-07, ING-05 |

Check profile:

```bash
oc get nodes -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type
```

### Install a cluster (if needed)

- Ansible: [hcp-ansible/README.md](../../../cluster-creation-cloud/aws/hcp-ansible/README.md)
- Terraform: [tf-rosa/](../../../cluster-creation-cloud/aws/tf-rosa/)

## Steps

1. Log in to OCM and confirm cluster state:

   ```bash
   rosa login --token="${ROSA_TOKEN}"
   rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq '{name:.name, state:.state, region:.region, api:.api.url}'
   ```

2. Obtain kubeconfig if missing:

   ```bash
   rosa create admin --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"
   ```

3. Verify cluster health baseline:

   ```bash
   oc get co --no-headers | awk '$2!="True" && $3!="True" {print}'
   oc get nodes
   ```

4. Record profile for downstream tests (standard vs bare metal).

## Expected output

- Cluster `state`: `ready`
- All ClusterOperators `Available=True` (or documented exceptions)
- Nodes `Ready`

## Success criteria

| Check | Pass |
|-------|------|
| `rosa describe cluster` state | `ready` |
| `oc get co` | No Degraded operators required for your test scope |
| Profile documented | Standard and/or bare metal noted in [validation-report.md](validation-report.md) |

## Failure signals

- Cluster `installing` / `error` → finish platform install before use-case tests.
- `oc` unauthorized → refresh admin kubeconfig or RBAC.
- UC-05/UC-07/ING-05 planned but nodes are not metal → mark **BLOCKED**, do not fail the platform.

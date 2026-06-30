# OpenShift UPI on AWS — Terraform

Terraform automation for [User Provisioned Infrastructure (UPI)](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-user-infra.html) OpenShift installs on AWS.

Based on the [OpenShift installer UPI CloudFormation templates](https://github.com/openshift/installer/tree/master/upi/aws) and the modular layout from [openshift4-upi-deployer](https://github.com/kenmoini/openshift4-upi-deployer/tree/master/infrastructure/aws-terraform).

## What This Provisions

| Module | Resources |
|--------|-----------|
| `network` | VPC, public/private subnets, IGW, NAT gateways, optional S3/EC2 VPC endpoints |
| `load_balancer` | Internal + external NLBs, target groups for API (6443) and machine config (22623) |
| `dns` | Private Route53 zone, `api` / `api-int` records; optional public `api` record |
| `security` | Control plane and worker security groups (OCP-required ports) |
| `iam` | Master, worker, and bootstrap instance profiles |
| `cluster` *(optional)* | `openshift-install`, bootstrap/control-plane EC2, NLB registrations, install wait |

## Prerequisites

- Terraform >= 1.5, AWS CLI, `curl`, `jq`
- AWS credentials with permissions to create VPC, EC2, ELB, Route53, IAM, S3
- Route53 public hosted zone for `base_domain` (when `create_public_dns_records = true`)
- Pull secret from https://console.redhat.com/openshift/install/pull-secret (for full install)
- Run from Linux/macOS (or a bastion in the target VPC)

## Quick Start

### 1. Infrastructure only

```bash
cd cluster-creation-onprem/ocp/aws-infra/terraform-upi
cp examples/standard.tfvars.example terraform.tfvars
# edit cluster_name, base_domain, public_hosted_zone_id

terraform init
terraform plan
terraform apply
```

Review outputs (`vpc_id`, NLB ARNs, security group IDs, instance profiles) — these match what the OpenShift UPI docs require before generating ignition configs.

### 2. Full cluster install

Set in `terraform.tfvars`:

```hcl
enable_cluster_install     = true
openshift_pull_secret_path = "./openshift_pull_secret.json"
```

Re-apply. Terraform will:

1. Download `openshift-install` for the latest stable release
2. Generate manifests and ignition configs
3. Launch bootstrap + control plane nodes
4. Register node IPs with NLB target groups
5. Wait for bootstrap and install completion

After install, remove the bootstrap node manually:

```bash
# Get bootstrap instance ID from output or EC2 console, then:
aws ec2 terminate-instances --instance-ids i-xxxxxxxx
```

Credentials land in `./output/<infrastructure_name>/auth/` (`kubeconfig`, `kubeadmin-password`).

## Architecture

```
Internet
    │
    ▼
[External NLB :6443] ──► api.<cluster>.<domain> (public Route53)
    │
[Public subnets] ─ NAT ─► [Private subnets]
                              │
                    [Internal NLB :6443/:22623]
                              │
              bootstrap + control-plane EC2
                              │
                    [Private Route53 zone]
                    api-int / api (internal)
```

## Variables

See [`variables.tf`](variables.tf). Key inputs:

| Variable | Description |
|----------|-------------|
| `cluster_name` | Cluster DNS label (max 27 chars) |
| `base_domain` | Parent DNS zone (e.g. `example.com`) |
| `enable_cluster_install` | Run openshift-install + launch nodes (default `false`) |
| `az_count` | 1–3 AZs (use 3 for HA) |
| `network_type` | Default `OVNKubernetes` (OCP 4.12+) |

## Two-Stage Workflow (Recommended)

1. **`enable_cluster_install = false`** — provision and validate networking, LBs, DNS, IAM
2. Generate/test ignition manually if needed using outputs
3. **`enable_cluster_install = true`** — run installer automation

This mirrors the staged folders in the reference deployer (`1_private_network` → `8_postinstall`).

## Worker MachineSets

Workers are **not** EC2 instances created at install time — the Machine API provisions them from MachineSets after the control plane is up.

| Mode | Behavior |
|------|----------|
| `enable_cluster_install = true`, `use_worker_machinesets = true` (default) | One MachineSet per AZ generated automatically; see `worker` variable in `variables.tf` |
| `enable_cluster_install = false` | Apply MachineSets manually post-install using [`examples/worker-machineset.yaml.example`](examples/worker-machineset.yaml.example) |

```hcl
use_worker_machinesets = true
worker = {
  count         = 3
  instance_type = "m6i.large"
  disk_gb       = 120
}
```

Verify after install:

```bash
oc get machinesets,machines,nodes -n openshift-machine-api
oc get nodes -l node-role.kubernetes.io/worker=
```

Full details — scaling, manual manifests, troubleshooting: **[UPI Installation Guide — Worker MachineSets](../upi-installation-guide.md#worker-machinesets)**.

## References

- [OpenShift UPI on AWS](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-user-infra.html)
- [openshift/installer upi/aws](https://github.com/openshift/installer/tree/master/upi/aws)
- [kenmoini/openshift4-upi-deployer](https://github.com/kenmoini/openshift4-upi-deployer/tree/master/infrastructure/aws-terraform)

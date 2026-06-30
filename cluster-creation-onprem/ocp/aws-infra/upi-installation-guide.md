# OpenShift UPI Installation on AWS Infrastructure

Guide for installing self-managed OpenShift Container Platform on AWS using User Provisioned Infrastructure (UPI).

> UPI requires you to provision AWS resources before (or alongside) running the OpenShift installer. This repo includes Terraform automation for that workflow.

## Terraform Automation

Use the Terraform in [`terraform-upi/`](terraform-upi/):

```bash
cd terraform-upi
cp examples/standard.tfvars.example terraform.tfvars
# edit cluster_name, base_domain, public_hosted_zone_id

terraform init
terraform apply
```

See [`terraform-upi/README.md`](terraform-upi/README.md) for the full two-stage workflow (infrastructure first, then `enable_cluster_install = true`).

The layout follows the staged modules from [openshift4-upi-deployer](https://github.com/kenmoini/openshift4-upi-deployer/tree/master/infrastructure/aws-terraform) and aligns with the official [OpenShift UPI CloudFormation templates](https://github.com/openshift/installer/tree/master/upi/aws).

## When to Use UPI

Use UPI when:

- You need complete control over AWS infrastructure
- You have strict networking or security requirements
- You are integrating with an existing VPC
- You need air-gapped or disconnected installations
- IPI does not support your configuration

## High-Level Steps

1. **Provision infrastructure** — VPC, subnets, NLBs, Route53, security groups, IAM (`terraform apply`)
2. **Generate ignition configs** — automated when `enable_cluster_install = true`, or manual via `openshift-install`
3. **Launch bootstrap and control plane** — EC2 instances with ignition user-data
4. **Register NLB targets** — bootstrap first, then control plane nodes
5. **Wait for bootstrap complete** — `openshift-install wait-for bootstrap-complete`
6. **Remove bootstrap node** — terminate bootstrap EC2 and deregister from NLBs
7. **Wait for install complete** — `openshift-install wait-for install-complete`
8. **Configure ingress DNS** — router/apps load balancer records post-install

## Manual Install (Without Terraform Cluster Module)

If you only run infrastructure Terraform (`enable_cluster_install = false`), use the outputs and follow:

- [Official OpenShift UPI on AWS Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-user-infra.html)
- [AWS CloudFormation Templates](https://github.com/openshift/installer/tree/master/upi/aws)

Key outputs needed for `install-config.yaml` / ignition customization:

- `infrastructure_name`, `vpc_id`, `private_subnet_ids`
- `internal_api_target_group_arn`, `internal_service_target_group_arn`, `external_api_target_group_arn`
- `master_security_group_id`, `worker_security_group_id`
- `master_instance_profile`, `worker_instance_profile`
- `private_hosted_zone_id`, `api_server_url`

## Worker MachineSets

UPI does not create worker EC2 instances during install. Workers are provisioned **after** the control plane is up, via **MachineSets** in the `openshift-machine-api` namespace. The Machine API controller creates EC2 instances using the cluster's AWS credentials and the worker IAM instance profile from Terraform.

### Automated (Terraform cluster module)

When `enable_cluster_install = true` and `use_worker_machinesets = true` (default), Terraform:

1. Sets `compute[0].replicas` in `install-config.yaml` to your worker count (so the scheduler expects workers)
2. Removes installer-generated worker MachineSets (they reference installer-owned subnets/SGs)
3. Writes one custom MachineSet per AZ under `output/<infrastructure_name>/openshift/`
4. Includes those manifests in `openshift-install create ignition-configs`

Configure in `terraform.tfvars`:

```hcl
use_worker_machinesets = true

worker = {
  count         = 3          # total workers across all AZs
  instance_type = "m6i.large"
  disk_gb       = 120
}
```

Replicas are split evenly: `floor(worker.count / az_count)` per MachineSet. With 3 workers and 3 AZs, each MachineSet gets `replicas: 1`.

Generated manifests match [`terraform-upi/modules/cluster/templates/worker-machineset.yaml.tftpl`](terraform-upi/modules/cluster/templates/worker-machineset.yaml.tftpl).

### Verify workers

After `install-complete`, workers may take several minutes to appear:

```bash
export KUBECONFIG=./output/<infrastructure_name>/auth/kubeconfig

# MachineSets and Machines
oc get machinesets -n openshift-machine-api
oc get machines -n openshift-machine-api

# Should reach Ready once EC2 instances join
oc get nodes -l node-role.kubernetes.io/worker=

# Machine API controller logs if stuck
oc logs -n openshift-machine-api -l api=clusterapi --tail=50
```

Expected flow: MachineSet → Machine → EC2 instance → Node `Ready`.

Common checks:

```bash
# AWS credentials secret (created by installer)
oc get secret aws-cloud-credentials -n openshift-machine-api

# Pending machines show failure reason
oc describe machine -n openshift-machine-api <name>
```

### Scale workers

**Via Terraform** — change `worker.count`, re-run `terraform apply`. This regenerates ignition/manifests; for a running cluster, prefer `oc` scaling instead.

**Via oc (recommended on running cluster):**

```bash
# Scale a specific AZ MachineSet
oc scale machineset INFRASTRUCTURE_NAME-worker-us-east-1a \
  -n openshift-machine-api --replicas=2

# Or patch all MachineSets
oc get machineset -n openshift-machine-api -o name | \
  xargs -I{} oc scale {} -n openshift-machine-api --replicas=2
```

Scale down by reducing replicas; the controller terminates excess EC2 instances.

### Manual MachineSets (infra-only Terraform)

If you ran Terraform with `enable_cluster_install = false`, create MachineSets **after** the cluster is installed and you have a working `kubeconfig`.

1. Gather Terraform outputs:

```bash
terraform output infrastructure_name
terraform output worker_instance_profile
terraform output worker_security_group_id
terraform output private_subnet_ids
terraform output rhcos_ami
```

2. Copy the example manifest:

```bash
cp terraform-upi/examples/worker-machineset.yaml.example worker-machineset.yaml
# Edit: one file per AZ, each with a different subnet_id and availabilityZone
```

3. Apply:

```bash
oc apply -f worker-machineset.yaml
```

Create **one MachineSet per AZ**, each pinned to a private subnet from `private_subnet_ids`. The worker security group is selected by tag `Name = <infrastructure_name>-worker`.

> **Note:** The cluster must already have the `aws-cloud-credentials` secret and `worker-user-data` secret in `openshift-machine-api` (created by `openshift-install`). Manual MachineSets only work after a normal UPI install — not on a blank cluster.

### Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Machine `Provisioning` forever | Wrong subnet, SG, or instance profile; check `oc describe machine` events |
| `InvalidInstanceProfile.NotFound` | `iamInstanceProfile.id` doesn't match Terraform `worker_instance_profile` output |
| `InsufficientInstanceCapacity` | Try a different instance type or AZ |
| Nodes not `Ready` | Check EC2 instance system log; verify NAT/endpoints allow registry pulls |
| No workers at all | MachineSets missing or `replicas: 0`; confirm `use_worker_machinesets = true` was set before install |

Machine API needs the **master** IAM role permissions (ELB, EC2, etc.) — already provisioned by the Terraform `iam` module. Workers use a minimal read-only EC2 policy.

## Alternatives

- [IPI installation](ipi-installation-guide.md) — faster if you do not need custom infrastructure
- [ROSA](../../../cluster-creation-cloud/aws/) — fully managed OpenShift on AWS

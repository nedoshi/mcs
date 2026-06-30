# ROSA HCP Shared VPC — IAM Roles and Trust Policies

Complete reference for the IAM roles, trust policies, and permissions required
to deploy a ROSA HCP cluster in a shared VPC configuration.

## Overview

ROSA HCP shared VPC requires IAM roles in **two categories**:

1. **Shared VPC roles** (created by Terraform in the VPC account) — assumed by ROSA
   to manage Route53 records and VPC endpoints in the shared VPC account.
2. **ROSA roles** (created by `rosa` CLI in the cluster account) — used by the
   ROSA service and cluster operators. Some need additional inline policies for
   shared VPC.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Shared VPC Account                               │
│                                                                          │
│  route53-role ←──── assumed by Installer Role, ingress-operator          │
│    ├── Trust: Installer Role ARN + account root                          │
│    └── Policy: ROSASharedVPCRoute53Policy (AWS managed)                  │
│                                                                          │
│  vpc-endpoint-role ←──── assumed by Installer Role, control-plane-op     │
│    ├── Trust: Installer Role ARN + account root                          │
│    └── Policy: ROSASharedVPCEndpointPolicy (AWS managed)                 │
├──────────────────────────────────────────────────────────────────────────┤
│                         Cluster Account                                  │
│                                                                          │
│  <prefix>-HCP-ROSA-Installer-Role (rosa CLI)                            │
│    └── Can assume shared VPC roles via specific trust                    │
│                                                                          │
│  <prefix>-kube-system-control-plane-operator (rosa CLI)                  │
│    └── Inline policy: sts:AssumeRole on shared VPC roles (Terraform)     │
│                                                                          │
│  <prefix>-openshift-ingress-operator-cloud-credentials (rosa CLI)        │
│    └── Inline policy: sts:AssumeRole on shared VPC roles (Terraform)     │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Shared VPC Roles (Terraform-managed)

### 1. Route53 Role (`<cluster>-route53-role`)

Allows ROSA to manage DNS records in the shared VPC's private hosted zones.

**Trust Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::<CLUSTER_ACCOUNT_ID>:role/<PREFIX>-HCP-ROSA-Installer-Role",
          "arn:aws:iam::<CLUSTER_ACCOUNT_ID>:root"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions Policy:** AWS managed `ROSASharedVPCRoute53Policy`
(`arn:aws:iam::aws:policy/ROSASharedVPCRoute53Policy`)

Key permissions:
- `route53:GetHostedZone`, `route53:ListHostedZones`, `route53:ListResourceRecordSets` (read)
- `route53:ChangeResourceRecordSets` (restricted to `*.hypershift.local`,
  `*.openshiftapps.com`, and related patterns)
- `route53:ChangeTagsForResource`
- `tag:GetResources`

**Assumed by:**
| Principal | Purpose |
|-----------|---------|
| Installer Role | Initial DNS setup during cluster creation |
| ingress-operator | Ongoing DNS record management for app routes |

---

### 2. VPC Endpoint Role (`<cluster>-vpc-endpoint-role`)

Allows ROSA to create and manage PrivateLink VPC endpoints for the HCP
control plane connection.

**Trust Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::<CLUSTER_ACCOUNT_ID>:role/<PREFIX>-HCP-ROSA-Installer-Role",
          "arn:aws:iam::<CLUSTER_ACCOUNT_ID>:root"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions Policy:** AWS managed `ROSASharedVPCEndpointPolicy`
(`arn:aws:iam::aws:policy/ROSASharedVPCEndpointPolicy`)

Key permissions:
- `ec2:CreateVpcEndpoint`, `ec2:ModifyVpcEndpoint`, `ec2:DeleteVpcEndpoints`
- `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup` (with `red-hat-managed` tag condition)
- Security group ingress/egress rules (with `red-hat-managed` tag condition)
- `ec2:CreateTags` (restricted to CreateVpcEndpoint and CreateSecurityGroup actions)

**Assumed by:**
| Principal | Purpose |
|-----------|---------|
| Installer Role | Initial VPC endpoint creation |
| control-plane-operator | Ongoing VPC endpoint lifecycle management |

---

## Trust Policy Design

Both shared VPC roles use a **dual-principal trust policy**:

1. **Installer Role ARN** (specific trust) — The installer role can assume the
   shared VPC roles without needing an `sts:AssumeRole` policy on its own side.
   This is required because the installer role is an account-level role managed
   by `rosa` CLI and we don't add inline policies to it.

2. **Account root** (broad trust) — Allows any IAM entity in the cluster account
   to assume the role, provided the entity has an `sts:AssumeRole` policy granting
   access. This enables the operator roles (which get an inline policy from
   Terraform) to assume the shared VPC roles.

**Why not ExternalId?** OCM (the ROSA management service) does not pass an
`sts:ExternalId` when assuming roles on behalf of the cluster. An ExternalId
condition will cause all AssumeRole calls from OCM to be denied.

**Why not just account root?** When a trust policy only lists `account:root`,
every caller must have an explicit `sts:AssumeRole` permission in its own IAM
policy. The installer role (managed by `rosa` CLI) does not have this, so it
must be named specifically in the trust policy.

---

## Operator Role Inline Policies (Terraform-managed)

The `rosa create operator-roles` command does not grant `sts:AssumeRole` on
shared VPC roles. Terraform adds an inline policy `AssumeSharedVPCRoles` to the
operator roles that need it.

### control-plane-operator

Role name: `<prefix>-kube-system-control-plane-operator`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::<VPC_ACCOUNT_ID>:role/<cluster>-vpc-endpoint-role",
        "arn:aws:iam::<VPC_ACCOUNT_ID>:role/<cluster>-route53-role"
      ]
    }
  ]
}
```

### ingress-operator

Role name: `<prefix>-openshift-ingress-operator-cloud-credentials`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::<VPC_ACCOUNT_ID>:role/<cluster>-vpc-endpoint-role",
        "arn:aws:iam::<VPC_ACCOUNT_ID>:role/<cluster>-route53-role"
      ]
    }
  ]
}
```

---

## ROSA CLI Roles (not managed by Terraform)

These roles are created by `rosa` CLI and looked up via Terraform data sources.
They are listed here for completeness.

### Account Roles

Created by: `rosa create account-roles --prefix <PREFIX> --hosted-cp`

| Role | Purpose |
|------|---------|
| `<prefix>-HCP-ROSA-Installer-Role` | Cluster installation and initial setup |
| `<prefix>-HCP-ROSA-Support-Role` | Red Hat SRE support access |
| `<prefix>-HCP-ROSA-Worker-Role` | Worker node instance profile |

### Operator Roles

Created by: `rosa create operator-roles --prefix <PREFIX> --hosted-cp`

| Role | Namespace | Purpose |
|------|-----------|---------|
| `<prefix>-kube-system-capa-controller-manager` | kube-system | Cluster API AWS controller |
| `<prefix>-kube-system-control-plane-operator` | kube-system | HCP control plane management |
| `<prefix>-kube-system-kms-provider` | kube-system | KMS encryption for etcd |
| `<prefix>-kube-system-kube-controller-manager` | kube-system | Kubernetes controller manager |
| `<prefix>-openshift-cloud-network-config-controller-cloud-credential` | openshift-cloud-network-config-controller | Cloud network configuration |
| `<prefix>-openshift-cluster-csi-drivers-ebs-cloud-credentials` | openshift-cluster-csi-drivers | EBS CSI driver |
| `<prefix>-openshift-image-registry-installer-cloud-credentials` | openshift-image-registry | Image registry S3 backend |
| `<prefix>-openshift-ingress-operator-cloud-credentials` | openshift-ingress-operator | Ingress DNS management |

---

## Route53 Private Hosted Zones

ROSA HCP validates that hosted zone names match specific patterns.

| Zone | Name pattern | Example |
|------|-------------|---------|
| HCP internal | `<cluster_name>.hypershift.local` | `demo1.hypershift.local` |
| Ingress | `rosa.<cluster_name>.<base_dns_domain>` | `rosa.demo1.xxxx.p3.openshiftapps.com` |

The `base_dns_domain` must be reserved via `rosa create dns-domain --hosted-cp`
and must be under `p3.openshiftapps.com` (the HCP architecture parent for AWS).

---

## IAM Propagation

AWS IAM changes (trust policies, inline policies, managed policy attachments)
are **eventually consistent**. Changes can take 5-15 seconds to propagate
globally. ROSA validates IAM access during cluster creation and will reject the
request if policies haven't propagated yet.

**Mitigation:** Apply shared VPC resources and operator policies in a separate
Terraform stage (Step 1a), wait 15 seconds, then apply the cluster (Step 1b).

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Domain 'X' is incompatible with architecture parent domain 'p3.openshiftapps.com'` | base_dns_domain is not under p3.openshiftapps.com | Run `rosa create dns-domain --hosted-cp` to get a p3 domain |
| `Attribute 'dns.base_domain' is mandatory on shared VPC clusters` | base_dns_domain is empty | Set base_dns_domain in tfvars |
| `failed to find dns domain 'X' for organization` | Domain not registered with OCM | Run `rosa create dns-domain --hosted-cp` |
| `Failed to assume role ... AccessDenied` (Installer Role) | Trust policy doesn't include installer role ARN | Add installer role ARN to trust policy |
| `Failed to assume role ... AccessDenied` (operator role) | Operator role missing sts:AssumeRole policy | Add AssumeSharedVPCRoles inline policy |
| `not authorized to access hosted zone` | Missing Route53 permissions | Use AWS managed ROSASharedVPCRoute53Policy |
| `Hosted zone name should match the pattern` | Zone name doesn't follow ROSA naming convention | Use `<cluster>.hypershift.local` and `rosa.<cluster>.<base_domain>` |
| `HostedZoneNotEmpty` on destroy | Leftover DNS records from failed cluster attempts | Clear non-NS/SOA records before destroying zone |

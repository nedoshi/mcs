# ROSA security considerations

Consolidated from [rosa-llm-driven-deployment](https://github.com/manu-joy/rosa-llm-driven-deployment) and Red Hat / AWS guidance. Maps to folders under `cluster-creation/aws/`.

## Network security

| Mode | Pattern | Folder |
|------|---------|--------|
| Public API + ingress | Dev / test | `tf-rosa/examples/standard.tfvars.example`, `examples/rosa-hcp-public/` |
| Private API | Production | `tf-rosa/examples/private-cluster.tfvars.example`, `examples/rosa-hcp-private/` |
| Zero egress | Highest isolation | `cluster-zero-egress/` (dedicated VPC + endpoints) |
| Shared VPC | Enterprise networking | `tf-rosa/examples/rosa-hcp-private-shared-vpc/`, `docs/hcp-shared-vpc/` |

- ROSA HCP requires **public and private subnets** when using an existing VPC (`aws_subnet_ids`).
- Use bastion or SSM for private API access (`create_bastion_host` in tfvars).

## Identity & access

| Concern | Approach | Location |
|---------|----------|----------|
| AWS STS / account roles | Least privilege, shared roles in prod | `tf-rosa/` variables `create_account_roles` |
| Cluster OAuth IdP | GitHub, LDAP, HTPasswd, OIDC | `tf-rosa` `identity_providers`, `modules/idp/` |
| Azure AD (RHCS) | Post-install OIDC registration | `addons/idp-azure-ad/` |
| Microsoft Entra external auth | HCP external auth provider | `tf-rosa/docs/ENTRA-ID-SETUP.md` |
| Keycloak on-cluster | Workload IdP | `addons/keycloak/` |
| Break-glass | Documented in external-auth guide | `docs/ROSA-HCP-EXTERNAL-AUTH-GITOPS-GUIDE.md` |

## Data protection

- **etcd**: `enable_etcd_encryption` + `etcd_kms_key_arn` in `tf-rosa/terraform.tfvars.example`
- **EBS**: `enable_ebs_encryption`, `kms_key_arn`
- **AI artifacts**: S3 encryption — see `addons/openshift-ai/` and OpenShift AI setup doc
- **In transit**: TLS on routes; private clusters limit exposure

## Compliance & operations

- Tag all resources (`tags` in tfvars) for cost and audit
- Prefer Terraform / GitOps for reproducibility (`tf-rosa/`, `addons/operators/gitops-manifests/`)
- Documented teardown in agent instructions (`docs/ai-assistant/`)
- Use persistent OCM token (`RHCS_TOKEN`), not short-lived `rosa login` output, for long applies

## AI workload security

- Private code assistant hardening: `docs/private-code-assistant/`
- Authorino sample: `tf-rosa/assets/authorino.yml`
- Agent demo: `addons/agentic-ai-demo/` (upstream manifests when available)

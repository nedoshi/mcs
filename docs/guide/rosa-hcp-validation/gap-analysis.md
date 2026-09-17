# ROSA HCP gap analysis — validation coverage

Living document. Reconcile with Google Docs when [source-doc-reconciliation.md](source-doc-reconciliation.md) is complete.

## MCS repo coverage vs test cases

| TC | Topic | Repo automation | Gap |
|----|-------|-----------------|-----|
| TC-01 | STS roles | `hcp-ansible`, `tf-rosa` | Manual prefix hygiene |
| TC-02 | Public install | `rosa_hcp_public` role | ROSA-managed network path less exercised in Ansible |
| TC-03 | Private install | `rosa_hcp_private` role | Full PrivateLink matrix not scripted |
| TC-04 | Shared VPC | Tutorial + `shared-vpc/terraform` | Long manual cross-account path |
| TC-05 | External auth | `tf-rosa` external-auth example | CLI-only external auth path version-dependent |
| TC-06 | Cluster review | `rosa_cluster_review_guide.md` | No automated script in this folder |
| TC-07 | Machine pools | Examples only | No CI job |
| TC-08 | IdP | Docs | External-auth-only clusters differ |
| TC-09 | Private ingress | Troubleshooting guide | Public ALB chain not automated |
| TC-10 | Day-2 smoke | ARO HCP mirror | Logging/mesh deferred |

## ARO HCP vs ROSA HCP (validation parity)

| Dimension | ARO HCP validation | ROSA HCP validation |
|-----------|-------------------|---------------------|
| Control plane | Azure-hosted | Red Hat/AWS-hosted (HyperShift) |
| Provision | `az rest` / Bicep | `rosa`, Terraform RHCS |
| Mandatory external auth | Yes (preview) | Optional at create |
| Admin access | 24h ARM credential | `rosa create admin` |
| Shared network | Azure VNet | AWS Shared VPC + RAM |
| Workshop port | bookbag-aro-mobb | Use ROSA MOBB / tf-rosa examples |

## Recommended execution order

1. Prerequisites → TC-01 → TC-02 (baseline)
2. TC-06 on baseline cluster
3. TC-10 smoke
4. TC-03 + TC-09 (private path)
5. TC-04 (if multi-account lab available)
6. TC-05 + TC-08 (identity)
7. TC-07 (capacity)

## Blockers to track

| Blocker | Severity |
|---------|----------|
| Google Doc test IDs unknown | High — reconcile sources |
| Shared VPC CLI flag drift across ROSA versions | Medium |
| External auth irreversible — lab churn cost | Medium |
| Zero-egress clusters not covered here | Low — see `cluster-zero-egress/` |

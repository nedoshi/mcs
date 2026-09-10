# ARO HCP Gap Analysis — Classic ARO vs ARO HCP vs ROSA HCP

Living document — update during Phase 1 validation. See [validation-report.md](validation-report.md) for test execution dates.

## Platform comparison

| Dimension | Classic ARO | ARO HCP | ROSA HCP (AWS) |
|-----------|-------------|---------|----------------|
| Control plane | Customer-managed nodes in cluster VNet | Hosted (Azure-managed) | Hosted (Red Hat/AWS) |
| ARM/RHCS resource | `openShiftClusters` | `hcpOpenShiftClusters` | RHCS `Cluster` |
| Provision tooling in MCS | [terraform-aro](../../../cluster-creation-cloud/azure/terraform-aro/) | [terraform-aro-hcp stub](../../../cluster-creation-cloud/azure/terraform-aro-hcp/) | [tf-rosa](../../../cluster-creation-cloud/aws/tf-rosa/) |
| Default admin | kubeadmin (persistent) | 24h admin kubeconfig API | break-glass / admin credential |
| Identity | Built-in OAuth + optional IdP | **External auth only** | External auth optional at create |
| IdP configuration | `OAuth` CR + secrets | Bicep `externalAuths` child resource | RHCS external auth config |
| Workshop IdP module | Azure AD ([1a-configure-aad](https://github.com/rh-mobb/bookbag-aro-mobb/blob/main/workshop/content/200-ops/idp/1a-configure-aad.adoc)) | RHBK + Bicep (rewrite required) | Entra ID / Keycloak patterns exist |
| CLI login | `oc login -u kubeadmin` | OIDC token / oc-oidc | OIDC token |
| Scale workers | `az aro update` | TBD — ARM/MachineSet (validate ST-01) | `rosa edit machinepool` / TF |
| MCS DR tfvars | [aro-primary.tfvars.example](../../../cluster-creation-cloud/cross-cloud-dr/environments/aro-primary.tfvars.example) | **Not validated** — classic only today | ROSA side complete |

## bookbag-aro-mobb module portability

| Module | Portable to HCP? | Action |
|--------|------------------|--------|
| `100-setup/1-environment` | Partial | Update Azure CLI checks for HCP API |
| `100-setup/2-access-cluster` | **No** | Replace kubeadmin flow with admin credential + OIDC |
| `200-ops/idp/1a-configure-aad` | **No** | Replace with RHBK external auth module |
| `200-ops/idp/1b-explore-aad` | **No** | Replace with external auth exploration |
| `200-ops/day2/1-upgrades` | Unknown | Validate HCP upgrade path (ST pending) |
| `200-ops/day2/2-scaling-nodes` | Unknown | ST-01 |
| `200-ops/day2/3-autoscaling` | Unknown | ST-02 |
| `200-ops/day2/4-labels` | Likely yes | Node labeling via `oc` unchanged |
| `200-ops/day2/5-observability` | Unknown | ST-05 — Azure integration may differ |
| `300-app/*` | Likely yes | Requires RHBK user login |
| `500-service-mesh/*` | Defer | ST-06 BLOCKED for Phase 1 |

## Cross-cloud DR implications

The [cross-cloud DR guide](../cross-cloud-dr-aro-rosa/README.md) pairs **classic ARO** with **ROSA HCP**. Until ARO HCP DR is validated:

- Treat [aro-dr.tfvars.example](../../../cluster-creation-cloud/cross-cloud-dr/environments/aro-dr.tfvars.example) as **classic ARO only**
- Flag ARO HCP as unsupported for cross-cloud DR tiers in production checklists
- GitOps/OADP layers remain platform-agnostic above the cluster provisioner

## Smoke test results (fill during validation)

| ID | Result | Date | Root cause / notes |
|----|--------|------|---------------------|
| ST-01 Worker scaling | PENDING | | |
| ST-02 Autoscaling | PENDING | | |
| ST-03 Quarkus deploy | PENDING | | |
| ST-04 GitOps | PENDING | | |
| ST-05 Observability | PENDING | | |
| ST-06 Service mesh | BLOCKED | | Deferred Phase 2 |

## Key blockers for GA readiness

| Blocker | Severity | Owner |
|---------|----------|-------|
| API version preview drift (`2024-06-10-preview`) | High | Microsoft |
| terraform-aro-hcp repo access | Medium | rh-mobb |
| RHBK mandatory for all labs | Medium | Workshop team |
| No kubeadmin breaks existing bookbag access modules | High | Workshop team |
| HCP DR story undefined | Medium | Architecture |

## Phase 2 workshop recommendation (preview)

**Do not fork bookbag until PA-01 through PA-10 pass.**

Minimum viable workshop (MVP):

1. Environment setup (HCP-specific)
2. Admin credential + RHBK external auth
3. OIDC console/CLI access
4. Quarkus deploy + GitOps (port from classic)

Defer: Azure AD modules, service mesh, observability-to-Azure-Files until smoke tests pass.

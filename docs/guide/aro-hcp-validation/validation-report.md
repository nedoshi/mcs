---
date: '2026-08-20'
title: 'ARO HCP Phase 1 Validation Report'
tags: ["ARO HCP", "Validation", "MOBB", "Phase 1"]
status: template
---

# ARO HCP Phase 1 Validation Report

**Purpose:** Gate Phase 2 workshop work ([bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb) HCP fork). Do not start bookbag rewrites until Path A criteria below are `PASS`.

## Executive summary

| Item | Status |
|------|--------|
| Validation runbook in MCS | **Complete** — [docs/guide/aro-hcp-validation/](.) |
| Reproducible scripts (RHAC-derived) | **Complete** — [scripts/](scripts/) |
| Path A live execution | **Pending** — requires Azure ARO HCP preview subscription |
| Path B terraform-aro-hcp | **Blocked** — repo access not available; placeholder at [terraform-aro-hcp](../../../cluster-creation-cloud/azure/terraform-aro-hcp/) |
| Troubleshooting guide | **Complete** — [ARO-HCP-External-auth.md](../../troubleshooting/ARO/ARO-HCP-External-auth.md) |
| Gap analysis | **Complete** — [gap-analysis.md](gap-analysis.md) |

## Test environment (fill on execution)

| Field | Value |
|-------|-------|
| Tester | |
| Execution date (UTC) | |
| Azure subscription ID | |
| Azure region | |
| Cluster name | |
| Resource group | |
| OpenShift version | |
| ARM API version | `2024-06-10-preview` |
| RHBK host | |
| External auth name | `aro-hcp-auth` |

## Path A results

| ID | Test | Result | Notes |
|----|------|--------|-------|
| PA-01 | Preview subscription access | PENDING | Request via Microsoft/Red Hat PM |
| PA-02 | Cluster `Succeeded` | PENDING | See [02-provision-azure-cli.md](02-provision-azure-cli.md) |
| PA-03 | API URL via ARM | PENDING | |
| PA-04 | Admin kubeconfig issued | PENDING | [request-aro-admin-credential.sh](scripts/request-aro-admin-credential.sh) |
| PA-05 | ClusterOperators Available | PENDING | [validate-cluster.sh](scripts/validate-cluster.sh) |
| PA-06 | External auth Bicep | PENDING | [externalauth.bicep](scripts/externalauth.bicep) |
| PA-07 | Console client secret | PENDING | |
| PA-08 | RBAC group binding | PENDING | |
| PA-09 | RHBK console login | PENDING | |
| PA-10 | RHBK CLI `oc whoami` | PENDING | |
| PA-11 | Admin credential re-issue | PENDING | |

**Path A exit:** All PA-* rows must be `PASS` before Phase 2.

### Path A execution commands

```bash
cd docs/guide/aro-hcp-validation/scripts
cp env.example env.sh && vi env.sh && source env.sh

# After cluster provision:
chmod +x request-aro-admin-credential.sh validate-cluster.sh
./request-aro-admin-credential.sh
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
./validate-cluster.sh

# External auth — see 03-external-auth-rhbk.md
```

## Day-2 smoke test results

| ID | Test | Result | Notes |
|----|------|--------|-------|
| ST-01 | Worker scaling | PENDING | |
| ST-02 | Cluster autoscaling | PENDING | |
| ST-03 | Quarkus deploy | PENDING | |
| ST-04 | GitOps | PENDING | |
| ST-05 | Observability → Azure Files | PENDING | |
| ST-06 | Service mesh | BLOCKED | Deferred Phase 2 |

Details: [05-smoke-tests.md](05-smoke-tests.md)

## Path B results (terraform-aro-hcp)

| Item | Result | Notes |
|------|--------|-------|
| Submodule added | BLOCKED | [06-terraform-aro-hcp.md](06-terraform-aro-hcp.md) |
| mobb-lab.tfvars.example | **Complete** | [examples/mobb-lab.tfvars.example](../../../cluster-creation-cloud/azure/terraform-aro-hcp/examples/mobb-lab.tfvars.example) |
| plan/apply matches Path A | PENDING | |
| destroy cleanup | PENDING | |

## Findings and blockers

### Confirmed architectural deltas (pre-live test)

1. **No kubeadmin** — all bookbag access modules must be rewritten.
2. **External auth mandatory** — Azure AD OAuth CR modules are invalid; use RHBK + Bicep.
3. **Admin credential TTL 24h** — lab environments need renewal automation or scripted refresh.
4. **API preview** — pin `2024-06-10-preview`; revalidate on GA.
5. **Cross-cloud DR** — existing ARO tfvars target classic ARO only ([gap-analysis.md](gap-analysis.md)).

### Open blockers

| Blocker | Impact | Mitigation |
|---------|--------|------------|
| No Azure HCP preview subscription in MCS CI | Cannot auto-run Path A | Manual execution by assigned cloud expert |
| terraform-aro-hcp repo 404 / private | Path B blocked | Path A authoritative; MOBB tfvars template ready |
| RHBK lab infrastructure | Workshop complexity | Shared MOBB Keycloak per GUID |

## Phase 2 workshop recommendations

**Gate:** Path A PA-01–PA-10 all `PASS`.

### Repository strategy

Fork [bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb) → `bookbag-aro-hcp-mobb` (recommended over in-repo conditionals).

### Module rewrite priority

| Priority | Module | Effort |
|----------|--------|--------|
| P0 | `100-setup/2-access-cluster` | High — admin credential + OIDC |
| P0 | `200-ops/idp/*` | High — replace AAD with RHBK Bicep flow |
| P1 | `300-app/*` | Low — port with OIDC login note |
| P2 | `200-ops/day2/*` | Medium — validate ST-01/ST-02 first |
| P3 | `500-service-mesh/*` | Defer |

### workshop-vars.json changes

Remove:

- `aro_kube_password`
- `preconfigure_aad` (AAD-specific)

Add:

- `aro_hcp_cluster_name`
- `rhbk_host`
- `external_auth_name`
- `openshift_api_url`

### Lab provisioning (AgnosticD / OpenTLC)

Pre-provision per student GUID:

1. ARO HCP cluster
2. RHBK realm `openshift` with clients (or shared RHBK + per-GUID realm)
3. Inject vars into bookbag `WORKSHOP_VARS`

### MCS demo follow-up

After Path A pass: add `openshift-demos/aro-hcp-101-welcome/` mirroring [rosa-101-welcome](../../../openshift-demos/rosa-101-welcome/).

## Deliverables checklist (Phase 1)

- [x] Validation runbook — [README.md](README.md) + numbered guides
- [x] RHAC-derived scripts — [scripts/](scripts/)
- [x] Gap analysis — [gap-analysis.md](gap-analysis.md)
- [x] Troubleshooting — [ARO-HCP-External-auth.md](../../troubleshooting/ARO/ARO-HCP-External-auth.md)
- [x] terraform-aro-hcp placeholder + MOBB tfvars — [terraform-aro-hcp/](../../../cluster-creation-cloud/azure/terraform-aro-hcp/)
- [ ] Live Path A execution recorded (tester action)
- [ ] Live smoke tests recorded (tester action)
- [ ] Path B comparison (when repo access granted)

## Sign-off

| Role | Name | Date | Path A | Phase 2 approved |
|------|------|------|--------|------------------|
| Cloud expert | | | PENDING | No |
| Workshop lead | | | | |

## References

- [RHAC ARO HCP external auth](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html)
- [terraform-aro-hcp (pending)](https://github.com/rh-mobb/terraform-aro-hcp)
- [bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb)
- [Master checklist](README.md)

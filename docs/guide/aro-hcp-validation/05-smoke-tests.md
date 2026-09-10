# ARO HCP Validation — Day-2 Smoke Tests

Run after Path A pass criteria ([README.md](README.md)). These tests probe whether existing [bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb) scenarios work on ARO HCP without modification.

**Credential guidance:**

- Use **admin kubeconfig** for cluster-scoped bootstrap (operators, MachineSets, GitOps install).
- Use **RHBK OIDC user** for app deploy labs mirroring student experience.

## Automated baseline

```bash
source docs/guide/aro-hcp-validation/scripts/env.sh
export KUBECONFIG=docs/guide/aro-hcp-validation/scripts/aro-cluster.kubeconfig
docs/guide/aro-hcp-validation/scripts/validate-cluster.sh
```

## ST-01 — Worker scaling

**Source:** `bookbag-aro-mobb` → `200-ops/day2/2-scaling-nodes`

Classic ARO uses `az aro update --worker-count`. HCP may require ARM API, portal, or MachineSet edits.

```bash
# Inspect current workers
oc get nodes
oc get machinesets -A

# Document the scaling mechanism that works on your HCP cluster:
# Option A: Azure portal / az rest PATCH on hcpOpenShiftClusters
# Option B: oc scale machineset <name> -n openshift-machine-api --replicas=N
```

| Result | Criteria |
|--------|----------|
| PASS | Node count increases; workloads schedule |
| FAIL | Scale action errors or nodes NotReady |
| BLOCKED | No documented HCP scale API available |

## ST-02 — Cluster autoscaling

**Source:** `200-ops/day2/3-autoscaling`

```bash
oc get clusterautoscaler cluster -o yaml 2>/dev/null || echo "No ClusterAutoscaler"
oc get machinesets -n openshift-machine-api
```

Verify ClusterAutoscaler operator is Available and min/max replicas behave as expected.

## ST-03 — Quarkus app deploy

**Source:** `300-app/1-app-deploy`

Prerequisites: RHBK user with `edit` on target namespace (or cluster-admin for lab).

```bash
# Login as RHBK user (not admin kubeconfig)
oc login "${OPENSHIFT_API_URL}" --token=<oidc-token>

oc new-project aro-hcp-smoke --display-name="ARO HCP Smoke Test"
oc new-app --name=quarkus-smoke \
  https://github.com/quarkusio/quarkus-quickstarts.git \
  --context-dir=get-started \
  --track=main
oc get pods -w
```

| Result | Criteria |
|--------|----------|
| PASS | Build completes; route serves HTTP 200 |
| FAIL | Build/deploy/auth failure |

## ST-04 — OpenShift GitOps

**Source:** `300-app/2-app-gitops`

Use admin kubeconfig to install OpenShift GitOps operator, then validate Application sync as RHBK user.

```bash
# Admin context
export KUBECONFIG=docs/guide/aro-hcp-validation/scripts/aro-cluster.kubeconfig
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get csv -n openshift-operators -w
```

Document whether default GitOps Argo CD instance is reachable with RHBK SSO.

## ST-05 — Observability → Azure Files

**Source:** `200-ops/day2/5-observability`

Validate whether Azure Files integration documented for classic ARO applies to HCP worker/control-plane split. Record Azure Monitor / log forwarding behavior differences.

**Expected:** May require BLOCKED pending HCP-specific Microsoft guidance.

## ST-06 — Service mesh

**Source:** `500-service-mesh/*`

**Recommendation:** Mark **BLOCKED** for Phase 1 unless explicit HCP service mesh guidance exists. Defer to Phase 2 workshop scoping.

## Recording results

Update the smoke test matrix in [README.md](README.md) and summarize in [validation-report.md](validation-report.md).

## Next step

Path B (when repo access granted): [06-terraform-aro-hcp.md](06-terraform-aro-hcp.md)

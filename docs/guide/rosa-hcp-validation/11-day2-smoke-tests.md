# TC-10 — Day-2 smoke tests

**Provenance:** Inferred from repo (ARO HCP [05-smoke-tests.md](../aro-hcp-validation/05-smoke-tests.md), `hcp-ansible` post-install patterns).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Day-2 operations smoke: operator health, sample app deploy, optional GitOps operator install, and machine pool scale—mirroring workshop scenarios on ROSA HCP.

## Why this matters

- Proves customer day-2 workflows beyond install.
- Catches CNI/storage regressions on HyperShift workers.
- Feeds cross-cloud DR readiness (GitOps, sample app portability).

## Flow

```
 ready cluster
      │
      ├── ST-01 scale workers / machinepool
      ├── ST-02 cluster autoscaler check
      ├── ST-03 sample app + route
      └── ST-04 GitOps operator (optional)
```

## Prerequisites

- TC-02+ cluster `ready`; `oc` cluster-admin.
- IdP or htpasswd user for app namespace tests (TC-08).

## Automated baseline

```bash
oc get clusterversion
oc get clusteroperators
oc get nodes
```

All critical operators `Available=True`.

## ST-01 — Worker / machine pool scaling

```bash
rosa list machinepools -c "${CLUSTER_NAME}"
# Scale default pool or use TC-07
rosa edit machinepool --cluster="${CLUSTER_NAME}" --name=default --replicas=4
watch -n 20 'oc get nodes | wc -l'
```

| Result | Criteria |
|--------|----------|
| PASS | Node count increases; pods schedule |
| FAIL | Machines fail or NotReady >15m |

## ST-02 — Cluster autoscaling

```bash
oc get clusterautoscaler cluster -o yaml 2>/dev/null || echo "No ClusterAutoscaler"
oc get machinepool -n openshift-machine-api
```

PASS if autoscaler exists and min/max match tfvars—or document N/A for fixed-replica labs.

## ST-03 — Sample application

```bash
oc new-project rosa-hcp-smoke --as htpasswd:lab-htpasswd:testuser 2>/dev/null || oc new-project rosa-hcp-smoke
oc create deployment smoke --image=registry.redhat.io/ubi9/httpd-24 -n rosa-hcp-smoke
oc expose deployment smoke -n rosa-hcp-smoke --port=8080
curl -sk "https://$(oc get route smoke -n rosa-hcp-smoke -o jsonpath='{.spec.host}')/" -w "%{http_code}\n"
```

PASS: HTTP 2xx/3xx from in-VPC or public client per cluster type.

## ST-04 — OpenShift GitOps (optional)

```bash
oc apply -f - <<'EOF'
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
oc get csv -n openshift-operators | grep gitops
```

PASS: CSV `Succeeded`; default Argo CD instance reachable.

## ST-05 — Logging (optional)

See [OpenShift Logging 6 on ROSA HCP](https://cloud.redhat.com/experts/o11y/openshift-logging6-rosa-hcp/). Mark BLOCKED if not in QE scope.

## Success criteria (rollup)

| ID | PASS condition |
|----|----------------|
| ST-01 | `oc get nodes` count ≥ target replicas |
| ST-02 | Autoscaler documented or functional |
| ST-03 | Route returns connected HTTP response |
| ST-04 | GitOps CSV installed (if attempted) |

Update matrix in [README.md](README.md) and [validation-report.md](validation-report.md).

## Failure signals

- Image pull errors on workers → missing egress/NAT or registry firewall.
- Route pending → ingress or DNS not ready.
- GitOps CSV stuck `Installing` → catalog or pull secret issues.

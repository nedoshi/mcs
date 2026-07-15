# ROSA 101: Resource Requests, Limits & Quotas Demo

Workshop script for the `rosa-101-welcome` deployment. Modeled on the Red Hat OpenShift resource management lab flow ([resource-mgmt.md](https://github.com/bcgov/devops-platform-workshops/blob/master/openshift-201/resource-mgmt.md)).

> **Note:** The Google Drive reference (`1e4V-ePDEjV9a9Izbf4YzHoifsRYxcABh`) requires sign-in and could not be fetched. This script follows the same structure: set resources → generate traffic → observe usage → QoS → LimitRange/Quota.

## Objectives

After this demo you can explain:

- **Requests** — scheduling guarantee; used by the scheduler
- **Limits** — hard cap; CPU throttling / OOM kill beyond this
- **QoS classes** — Burstable vs Guaranteed
- **LimitRange** — defaults and min/max per container in a project
- **ResourceQuota** — project-wide caps on total CPU/memory/pods

## Recommended values (rosa-101-welcome)

| Phase | CPU request | CPU limit | Memory request | Memory limit | QoS |
|-------|-------------|-----------|----------------|--------------|-----|
| Baseline | `50m` | `200m` | `128Mi` | `256Mi` | Burstable |
| Under load demo | `50m` | `100m` | `128Mi` | `200Mi` | Burstable (throttles sooner) |
| Guaranteed demo | `100m` | `100m` | `200Mi` | `200Mi` | Guaranteed |

## Prerequisites

```bash
oc project rosa-demo          # or your project
oc get deploy                 # note deployment name (often mcs-git)
chmod +x scripts/demo-resource-limits.sh
```

App must be deployed with a route:

```bash
oc get route
curl -sk https://$(oc get route -o jsonpath='{.items[0].spec.host}')/health
```

## Automated demo (instructor script)

Runs step-by-step with pauses:

```bash
./scripts/demo-resource-limits.sh rosa-demo mcs-git
```

Replace `mcs-git` with your deployment name.

## Manual demo steps

### 1. Set requests and limits

```bash
DEPLOY=mcs-git
NS=rosa-demo

oc set resources deployment/${DEPLOY} \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi \
  -n ${NS}

oc rollout status deployment/${DEPLOY} -n ${NS}
oc describe deploy/${DEPLOY} -n ${NS}
```

**Talking point:** Requests tell the scheduler how much to reserve. Limits prevent a pod from starving others.

### 2. Tighten limits before load test

```bash
oc set resources deployment/${DEPLOY} \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=100m,memory=200Mi \
  -n ${NS}
```

### 3. Generate traffic

```bash
ROUTE=$(oc get route -n ${NS} -o jsonpath='{.items[0].spec.host}')

oc delete job rosa-101-load-test -n ${NS} --ignore-not-found
sed "s/REPLACE_WITH_ROUTE_HOST/${ROUTE}/" kubernetes/load-test-job.yaml | oc apply -n ${NS} -f -

oc logs -f job/rosa-101-load-test -n ${NS}
```

### 4. Observe usage

```bash
oc describe pod -l app=${DEPLOY} -n ${NS}
oc adm top pods -l app=${DEPLOY} -n ${NS}
oc get pod -l app=${DEPLOY} -n ${NS} -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```

**Talking point:** If `oc adm top` shows CPU near the limit (`100m`), the kernel cgroup is throttling the container.

### 5. Guaranteed QoS

```bash
oc set resources deployment/${DEPLOY} \
  --requests=cpu=100m,memory=200Mi \
  --limits=cpu=100m,memory=200Mi \
  -n ${NS}

oc get pod -l app=${DEPLOY} -n ${NS} -o jsonpath='{.items[0].status.qosClass}{"\n"}'
# Guaranteed
```

### 6. LimitRange and ResourceQuota (optional)

```bash
oc apply -f kubernetes/limit-range.yaml -n ${NS}
oc apply -f kubernetes/resource-quota.yaml -n ${NS}

oc describe limitrange rosa-101-limits -n ${NS}
oc describe quota rosa-101-quota -n ${NS}
```

**Talking point:** LimitRange = per-container defaults/min/max. ResourceQuota = project-wide totals.

### 7. Restore baseline

```bash
oc set resources deployment/${DEPLOY} \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi \
  -n ${NS}
```

## Console demo (optional)

1. **Workloads → Deployments → {deploy} → Actions → Edit resource limits**
2. **Administration → LimitRanges** (if cluster admin)
3. **Administration → ResourceQuotas**
4. **Observe → Metrics** — CPU/memory per pod

## Cleanup

```bash
oc delete job rosa-101-load-test -n rosa-demo --ignore-not-found
oc delete -f kubernetes/limit-range.yaml -n rosa-demo --ignore-not-found
oc delete -f kubernetes/resource-quota.yaml -n rosa-demo --ignore-not-found
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `oc adm top` says metrics not available | Wait for metrics-server; `oc get apiservice v1beta1.metrics.k8s.io` |
| Load test Job fails | Check route URL; `curl -sk https://${ROUTE}/health` |
| Pod pending after quota applied | Quota exceeded — `oc describe quota rosa-101-quota` |
| Wrong deployment name | `oc get deploy -n rosa-demo` |

## Files

| File | Purpose |
|------|---------|
| `scripts/demo-resource-limits.sh` | Interactive instructor script |
| `kubernetes/load-test-job.yaml` | Traffic generator Job |
| `kubernetes/limit-range.yaml` | Project LimitRange |
| `kubernetes/resource-quota.yaml` | Project ResourceQuota |
| `kubernetes/deployment.yaml` | Deployment with baseline resources |

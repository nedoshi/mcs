# ROSA 101: Resource Limits & HPA Demo

Use these values and steps for a **5–10 minute live demo** on the `rosa-101-welcome` app.

## Run preflight first

Most HPA demos fail for three reasons:

1. **`/api/load` returns 404** — old image, no CPU burn endpoint
2. **No CPU requests** on deployment — HPA cannot calculate utilization
3. **Wrong deployment/service name** — import-from-git often creates `mcs-git`, not `rosa-101-welcome`

```bash
chmod +x scripts/hpa-preflight.sh
./scripts/hpa-preflight.sh rosa-demo
```

Fix anything marked `FAIL` before continuing.

## Recommended values

| Setting | Value | Why |
|---------|-------|-----|
| **CPU request** | `50m` | Lower request = same load hits HPA target faster |
| **CPU limit** | `200m` | Room to work while still showing pressure |
| **Memory request** | `128Mi` | Typical small Node.js app |
| **Memory limit** | `256Mi` | Headroom without hiding OOM risk entirely |
| **Starting replicas** | `1` | Makes scale-up obvious (1 → 3 → 5) |
| **HPA min** | `1` | |
| **HPA max** | `5` | Fits small ROSA worker nodes |
| **HPA CPU target** | `40%` | Scales quickly (~20m avg CPU per pod) |

> HPA needs **CPU requests** on the container. Without requests, CPU-based autoscaling will not work.

## Prerequisites

```bash
oc project rosa-demo   # or your project

# metrics-server must be running (default on ROSA)
oc get apiservice v1beta1.metrics.k8s.io

# App must include /api/load endpoint (rebuild after pulling latest code)
oc start-build rosa-101-welcome --wait
```

## Part 1: Resource requests & limits (~3 min)

**Set resources** (if not using `kubernetes/deployment.yaml`):

```bash
DEPLOY=mcs-git   # use: oc get deploy -n rosa-demo
SVC=mcs-git      # use: oc get svc -n rosa-demo

oc set resources deployment/${DEPLOY} \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi \
  -n rosa-demo

oc scale deployment/${DEPLOY} --replicas=1 -n rosa-demo
```

**Show baseline:**

```bash
oc get deploy rosa-101-welcome -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
oc adm top pods -l app=rosa-101-welcome
```

**Generate load** (from your laptop):

```bash
ROUTE=$(oc get route rosa-101-welcome -o jsonpath='{.spec.host}' -n rosa-demo)

# 30 concurrent requests, each burns ~200ms CPU server-side
for i in $(seq 1 30); do
  curl -s "https://${ROUTE}/api/load?ms=200" >/dev/null &
done
wait

oc adm top pods -l app=rosa-101-welcome
```

**Talking points:**
- CPU **request** = guaranteed scheduling slice (`100m` = 0.1 core)
- CPU **limit** = hard cap; pod throttles above `150m`
- `oc adm top pods` shows live usage vs limits
- Normal page traffic barely moves the needle — that's why `/api/load` exists

## Part 2: Horizontal Pod Autoscaler (~5 min)

**Apply HPA** (match your deployment name):

```bash
DEPLOY=mcs-git   # change to your deployment name

# option A: quick CLI HPA
oc autoscale deployment/${DEPLOY} --min=1 --max=5 --cpu-percent=40 -n rosa-demo

# option B: manifest (edit scaleTargetRef.name if not rosa-101-welcome)
oc apply -f kubernetes/hpa.yaml -n rosa-demo
```

**Watch in a second terminal:**

```bash
watch -n2 'oc get hpa,pods -l app=rosa-101-welcome -n rosa-demo'
```

**Start in-cluster load generator** (point at your service):

```bash
SVC=mcs-git   # change to your service name

oc apply -f kubernetes/load-generator.yaml -n rosa-demo
oc set env deployment/rosa-101-loadgen \
  TARGET_URL="http://${SVC}:8080/api/load?ms=300" -n rosa-demo
oc rollout restart deployment/rosa-101-loadgen -n rosa-demo
```

Within **1–3 minutes** you should see:
- HPA `TARGETS` climb above `50%`
- `REPLICAS` increase (typically 1 → 3 → 5)
- New pods in `Running`

**Talking points:**
- HPA reads metrics from **metrics-server**
- Target `50%` of `100m` request = scale when avg pod CPU ≈ `50m`
- More pods share load → CPU per pod drops → stabilizes near target

**Stop load & watch scale-down:**

```bash
oc delete deployment rosa-101-loadgen -n rosa-demo
```

Replicas scale down after ~60s (configured in `hpa.yaml`). Default K8s behavior can take longer; our HPA uses a short `scaleDown` stabilization window for demos.

## Part 3: Console demo (optional)

1. **Workloads → Deployments → rosa-101-welcome → Actions → Edit resource limits**
2. **Workloads → HorizontalPodAutoscalers** — show targets and replica graph
3. **Observe → Metrics** — CPU per pod (if enabled on cluster)

## Quick reference commands

```bash
# Status
oc describe hpa rosa-101-welcome -n rosa-demo
oc get pods -l app=rosa-101-welcome -o wide -n rosa-demo

# Manual scale (disable HPA effect temporarily by deleting HPA first)
oc scale deployment/rosa-101-welcome --replicas=2 -n rosa-demo

# Cleanup
oc delete -f kubernetes/hpa.yaml -n rosa-demo
oc delete -f kubernetes/load-generator.yaml -n rosa-demo
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| HPA shows `<unknown>/50%` | metrics-server not ready; wait or `oc get apiservice v1beta1.metrics.k8s.io` |
| Replicas never increase | Missing CPU **requests** on deployment; verify with `oc get deploy -o yaml \| grep -A6 resources` |
| `/api/load` returns 404 | Rebuild app image (`oc start-build rosa-101-welcome --wait`) |
| Scale-up too slow | Lower HPA target to `40%` or increase loadgen replicas |
| Scale-down too slow | Already tuned to 60s; delete HPA for instant manual control |

## Why these numbers?

- **Too high** limits (e.g. `cpu: 1000m`) → app never looks "stressed", boring demo
- **Too low** limits (e.g. `cpu: 20m`) → pod thrashes/OOMs before HPA reacts
- **`100m` request / `150m` limit / `50%` target** → reliable scale-up on a 2–4 node ROSA cluster within a few minutes

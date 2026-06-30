# ARO Node Maintenance: Automated Image Pruning & Disk Alerts

This guide deploys two components on an Azure Red Hat OpenShift (ARO) cluster:

1. **Automated Image Pruning DaemonSet** — cleans up unused container images on worker nodes when disk usage exceeds a threshold
2. **PrometheusRule for Node Health Alerts** — fires alerts on DiskPressure, MemoryPressure, PIDPressure, and high disk utilization

## Background

On ARO (and ROSA/OSD), configuring the kubelet Garbage Collector via `KubeletConfig` is **not allowed** ([Red Hat Solution 7036391](https://access.redhat.com/solutions/7036391)). The built-in OpenShift image pruner only cleans the internal registry, not cached images on nodes under `/var/lib/containers/storage`. ARO also lacks a default `DiskPressure` alert.

These two manifests fill both gaps.

## Prerequisites

- `oc` CLI installed and authenticated as `cluster-admin`
- Access to the ARO cluster (`oc whoami` returns a valid user)

Verify access:

```bash
oc whoami
oc get nodes
```

---

## 1. Deploy the Automated Image Pruning DaemonSet

### 1.1 Apply the manifest

The manifest creates a namespace, service account, and DaemonSet in a single file.

```bash
oc apply -f image-pruner-daemonset.yaml
```

### 1.2 Grant the privileged SCC

The DaemonSet requires privileged access to `chroot` into the host filesystem and run `crictl`.

```bash
oc adm policy add-scc-to-user privileged -z image-pruner -n image-pruner
```

### 1.3 Label the namespace for Pod Security Admission

```bash
oc label namespace image-pruner \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite
```

### 1.4 Verify pods are running

```bash
oc get pods -n image-pruner -o wide
```

Expected output: one pod per worker node, all `1/1 Running`.

### 1.5 Check logs

```bash
oc logs daemonset/image-pruner -n image-pruner --all-containers --prefix
```

You should see periodic log lines like:

```
[pod/image-pruner-xxxxx/pruner] Image pruner started — high=70% low=60% interval=300s
[pod/image-pruner-xxxxx/pruner] 2026-03-23T13:45:57Z disk usage: 10%
```

When usage exceeds the threshold, you'll also see:

```
[pod/image-pruner-xxxxx/pruner] 2026-03-23T14:00:57Z threshold exceeded (72% > 70%), pruning unused images...
[pod/image-pruner-xxxxx/pruner] 2026-03-23T14:01:12Z pruning complete: images 41 -> 29, disk 72% -> 65%
```

### 1.6 How it works

| Setting | Default | Description |
|---|---|---|
| `HIGH_THRESHOLD` | `70` | Disk usage % that triggers pruning |
| `LOW_THRESHOLD` | `60` | Reserved for future use (stop-pruning watermark) |
| `CHECK_INTERVAL` | `300` | Seconds between checks (5 minutes) |

- Each pod mounts the host root filesystem at `/host` and uses `chroot /host` to access host tools.
- `crictl rmi --prune` removes all container images **not** referenced by any running container. It is safe — it will never remove images used by active pods.
- The DaemonSet targets only worker nodes via `nodeSelector: node-role.kubernetes.io/worker: ""`.

### 1.7 Tuning

Edit the environment variables in `image-pruner-daemonset.yaml` and re-apply:

```bash
oc apply -f image-pruner-daemonset.yaml
```

---

## 2. Deploy Node Health Alert Rules

### 2.1 Apply the PrometheusRule

```bash
oc apply -f custom-alert.yaml
```

### 2.2 Verify the rule was created

```bash
oc get prometheusrule node-health-alerts -n openshift-monitoring
```

### 2.3 Verify rules are loaded and healthy in Prometheus

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
  curl -s 'http://localhost:9090/api/v1/rules' | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for group in data.get('data', {}).get('groups', []):
    for rule in group.get('rules', []):
        name = rule.get('name', '')
        if name in ('NodePressure', 'NodeDiskUsageWarning', 'NodeDiskUsageCritical'):
            print(f'  {name}: state={rule.get(\"state\")}, health={rule.get(\"health\")}')
"
```

Expected output:

```
  NodeDiskUsageWarning: state=inactive, health=ok
  NodeDiskUsageCritical: state=inactive, health=ok
  NodePressure: state=inactive, health=ok
```

All rules should show `health=ok`. The `state=inactive` means no nodes are currently breaching the thresholds.

### 2.4 Alert summary

| Alert | Condition | Severity | Fires after |
|---|---|---|---|
| `NodePressure` | DiskPressure, MemoryPressure, or PIDPressure reported by kubelet | `warning` | 2 minutes |
| `NodeDiskUsageWarning` | `/var` disk usage between 70% and 80% | `warning` | 5 minutes |
| `NodeDiskUsageCritical` | `/var` disk usage above 80% | `critical` | 5 minutes |

### 2.5 ARO-specific note on mountpoints

RHCOS on ARO does **not** expose a `/` mountpoint in `node_exporter`. Container image storage lives on `/var` (typically `/dev/sda4`). The alert expressions use `mountpoint="/var"` to match correctly. You can verify your cluster's mountpoints with:

```bash
oc debug node/<worker-node-name> -- chroot /host df -h /var/lib/containers
```

---

## 3. Testing

### 3.1 Test the image pruner manually

Exec into any pruner pod and trigger a prune regardless of disk usage:

```bash
POD=$(oc get pods -n image-pruner -o name | head -1)

oc exec -n image-pruner $POD -- sh -c '
  echo "Images before: $(chroot /host crictl images -q | wc -l)"
  chroot /host crictl rmi --prune 2>&1
  echo "Images after:  $(chroot /host crictl images -q | wc -l)"
  echo "Disk usage:    $(chroot /host df -h /var/lib/containers | awk "NR==2 {print \$5}")"
'
```

### 3.2 Test alert expressions against live data

Query Prometheus to see current `/var` usage across all nodes:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
  curl -s --data-urlencode \
  'query=(1 - (node_filesystem_avail_bytes{mountpoint="/var"} / node_filesystem_size_bytes{mountpoint="/var"})) * 100' \
  'http://localhost:9090/api/v1/query' | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('data', {}).get('result', []):
    print(f'  {r[\"metric\"].get(\"instance\",\"?\")}: {float(r[\"value\"][1]):.1f}%')
"
```

### 3.3 Simulate a low-threshold alert

To confirm the alerting pipeline works end-to-end, temporarily lower the threshold (e.g., to 5%) in `custom-alert.yaml`, apply it, wait 5+ minutes, then check for firing alerts:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
  curl -s 'http://localhost:9090/api/v1/alerts' | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for alert in data.get('data', {}).get('alerts', []):
    name = alert.get('labels', {}).get('alertname', '')
    if 'NodeDisk' in name or 'NodePressure' in name:
        state = alert.get('state', '?')
        instance = alert.get('labels', {}).get('instance', '?')
        print(f'  {name}: state={state}, instance={instance}')
"
```

Remember to revert the threshold back to 70% after testing.

---

## 4. Cleanup

To remove everything:

```bash
oc delete -f image-pruner-daemonset.yaml
oc delete -f custom-alert.yaml
oc adm policy remove-scc-from-user privileged -z image-pruner -n image-pruner
oc delete namespace image-pruner
```

---

## Files Reference

| File | Description |
|---|---|
| `image-pruner-daemonset.yaml` | Namespace + ServiceAccount + DaemonSet for automated image pruning |
| `custom-alert.yaml` | PrometheusRule with NodePressure and disk usage alerts |

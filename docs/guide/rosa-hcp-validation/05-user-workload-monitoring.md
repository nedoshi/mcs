# UC-04 — User Workload Monitoring (PodMonitor and PrometheusRule)

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 4.

## Summary

Enable **User Workload Monitoring (UWM)** and deploy **PodMonitor** + **PrometheusRule** CRs in an app namespace—OpenShift-native alternative to installing `kube-prometheus-stack`.

## Why this matters

- Platform monitoring is SRE-managed; app teams still need metrics/alerts in their namespaces.
- UWM is required before federating app metrics to AMP—see [federating_metrics_to_aws_prometheus.md](../../troubleshooting/ROSA/federating_metrics_to_aws_prometheus.md).
- Validates `monitoring.coreos.com` CRDs and RBAC for developers.

## Architecture

```
 [App Pod :8080/metrics]
        ^
        | scrape
 [UWM Prometheus] <-- PodMonitor (my-app)
        |
 [PrometheusRule alerts/recording]
```

## Prerequisites

- Cluster admin can patch `cluster-monitoring-config`.
- App exposes metrics on a named port (example `http-metrics`).

## Steps

1. Enable UWM:

   ```bash
   oc apply -f - <<'EOF'
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: cluster-monitoring-config
     namespace: openshift-monitoring
   data:
     config.yaml: |
       enableUserWorkload: true
   EOF
   ```

2. Wait for UWM pods:

   ```bash
   oc get pods -n openshift-user-workload-monitoring
   ```

3. Deploy sample app with metrics port (or use existing workload).

4. Apply PodMonitor and PrometheusRule (from PDF):

   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PodMonitor
   metadata:
     name: webserver-pod-monitor
     namespace: my-app
     labels:
       app: webserver
   spec:
     selector:
       matchLabels:
         app: webserver
     podMetricsEndpoints:
       - port: http-metrics
         path: /metrics
         interval: 15s
   ---
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: webserver-alert-rules
     namespace: my-app
   spec:
     groups:
       - name: webserver.rules
         rules:
           - record: job:http_requests:rate5m
             expr: sum(rate(http_requests_total[5m])) by (job, namespace)
           - alert: HighErrorRate5XX
             expr: |
               sum(rate(http_requests_total{status=~"5.."}[5m]))
               / sum(rate(http_requests_total[5m])) > 0.05
             for: 2m
             labels:
               severity: critical
   ```

5. Verify targets in UWM Prometheus UI or CLI:

   ```bash
   oc -n openshift-user-workload-monitoring get prometheuses.user-workload -o name
   oc get podmonitor -n my-app
   ```

## Expected output

- UWM Prometheus pods `Running`.
- PodMonitor accepted; targets appear in Prometheus (may take 1–2 minutes).
- PrometheusRule object exists without admission errors.

## Success criteria

```bash
oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml | grep -q enableUserWorkload
oc get pods -n openshift-user-workload-monitoring | grep -q Running
oc get prometheusrule webserver-alert-rules -n my-app
```

Optional: query UWM Prometheus for a metric from your app.

## Failure signals

- No UWM pods → ConfigMap not applied or monitoring operator reconciling errors (`oc logs` in `openshift-monitoring`).
- Empty targets → PodMonitor label selector mismatch or metrics port name wrong.

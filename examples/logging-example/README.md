# ROSA Splunk cost-control — example manifests

Generic templates for [../rosa_splunk_log_filtering_routing_guide.md](../rosa_splunk_log_filtering_routing_guide.md).

Set these variables in your shell before use (see tutorial **Configuration variables**):

| Variable | Example |
|----------|---------|
| `CLUSTER_NAME` | `my-rosa-hcp` |
| `AWS_ACCOUNT_ID` | `123456789012` |
| `AWS_REGION` | `us-east-1` |
| `OCM_CLUSTER_ID` | from `rosa describe cluster -c $CLUSTER_NAME -o json \| jq -r .id` |
| `CRIBL_HEC_URL` | `https://cribl.example.com:10080/cribl/_hec` |
| `CRIBL_TOKEN` | your Cribl or Splunk HEC token |

Substitute placeholders in YAML files with `envsubst` or edit manually.

```bash
export CLUSTER_NAME=my-rosa-hcp AWS_ACCOUNT_ID=123456789012 AWS_REGION=us-east-1
export OCM_CLUSTER_ID=$(rosa describe cluster -c "$CLUSTER_NAME" -o json | jq -r .id)
export CRIBL_HEC_URL=https://cribl.example.com:10080/cribl/_hec

envsubst < clusterlogforwarder-tiered.yaml | oc apply -f -
envsubst < cp-security-cw.yaml > /tmp/cp-security-cw.yaml
envsubst < cp-ops-s3.yaml > /tmp/cp-ops-s3.yaml
rosa create log-forwarder -c "$CLUSTER_NAME" --log-fwd-config=/tmp/cp-security-cw.yaml -y
rosa create log-forwarder -c "$CLUSTER_NAME" --log-fwd-config=/tmp/cp-ops-s3.yaml -y
```

Full walkthrough: [tutorial Step 8](../rosa_splunk_log_filtering_routing_guide.md#step-8--verification-and-ongoing-operations).

---

## Validation — what you should see

Run these after each phase. **Expected** columns describe healthy state; if you see **Failure**, see [Troubleshooting](../rosa_splunk_log_filtering_routing_guide.md#troubleshooting).

### Phase 0 — Day 0 (Logging 6 installed)

```bash
oc get clusterversion
oc get lokistack logging-loki -n openshift-logging -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{.reason}{"\n"}{end}'
oc get pods -n openshift-logging | grep logging-loki
```

| Check | Expected | Failure |
|-------|----------|---------|
| `clusterversion` | `AVAILABLE=True` | Version stuck `Progressing` |
| LokiStack `Ready` | `Ready=True ReadyComponents` | `Failed=True` — often empty `role_arn` in `logging-loki-aws` |
| Loki pods | All `Running` / `1/1` | `CrashLoopBackOff` + `role ARN is not set` in logs |

### Phase 1 — Tiered CLF + S3 (Step 1)

```bash
oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{range .status.pipelineConditions[*]}{.type}{": "}{.status}{"\n"}{end}'

export LOG_BUCKET=rosa-logs-cold-${AWS_ACCOUNT_ID}
aws s3 ls "s3://${LOG_BUCKET}/infrastructure/" --recursive | tail -5

COLLECTOR=$(oc get pods -n openshift-logging -l app.kubernetes.io/name=instance -o jsonpath='{.items[0].metadata.name}')
oc exec -n openshift-logging "${COLLECTOR}" -c collector -- \
  curl -sk https://localhost:24231/metrics | grep 'output_s3_cold' | grep sent_events_total | head -3
```

| Check | Expected | Failure |
|-------|----------|---------|
| CLF `Ready` | `Ready=True` | `Valid=False` — API schema errors (wrong `type`, audit sources) |
| Pipelines | All `ValidPipeline-*=True` (5 pipelines) | Named pipeline `False` — check output secret/URL |
| S3 objects | `.log.gz` under `infrastructure/` within ~5 min | Empty bucket — IRSA / wrong AWS account |
| S3 metrics | `component_sent_events_total` > 0 for `output_s3_cold` | Stays 0 — no infra logs on that node yet, or auth error |
| Cribl sink | Events in Cribl HTTP source UI | DNS/connection errors in collector logs if URL wrong |

**Note (ROSA HCP):** `audit/` in S3 may stay empty until worker audit files exist; **kube API audit** for the control plane arrives via Step 5 / 5.4 (CloudWatch), not CLF.

### Phase 2 — CP log forwarders (Step 5)

```bash
rosa list log-forwarders -c "${CLUSTER_NAME}"
aws logs describe-log-groups --log-group-name-prefix "/rosa/${OCM_CLUSTER_ID}" --region "${AWS_REGION}"
aws s3 ls "s3://${LOG_BUCKET}/control-plane/" --recursive | tail -5
```

| Check | Expected | Failure |
|-------|----------|---------|
| Log forwarders | ≥2 entries (security CW + ops S3) | Empty — wrong `rosa`/`ocm` login or IAM role name |
| CW log group | `/rosa/${OCM_CLUSTER_ID}/security` exists | Missing — CP forwarder not created or wrong region |
| CP S3 prefix | Objects under `control-plane/` | Empty — wait 10–15 min after forwarder create |

### Phase 3 — Audit log forwarding (Step 5.4)

```bash
rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq '.aws.audit_log'
oc get pods -n openshift-config-managed
aws logs describe-log-groups --log-group-name-prefix "ocm-production" --region "${AWS_REGION}"
```

| Check | Expected | Failure |
|-------|----------|---------|
| `audit_log.role_arn` | Your `${AUDIT_ROLE_ARN}` | `null` — OCM patch not applied |
| Audit exporter pod | `cloudwatch-audit-exporter` Running | No pod — patch not applied or role trust wrong |
| CW log group | `ocm-production-*` group with streams | Missing — wait or check IAM policy |

### Phase 4 — Cribl + Splunk (Steps 6–7)

```bash
# Cribl: check HTTP source event rate in UI
# Splunk:
index=rosa_security OR index=rosa_infra_security OR index=rosa_apps earliest=-24h
| stats sum(eval(len(_raw))) as bytes by index
| eval gb=round(bytes/1024/1024/1024, 2)
```

| Check | Expected | Failure |
|-------|----------|---------|
| Cribl HTTP source | Events/sec > 0 from CLF pipelines | 0 — URL/token/egress |
| Cribl → Splunk HEC | Events in Splunk indexes | 0 — HEC destination config |
| Daily volume | Total ≤ 4.0 GB (budget) / hard cap 5 GB | Over cap — tighten Cribl sampling (Step 6.4) |

### Quick pass/fail script

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${CLUSTER_NAME:?}" "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${OCM_CLUSTER_ID:?}"
LOG_BUCKET="rosa-logs-cold-${AWS_ACCOUNT_ID}"

echo -n "CLF Ready: "; oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || echo "FAIL"
echo -n "LokiStack Ready: "; oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || echo "FAIL"
echo -n "S3 infra objects: "; aws s3 ls "s3://${LOG_BUCKET}/infrastructure/" --recursive 2>/dev/null | wc -l
echo -n "CP forwarders: "; rosa list log-forwarders -c "${CLUSTER_NAME}" 2>/dev/null | tail -n +2 | wc -l
echo -n "Audit role set: "; rosa describe cluster -c "${CLUSTER_NAME}" -o json 2>/dev/null | jq -r '.aws.audit_log.role_arn // "null"'
```


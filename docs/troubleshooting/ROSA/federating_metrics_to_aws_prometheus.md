# ROSA — Federating metrics to Amazon Managed Service for Prometheus (AMP)

This guide is an **expanded and hardened** version of the ideas in the Red Hat Cloud Experts article [ROSA - Federating Metrics to AWS Prometheus](https://cloud.redhat.com/experts/rosa/cluster-metrics-to-aws-prometheus/). Use it alongside the upstream MOBB Helm chart; it adds prerequisites, **region alignment**, **User Workload Monitoring (UWM) enablement**, verification commands, **troubleshooting**, and corrected API examples for current OpenShift / Grafana Operator versions.

> **Disclaimer:** Patterns here are for lab and proof-of-concept use. Tighten IAM and network policies for production.

---

## Architecture (short)

- **Cluster metrics:** Grafana Alloy scrapes in-cluster Prometheus **federation** (`/federate`) and **remote_writes** to AMP.
- **User workload metrics:** OpenShift **User Workload Monitoring** Prometheus **remote_writes** to Alloy’s HTTP receiver, which forwards to the same AMP pipeline.
- **Grafana:** Queries AMP through a **SigV4 proxy** sidecar using the same AWS role/region as the write path.

---

## Prerequisites

- [ROSA HCP cluster](https://cloud.redhat.com/experts/rosa/terraform/hcp/) (or compatible ROSA)
- `aws` CLI, `jq`, **`helm`**, **`oc`** (or `kubectl`)
- AWS account permissions to create IAM policies/roles, AMP workspaces, and (optionally) CloudWatch read access

---

## Region alignment (critical)

**Use one AWS region** for all of the following:

1. The **AMP workspace** (`aws amp create-workspace …`)
2. Helm values **`aws.region`** and **`grafana-cr.sigv4Proxy.region`** (and the SigV4 proxy host implied by that region)
3. Alloy’s **`remote_write`** endpoint (set by the chart from `aws.region`)

If Grafana’s SigV4 proxy targets **us-east-2** while Alloy writes to **us-east-1**, Grafana queries return **no data** (wrong regional AMP API), even though federation is healthy.

Pin the CLI when creating the workspace, for example:

```bash
# Use an AWS Region where Amazon Managed Service for Prometheus is available (see AWS documentation).
export REGION=us-east-1
export AWS_DEFAULT_REGION=$REGION
```

---

## Set up environment

1. **Environment variables**

    ```bash
    export CLUSTER=my-cluster
    export REGION=us-east-1
    export PROM_NAMESPACE=custom-metrics
    export PROM_SA=aws-prometheus-proxy
    export SCRATCH_DIR=/tmp/scratch
    export OIDC_PROVIDER=$(oc get authentication.config.openshift.io cluster -o json | jq -r .spec.serviceAccountIssuer | sed -e "s/^https:\/\///")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_PAGER=""
    export AWS_DEFAULT_REGION=$REGION
    mkdir -p $SCRATCH_DIR
    ```

1. **Create namespace**

    ```bash
    oc new-project $PROM_NAMESPACE
    ```

---

## Deploy operators

1. **Add the MOBB chart repository**

    ```bash
    helm repo add mobb https://rh-mobb.github.io/helm-charts/
    helm repo update
    ```

1. **Install operators (Grafana Operator, etc.)**

    ```bash
    helm upgrade -n $PROM_NAMESPACE custom-metrics-operators \
      mobb/operatorhub --install \
      --values https://raw.githubusercontent.com/rh-mobb/helm-charts/main/charts/rosa-aws-prometheus/files/operatorhub.yaml
    ```

1. **Wait for the Grafana Operator deployment**

    ```bash
    oc rollout status deployment grafana-operator-controller-manager-v5 -n $PROM_NAMESPACE
    ```

    Expect: `deployment "grafana-operator-controller-manager-v5" successfully rolled out`.

---

## Deploy and configure AWS SigV4 proxy and Grafana Alloy

The MOBB chart deploys **Grafana Alloy** (not the legacy Grafana Agent) to scrape federation and receive user workload remote write.

### IAM and AMP

Follow the upstream article for JSON policies and role creation. Keep these **production** notes in mind:

- **`AmazonPrometheusFullAccess`** is broad; for tighter access, scope policies to your AMP workspace ARN and required `aps:` actions.
- The trust policy must allow **`system:serviceaccount:${PROM_NAMESPACE}:${PROM_SA}`** and **`system:serviceaccount:${PROM_NAMESPACE}:grafana-sa`** (or the names your chart uses).

### Create AMP workspace (same region as `$REGION`)

```bash
PROM_WS=$(aws amp create-workspace --alias "$CLUSTER" --region "$REGION" \
  --query "workspaceId" --output text)
echo "$PROM_WS"
```

### Deploy `aws-prometheus-proxy` Helm release

Align **`aws.region`**, workspace ID, and **`grafana-cr.sigv4Proxy.region`** with **`$REGION`**. The chart typically sets **`rosa.clusterName`** — use a **stable cluster identifier** so metrics carry a non-empty **`cluster`** label for Grafana dashboard variables (for example **NodeExporter / Use Method / Cluster**).

```bash
helm upgrade --install -n $PROM_NAMESPACE \
  --set "aws.region=$REGION" \
  --set "aws.roleArn=$PROM_ROLE" \
  --set "fullnameOverride=$PROM_SA" \
  --set "aws.workspaceId=$PROM_WS" \
  --set "rosa.clusterName=$CLUSTER" \
  --set "grafana-cr.serviceAccountAnnotations.eks\.amazonaws\.com/role-arn=$PROM_ROLE" \
  --set "grafana-cr.sigv4Proxy.region=$REGION" \
  aws-prometheus-proxy mobb/rosa-aws-prometheus
```

### User workload remote write (ConfigMap only)

This matches the upstream doc: remote write from **UWM** Prometheus to Alloy’s receive endpoint.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-workload-monitoring-config
  namespace: openshift-user-workload-monitoring
data:
  config.yaml: |
    prometheus:
      remoteWrite:
        - url: "http://${PROM_SA}-alloy.${PROM_NAMESPACE}.svc.cluster.local:9999/api/v1/metrics/write"
EOF
```

### Enable User Workload Monitoring (required)

The ConfigMap above **does nothing** until the monitoring stack creates **User Workload Monitoring** Prometheus pods. Enable UWM with **`cluster-monitoring-config`**:

```bash
cat <<EOF | kubectl apply -f -
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

Wait until you see pods such as **`prometheus-user-workload-*`** in **`openshift-user-workload-monitoring`** (often one to three minutes).

---

## Verify metrics

### In the cluster

```bash
# UWM stack
oc get pods -n openshift-user-workload-monitoring
oc get prometheus -n openshift-user-workload-monitoring -o yaml | grep -A20 remoteWrite:

# Alloy
oc get pods -n $PROM_NAMESPACE -l app.kubernetes.io/name=alloy

# Grafana route
echo "https://$(oc get route -n $PROM_NAMESPACE grafana-route -o jsonpath='{.status.ingress[0].host}')"
```

### In Grafana

1. Open the Grafana URL; sign in with **OpenShift** credentials (or local **admin** if you enabled it).
1. **Connections → Data sources:** confirm **`aws-prometheus`** (Prometheus → AMP) and **`cloudwatch`**. Names may vary slightly by chart version; the Prometheus datasource backed by AMP is often **`aws-prometheus`**, not literally **`prometheus`**.
1. **Save & test** on the AMP datasource — it must succeed before dashboards show data.
1. **Dashboards → Browse →** folder **`aws-prometheus-proxy`** (or similar) → **NodeExporter / Use Method / Cluster**.
1. Set dashboard variables (for example **`cluster`**, **`datasource`**) — if **`cluster`** is empty, fix **`external_labels.cluster`** / **`rosa.clusterName`** in Helm and redeploy.

### If datasources are missing (race)

Reconcile the release; with **Grafana Operator v5** the API group is **`grafana.integreatly.org`**, not **`integreatly.org`** alone:

```bash
kubectl delete grafanadatasource -n $PROM_NAMESPACE aws-prometheus-proxy-aws-prometheus

helm upgrade --install -n $PROM_NAMESPACE \
  --set "aws.region=$REGION" \
  --set "aws.roleArn=$PROM_ROLE" \
  --set "fullnameOverride=$PROM_SA" \
  --set "aws.workspaceId=$PROM_WS" \
  --set "grafana-cr.serviceAccountAnnotations.eks\.amazonaws\.com/role-arn=$PROM_ROLE" \
  --set "grafana-cr.sigv4Proxy.region=$REGION" \
  aws-prometheus-proxy mobb/rosa-aws-prometheus
```

Adjust the **GrafanaDatasource** resource name if your release differs (`kubectl get grafanadatasource -n $PROM_NAMESPACE`).

---

## Troubleshooting

| Symptom | Things to check |
|--------|-------------------|
| **No data in Grafana**, datasource test fails | **Region mismatch** between SigV4 proxy and AMP workspace; **`aws.region`** / **`sigv4Proxy.region`** / **`AWS_DEFAULT_REGION`**. |
| **Empty `cluster` variable** on dashboards | Empty or missing **`cluster`** label on series; set **`rosa.clusterName`** / Alloy **`external_labels.cluster`** per chart. |
| **No UWM pods** | Missing **`cluster-monitoring-config`** with **`enableUserWorkload: true`**. |
| **AMP remote write 400 / out-of-order** | Multiple writers sending the same series; confirm chart replica/scrape design (federation from several Alloy pods can duplicate series — consult MOBB chart defaults and AWS AMP limits). |
| **Datasource CR not deleting** | Use **`kubectl api-resources \| grep -i grafana`** and delete **`grafanadatasource.grafana.integreatly.org`**. |

---

## Federation and Alloy replicas

If several Alloy instances scrape the **same** federation target and **remote_write** the same series to AMP, you can see **duplicate** or **out-of-order** samples. Prefer the chart’s recommended topology (often a **DaemonSet** for node-local scrape — here federation is cluster-scoped, so validate whether a **single-replica** scraper or deduplication is more appropriate for your environment).

---

## Cleanup (order matters)

1. Remove Helm releases in **`$PROM_NAMESPACE`** (`aws-prometheus-proxy`, then `custom-metrics-operators` as in the upstream doc).
1. Delete the **`custom-metrics`** namespace when ready.
1. **Detach** IAM policies from the role, then **delete** the custom CloudWatch policy and **IAM role**.
1. **Delete the AMP workspace** last (or after nothing is writing to it).

---

## References

- [ROSA - Federating Metrics to AWS Prometheus (Red Hat Cloud Experts)](https://cloud.redhat.com/experts/rosa/cluster-metrics-to-aws-prometheus/)
- [MOBB Helm charts](https://github.com/rh-mobb/helm-charts)
- [Amazon Managed Service for Prometheus documentation](https://docs.aws.amazon.com/prometheus/)

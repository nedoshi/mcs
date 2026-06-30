# Helm Charts for ROSA Operators

This directory contains Helm values files for installing operators on ROSA using the [rh-mobb/helm-charts](https://github.com/rh-mobb/helm-charts) repository.

## Charts Used

| Chart | Purpose |
|-------|---------|
| [operatorhub](https://github.com/rh-mobb/helm-charts/tree/main/charts/operatorhub) | Deploys operators via OperatorHub (Subscriptions, OperatorGroups) |
| [rosa-loki](https://github.com/rh-mobb/helm-charts/tree/main/charts/rosa-loki) | LokiStack + ClusterLogging with S3 backend (optional) |

## Quick Start

### 1. Add the MOBB Helm repository

```bash
helm repo add mobb https://rh-mobb.github.io/helm-charts/
helm repo update
```

### 2. Create required namespaces

```bash
oc create namespace openshift-gitops-operator
oc create namespace openshift-logging
oc create namespace openshift-operators-redhat
```

### 3. Install operators (GitOps, Pipelines, Logging)

```bash
cd cluster-creation/aws/addons/operators/helm-values

helm upgrade --install operators mobb/operatorhub \
  -n openshift-operators \
  -f operatorhub-operators.yaml \
  --create-namespace
```

### 4. (Optional) Deploy LokiStack with S3

After operators are ready and you have S3 configured:

```bash
export CLUSTER_NAME="my-rosa-cluster"
export AWS_REGION="us-east-1"
# Create S3 bucket and IAM credentials first - see rosa-loki README

helm upgrade --install cluster-logging mobb/rosa-loki \
  -n cluster-logging \
  --set "aws_access_key_id=${AWS_ACCESS_KEY_ID}" \
  --set "aws_access_key_secret=${AWS_SECRET_ACCESS_KEY}" \
  --set "aws_region=${AWS_REGION}" \
  --set "aws_s3_bucket_name=rosa-${CLUSTER_NAME}-loki" \
  --create-namespace
```

## Argo CD Integration

To manage via GitOps, create an Argo CD Application that uses Helm:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: operators-helm
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://rh-mobb.github.io/helm-charts/
    chart: operatorhub
    targetRevision: "0.1.2"
    helm:
      valueFiles:
        - https://raw.githubusercontent.com/your-org/your-repo/main/cluster-creation/aws/addons/operators/helm-values/operatorhub-operators.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

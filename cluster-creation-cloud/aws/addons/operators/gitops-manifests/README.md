# GitOps Manifests for ROSA HCP

> **Preferred:** Use [Helm charts from rh-mobb/helm-charts](../helm-values/README.md) for operator installation. This directory provides raw YAML manifests as an alternative.

This directory contains Kubernetes manifests for installing **Pipelines**, **GitOps**, and **Logging** operators on ROSA HCP clusters. These can be applied directly with `oc apply` or managed via Argo CD.

## Directory Structure

```
gitops-manifests/
├── gitops/           # OpenShift GitOps (Argo CD) - install first
│   ├── namespace.yaml
│   ├── operatorgroup.yaml
│   └── subscription.yaml
├── pipelines/       # OpenShift Pipelines (Tekton)
│   ├── operatorgroup.yaml
│   └── subscription.yaml
├── logging/         # OpenShift Logging + Loki
│   ├── 00-namespace-operators-redhat.yaml
│   ├── 01-loki-operatorgroup.yaml
│   ├── 02-loki-subscription.yaml
│   ├── 03-logging-namespace.yaml
│   ├── 04-logging-operatorgroup.yaml
│   ├── 05-logging-subscription.yaml
│   ├── 06-lokistack.yaml.example    # Optional - requires object storage
│   └── 07-clusterlogging.yaml.example  # Optional - requires LokiStack
└── argocd/          # Argo CD Application manifests
    └── operators-application.yaml
```

## Installation Order

1. **GitOps** - Required for Argo CD
2. **Pipelines** - Can be installed in parallel with GitOps
3. **Logging** - Loki operator first, then cluster-logging operator

## Quick Install

```bash
# From project root
cd cluster-creation/aws/addons/operators/gitops-manifests

# 1. GitOps (required first)
oc apply -f gitops/

# 2. Pipelines
oc apply -f pipelines/

# 3. Logging operators
oc apply -f logging/00-namespace-operators-redhat.yaml
oc apply -f logging/01-loki-operatorgroup.yaml
oc apply -f logging/02-loki-subscription.yaml
oc apply -f logging/03-logging-namespace.yaml
oc apply -f logging/04-logging-operatorgroup.yaml
oc apply -f logging/05-logging-subscription.yaml
```

## Logging (LokiStack + ClusterLogging)

The logging operators install the CRDs. To enable log collection:

1. Configure object storage (S3, ODF, etc.)
2. Create secret `logging-loki-s3` in `openshift-logging`
3. Apply `06-lokistack.yaml` (copy from `.example`)
4. Wait for LokiStack to be Ready
5. Apply `07-clusterlogging.yaml` (copy from `.example`)

See the main guide for details: [ROSA-HCP-EXTERNAL-AUTH-GITOPS-GUIDE.md](../ROSA-HCP-EXTERNAL-AUTH-GITOPS-GUIDE.md)

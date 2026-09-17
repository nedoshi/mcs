# UC-06 — Terraform: OpenShift Project and Helm release

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 6.

## Summary

Use **Terraform** with **kubernetes** and **helm** providers to create an OpenShift **Project** and deploy a **Helm** chart (Bitnami nginx) into it.

## Why this matters

- GitOps/IaC teams manage namespaces and app releases outside the console.
- Validates API token auth to ROSA API and Helm provider wiring.
- Day-2 pattern after cluster provision via [tf-rosa](../../../cluster-creation-cloud/aws/tf-rosa/) or `rosa`.

## Architecture

```
 [Terraform]
     | token
     v
 [OpenShift API] --> Project CR (marketing-apps)
     |
     v
 [Helm release] --> nginx (Bitnami chart)
```

## Prerequisites

- Cluster API URL and OAuth/admin token (`openshift_token` sensitive var).
- Terraform >= 1.5, providers `hashicorp/kubernetes`, `hashicorp/helm`.

```bash
export OPENSHIFT_API="https://api.${CLUSTER_NAME}.openshiftapps.com:6443"
export OPENSHIFT_TOKEN="$(oc whoami -t)"
```

## Steps

1. Create `main.tf` (from PDF — adjust host/token):

   ```hcl
   terraform {
     required_version = ">= 1.5.0"
     required_providers {
       kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25.0" }
       helm       = { source = "hashicorp/helm", version = "~> 2.12.0" }
     }
   }

   provider "kubernetes" {
     host                   = var.openshift_api
     token                  = var.openshift_token
     insecure               = false
   }

   provider "helm" {
     kubernetes {
       host                   = var.openshift_api
       token                  = var.openshift_token
       insecure               = false
     }
   }

   resource "kubernetes_manifest" "app_project" {
     manifest = {
       apiVersion = "project.openshift.io/v1"
       kind       = "Project"
       metadata = {
         name = "marketing-apps"
         labels = { environment = "production" }
       }
     }
   }

   resource "helm_release" "nginx_webserver" {
     name       = "internal-webserver"
     repository = "https://charts.bitnami.com/bitnami"
     chart      = "nginx"
     version    = "15.4.4"
     namespace  = "marketing-apps"
     depends_on = [kubernetes_manifest.app_project]
     set { name = "replicaCount"; value = "2" }
     set { name = "service.type"; value = "ClusterIP" }
   }
   ```

2. Apply:

   ```bash
   terraform init
   terraform apply -var="openshift_api=${OPENSHIFT_API}" -var="openshift_token=${OPENSHIFT_TOKEN}"
   ```

3. Verify:

   ```bash
   oc get project marketing-apps
   oc get pods -n marketing-apps -l app.kubernetes.io/name=nginx
   helm list -n marketing-apps
   ```

## Expected output

- Terraform apply succeeds.
- Project `Active`; two nginx pods `Running`.

## Success criteria

```bash
oc get project marketing-apps -o jsonpath='{.status.phase}' | grep -q Active
oc get deploy -n marketing-apps -o jsonpath='{.items[0].status.readyReplicas}' | grep -q 2
```

## Failure signals

- 401 on provider → expired token.
- Project exists conflict → import or choose new name.
- Helm chart pull failure → network or chart version retired.

## Cleanup

```bash
terraform destroy -var="openshift_api=${OPENSHIFT_API}" -var="openshift_token=${OPENSHIFT_TOKEN}"
```

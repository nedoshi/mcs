# End-to-End TLS Termination with Azure Front Door and Azure Red Hat OpenShift (ARO)

This document is a **Red Hat–style procedural guide** with **step-by-step commands and example outputs** for configuring **TLS termination at Azure Front Door in front of a *private* Azure Red Hat OpenShift (ARO) cluster**.

Audience:
- New to networking / TLS
- Platform, SRE, or cloud engineers

Assumptions:
- ARO is **private** (no public API / ingress)
- Azure Front Door (Standard/Premium)
- TLS is terminated at Front Door

---

## 1. Architecture Overview

```
Client (Browser)
   |
   | HTTPS (Public TLS)
   v
Azure Front Door (WAF + TLS termination)
   |
   | HTTPS (Private)
   v
Private Endpoint / Internal Load Balancer
   |
   v
ARO Ingress Router
   |
   v
Application Pod
```

---

## 2. Prerequisites

### 2.1 Required Tools

```bash
az version
oc version
```

Example output:
```
az-cli                         2.57.0
openshift-client               4.18.0
```

---

### 2.2 Azure Variables

```bash
export RESOURCE_GROUP=aro-rg
export ARO_CLUSTER=myaro
export LOCATION=eastus
export FRONTDOOR_NAME=aro-frontdoor
export DOMAIN_NAME=app.example.com
```

---

## 3. Verify ARO Private Ingress

### 3.1 Get Ingress Domain

```bash
oc get ingresscontroller default \
  -n openshift-ingress-operator \
  -o jsonpath='{.status.domain}'
```

Example output:
```
apps.myaro.private.azure.redhat.com
```

This hostname is **internal only**.

---

## 4. Deploy a Sample Application

### 4.1 Create Namespace

```bash
oc new-project tls-demo
```

Output:
```
Now using project "tls-demo" on server https://api.myaro.internal:6443
```

---

### 4.2 Deploy App

```bash
oc new-app quay.io/openshift/origin-hello-openshift
```

---

### 4.3 Expose Route (Edge Termination)

```bash
oc expose svc/origin-hello-openshift --name hello
```

Verify route:

```bash
oc get route hello
```

Output:
```
NAME    HOST/PORT                                           TLS
hello   hello-tls-demo.apps.myaro.private.azure.redhat.com   edge
```

---

## 5. Azure Front Door Setup

### 5.1 Create Front Door Profile

```bash
az afd profile create \
  --name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP \
  --sku Premium_AzureFrontDoor
```

---

### 5.2 Create Endpoint

```bash
az afd endpoint create \
  --endpoint-name aro-endpoint \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP
```

---

### 5.3 Create Origin Group

```bash
az afd origin-group create \
  --origin-group-name aro-origins \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-path /
```

---

### 5.4 Add ARO Ingress as Origin

```bash
az afd origin create \
  --origin-name aro-ingress \
  --origin-group-name aro-origins \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP \
  --host-name apps.myaro.private.azure.redhat.com \
  --https-port 443 \
  --origin-host-header $DOMAIN_NAME
```

---

## 6. Configure Private Connectivity (Required)

### 6.1 Create Private Endpoint

```bash
az network private-endpoint create \
  --name afd-to-aro \
  --resource-group $RESOURCE_GROUP \
  --vnet-name aro-vnet \
  --subnet aro-subnet \
  --private-connection-resource-id /subscriptions/.../internalLoadBalancers/... \
  --group-id loadBalancer
```

(This step is usually performed by the networking team.)

---

## 7. Configure Custom Domain and TLS

### 7.1 Add Custom Domain

```bash
az afd custom-domain create \
  --custom-domain-name app-domain \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP \
  --host-name $DOMAIN_NAME
```

---

### 7.2 Enable Managed TLS

```bash
az afd custom-domain enable-https \
  --custom-domain-name app-domain \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP
```

Output:
```
ProvisioningState: Succeeded
CertificateSource: AzureManaged
```

---

## 8. Routing Rule

```bash
az afd route create \
  --route-name aro-route \
  --profile-name $FRONTDOOR_NAME \
  --resource-group $RESOURCE_GROUP \
  --endpoint-name aro-endpoint \
  --origin-group aro-origins \
  --supported-protocols Https \
  --patterns-to-match "/*" \
  --custom-domains app-domain
```

---

## 9. Security Hardening (Strongly Recommended)

### 9.1 Enable WAF

```bash
az afd waf-policy create \
  --name aro-waf \
  --resource-group $RESOURCE_GROUP \
  --sku Premium_AzureFrontDoor
```

Attach policy to domain.

---

### 9.2 Restrict ARO Ingress to Front Door Only

```bash
oc edit ingresscontroller default -n openshift-ingress-operator
```

Add:
```yaml
spec:
  endpointPublishingStrategy:
    type: Private
```

(Optional IP allowlists may also be applied.)

---

## 10. Validation

### 10.1 Browser Test

```bash
curl -I https://app.example.com
```

Output:
```
HTTP/2 200
server: envoy
```

---

### 10.2 Router Logs

```bash
oc logs -n openshift-ingress deploy/router-default
```

Output:
```
X-Forwarded-Proto=https
Host=app.example.com
```

---

## 11. Certificate Responsibility Matrix

| Segment | TLS Owner |
|------|-----------|
| Browser → Front Door | Azure Front Door |
| Front Door → ARO | Internal TLS |
| ARO → Pod | Optional |

No wildcard certificates required.

---

## 12. Summary

- Public TLS terminates at Azure Front Door
- ARO remains private
- No wildcard certs
- Fully supported enterprise pattern

---

## 13. Troubleshooting

| Symptom | Likely Cause |
|------|------------|
| 502 from Front Door | Private Endpoint/DNS issue |
| TLS error | Origin host header mismatch |
| Health probe fails | Route not reachable |

---

## 14. References

- Azure Front Door Premium
- Azure Red Hat OpenShift 4.18
- Red Hat OpenShift Networking


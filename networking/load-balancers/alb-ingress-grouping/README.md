# ALB Ingress Grouping on ROSA HCP

Share **one AWS Application Load Balancer** across multiple microservices on ROSA with Hosted Control Planes — the OpenShift equivalent of EKS Auto Mode / AWS Load Balancer Controller `IngressGroup`.

Demo apps: `catalog-service` (`/catalog/*`) and `checkout-service` (`/checkout/*`), each with its own Ingress, both reconciled onto a single ALB via `IngressClassParams`.

```
Internet
   │
   ▼
┌─────────────────────────────────────────┐
│  ONE internet-facing ALB                │
│  tag: ingress.k8s.aws/stack=shop-shared-alb
│                                         │
│  /catalog/*  ──► catalog-service (NodePort)
│  /checkout/* ──► checkout-service (NodePort)
└─────────────────────────────────────────┘
   │  target-type: instance
   ▼
 Worker nodes → pods (ALBO does not support IP mode on OpenShift)
```

---

## 1. Architectural overview — EKS vs ROSA HCP

| Concern | EKS (ALB Controller / Auto Mode) | ROSA HCP (AWS Load Balancer Operator) |
|--------|-----------------------------------|----------------------------------------|
| Install | Helm / EKS addon | OLM Operator → `AWSLoadBalancerController` CR |
| Group membership | Annotation `alb.ingress.kubernetes.io/group.name` on each Ingress | **`IngressClassParams.spec.group.name`** (annotation is **disabled**) |
| Ingress class | Annotation or `ingressClassName` | Must use `spec.ingressClassName` (class annotation disabled) |
| Target type | `ip` (common) or `instance` | **`instance` only** (IP mode disabled by ALBO) |
| Service type | Often `ClusterIP` with IP targets | Must be **`NodePort`** for instance mode |
| Rule order | `alb.ingress.kubernetes.io/group.order` | Same annotation — still supported |
| Cost model | 1 ALB per IngressGroup | Same: 1 ALB per `IngressClassParams` group |

### Why ALBO disables `group.name` on Ingress

The Operator starts the controller with:

- `--disable-ingress-group-name-annotation`
- `--disable-ingress-class-annotation`

That forces cluster admins to declare sharing via **`IngressClass` + `IngressClassParams`**, so any developer Ingress that opts into that class joins the shared ALB — no silent cross-tenant annotation hijacking via raw `group.name`.

### Equivalent pattern

**EKS**

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/group.name: shop-shared-alb
    alb.ingress.kubernetes.io/group.order: "10"
```

**ROSA HCP (this demo)**

```yaml
# Cluster-scoped once:
apiVersion: elbv2.k8s.aws/v1beta1
kind: IngressClassParams
metadata:
  name: shop-shared-alb-params
spec:
  group:
    name: shop-shared-alb
---
# Each app Ingress:
spec:
  ingressClassName: shop-shared-alb   # ← joins the group
metadata:
  annotations:
    alb.ingress.kubernetes.io/group.order: "10"  # still valid
    # do NOT set group.name — ignored / rejected by ALBO
```

---

## 2. Prerequisites

- ROSA HCP (or classic ROSA STS) cluster, multi-AZ recommended
- `oc` logged in as a user who can create cluster-scoped `IngressClass` / `IngressClassParams`
- `aws` CLI with IAM permissions to create roles/policies (for ALBO install)
- Public subnets tagged `kubernetes.io/role/elb` (ROSA-managed VPC usually already is; BYO VPC: see install script)

### Enable AWS Load Balancer Controller (ALBO)

```bash
cd networking/load-balancers/alb-ingress-grouping
chmod +x scripts/install-albo.sh deploy.sh cleanup.sh

# Optional for BYO VPC:
# export VPC_ID=vpc-xxx
# export PUBLIC_SUBNET_IDS="subnet-aaa subnet-bbb"
# export PRIVATE_SUBNET_IDS="subnet-ccc subnet-ddd"

./scripts/install-albo.sh
```

Verify:

```bash
oc get pods -n aws-load-balancer-operator
oc get awsloadbalancercontroller cluster -o yaml
oc get crd ingressclassparams.elbv2.k8s.aws
```

You should see Operator + Controller pods `Running`, and CRD present.

---

## 3. Application manifests

| File | Purpose |
|------|---------|
| `manifests/00-namespace.yaml` | `shop-demo` project |
| `manifests/10-ingressclass.yaml` | `IngressClassParams` group + `IngressClass` |
| `manifests/20-catalog-service.yaml` | Deployment, **NodePort** Service, BuildConfig, ImageStream |
| `manifests/30-checkout-service.yaml` | Same for checkout |
| `manifests/40-ingress-catalog.yaml` | Ingress → `/catalog` (order 10) |
| `manifests/50-ingress-checkout.yaml` | Ingress → `/checkout` (order 20) |

Source apps live under `apps/{catalog,checkout}-service/` (UBI9 Node.js Express APIs).

---

## 4. Ingress configuration (shared ALB)

Key annotations on both Ingresses:

```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: instance
alb.ingress.kubernetes.io/group.order: "10"   # or "20"
alb.ingress.kubernetes.io/healthcheck-path: /health
```

Shared class:

```yaml
spec:
  ingressClassName: shop-shared-alb
```

Proof of consolidation: both Ingresses report the **same** `.status.loadBalancer.ingress[0].hostname`.

---

## 5. Deploy

```bash
./deploy.sh
```

What it does:

1. Applies `IngressClassParams` / `IngressClass` (`shop-shared-alb`)
2. Creates BuildConfigs and binary-builds both images
3. Rolls out Deployments + NodePort Services
4. Applies both Ingresses
5. Prints the shared ALB DNS and sample curls

### Manual verify

```bash
# Same hostname on both?
oc get ingress -n shop-demo \
  -o custom-columns=NAME:.metadata.name,HOST:.status.loadBalancer.ingress[0].hostname,CLASS:.spec.ingressClassName

ALB=$(oc get ingress catalog-ingress -n shop-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -s "http://${ALB}/catalog/products" | jq .
curl -s "http://${ALB}/checkout/" | jq .
curl -s -X POST "http://${ALB}/checkout/orders" \
  -H 'Content-Type: application/json' \
  -d '{"items":[{"sku":"sku-1001","qty":1}]}' | jq .
```

AWS Console / CLI:

```bash
aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[].LoadBalancerArn" --output text) \
  --query "TagDescriptions[?Tags[?Key=='ingress.k8s.aws/stack' && Value=='shop-shared-alb']]"
```

---

## 6. Cleanup

```bash
./cleanup.sh
```

Removes demo namespace, Ingresses (triggers ALB delete), workloads, and the demo `IngressClass`. Leaves ALBO installed.

---

## Cost talking points (for workshops)

- Default OpenShift Routes → often **one NLB/ALB per IngressController** or per router shard, not per app path group you control.
- Naive pattern: **1 ALB per Ingress** → ~\$16+/mo/ALB + LCU, plus quota pressure.
- This pattern: **N Ingresses → 1 ALB** via IngressGroup, path/host rules merged — same as EKS Auto Mode Ingress grouping, expressed the ALBO-safe way.
- `group.order` controls listener-rule priority when paths could overlap.

---

## Troubleshooting

| Symptom | Check |
|--------|--------|
| Ingress never gets hostname | Controller logs: `oc logs -n aws-load-balancer-operator -l app.kubernetes.io/name=aws-load-balancer-controller` |
| `Failed build security group` / subnet errors | Public subnets missing `kubernetes.io/role/elb`; set `subnetTagging: Auto` or tag manually |
| 504 / unhealthy targets | Service must be `NodePort`; health path `/health` must return 200 |
| Two different ALB hostnames | Ingresses not sharing `ingressClassName: shop-shared-alb`, or `IngressClassParams.group.name` missing |
| Annotation `group.name` ignored | Expected on ROSA — move group into `IngressClassParams` |

---

## Layout

```
alb-ingress-grouping/
├── README.md
├── deploy.sh
├── cleanup.sh
├── scripts/
│   └── install-albo.sh
├── apps/
│   ├── catalog-service/{Dockerfile,package.json,server.js}
│   └── checkout-service/{Dockerfile,package.json,server.js}
└── manifests/
    ├── 00-namespace.yaml
    ├── 10-ingressclass.yaml      # IngressClassParams + IngressClass
    ├── 20-catalog-service.yaml
    ├── 30-checkout-service.yaml
    ├── 40-ingress-catalog.yaml
    └── 50-ingress-checkout.yaml
```

## References

- [Creating multiple Ingresses through a single ALB (OpenShift)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/networking_operators/aws-load-balancer-operator-1#creating-multiple-ingress-through-single-alb)
- [AWS Load Balancer Operator on ROSA](https://cloud.redhat.com/experts/rosa/aws-load-balancer-operator/)
- [AWS LB Controller IngressGroup annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/#ingressgroup)

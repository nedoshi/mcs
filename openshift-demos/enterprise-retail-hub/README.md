# Enterprise Retail Hub

A multi-tier **enterprise e-commerce** demo for **ROSA** and **ARO**, adapted from patterns in [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) (Hipster Shop) and Spring Cloud retail microservices ([kuturogi/ecom-microservices](https://github.com/kuturogi/ecom-microservices)).

Browse an IT procurement catalog, add items to a persistent cart, and place orders — all running as separate microservices on OpenShift with a single public Route.

## Project Overview

| Aspect | Detail |
|--------|--------|
| **Domain** | Enterprise IT procurement (laptops, licenses, networking gear) |
| **Architecture** | 4 microservices + API gateway + PostgreSQL |
| **Runtime** | Node.js 20 on UBI9 (non-root containers) |
| **Data** | PostgreSQL with PVC (catalog, carts, orders) |
| **Ingress** | One OpenShift Route → frontend → internal gateway |

### OpenShift Developer Value

| Feature | What to show |
|---------|--------------|
| **Topology view** | 6 workloads wired together — gateway fans out to catalog/cart/order |
| **BuildConfigs** | UBI-based Docker builds pushed to internal ImageStream |
| **Routes** | Edge TLS termination; single URL for the storefront |
| **Secrets / ConfigMaps** | DB credentials and service discovery URLs injected as env |
| **Health probes** | Every service exposes `/health` with DB checks on stateful tiers |
| **HPA** | `catalog-service` and `frontend` auto-scale on CPU (if metrics-server present) |
| **Security context** | `runAsNonRoot`, dropped capabilities — SCC-friendly |
| **Scaling demo** | `oc scale deployment/catalog-service --replicas=3` — cart stays consistent via PostgreSQL |

## Directory Structure

```
enterprise-retail-hub/
├── README.md
├── deploy.sh                          # One-command full deploy
├── database/
│   └── init.sql                       # Reference schema (also embedded in ConfigMap)
├── services/
│   ├── shared/db.js                   # PostgreSQL pool helper
│   ├── catalog-service/               # Product catalog API
│   ├── cart-service/                  # Session cart (PostgreSQL-backed)
│   ├── order-service/                 # Checkout + inventory decrement
│   ├── api-gateway/                   # North-south routing + correlation IDs
│   └── frontend/                      # Storefront UI + /api proxy
├── openshift/
│   ├── postgres.yaml                  # Secret, PVC, Deployment, init ConfigMap
│   ├── config.yaml                    # DB secret + service URL ConfigMap
│   ├── buildconfigs.yaml              # ImageStreams + Docker BuildConfigs
│   ├── microservices.yaml             # Deployments, Services, Route
│   └── hpa.yaml                       # HorizontalPodAutoscalers
└── scripts/
    └── cleanup.sh                     # Delete the retail-hub project
```

## Architecture

```
                    ┌─────────────┐
   User ──────────► │   Route     │ (TLS edge)
                    │  frontend   │
                    └──────┬──────┘
                           │ /api/*
                    ┌──────▼──────┐
                    │ api-gateway │
                    └──┬───┬───┬──┘
           ┌───────────┘   │   └───────────┐
    ┌──────▼──────┐ ┌─────▼─────┐ ┌───────▼───────┐
    │catalog-svc  │ │ cart-svc  │ │  order-svc    │
    └──────┬──────┘ └─────┬─────┘ └───────┬───────┘
           └──────────────┼───────────────┘
                    ┌─────▼─────┐
                    │ postgres  │ (PVC)
                    └───────────┘
```

## Prerequisites

- ROSA or ARO cluster with cluster-admin or project-create permissions
- `oc` CLI logged in (`oc login`)
- **Cluster capacity:** ~2 CPU / 2 Gi RAM for all pods (requests are modest; limits allow burst)
- Optional: OpenShift Pipelines for CI/CD extension demo

## Quick Deploy

From this directory:

```bash
./deploy.sh
```

The script:

1. Creates the `retail-hub` project
2. Deploys PostgreSQL with seed data
3. Builds all 5 container images via OpenShift BuildConfigs
4. Applies Deployments, Services, Route, and HPA
5. Prints the storefront URL

Custom namespace:

```bash
NAMESPACE=my-demo ./deploy.sh
```

## Manual Deploy (step-by-step)

```bash
oc new-project retail-hub

# Database + config
oc apply -f openshift/postgres.yaml
oc apply -f openshift/config.yaml
oc wait --for=condition=available deployment/postgres -n retail-hub --timeout=300s

# Build images (run from demo root)
oc apply -f openshift/buildconfigs.yaml
for svc in catalog-service cart-service order-service api-gateway frontend; do
  oc start-build "$svc" --from-dir=. --wait --follow -n retail-hub
done

# Deploy workloads
oc apply -f openshift/microservices.yaml
oc apply -f openshift/hpa.yaml   # skip if no metrics-server

oc get route frontend -n retail-hub
```

## Live Demo Script

### 1. Topology tour (2 min)

Open **Developer → Topology** in the `retail-hub` project. Point out:

- Single public Route on `frontend`
- Internal services not exposed externally
- BuildConfigs linked to ImageStreams

### 2. Build → Deploy flow (3 min)

```bash
oc logs -f bc/frontend -n retail-hub    # show UBI9 Node build
oc get pods -n retail-hub -w
```

Highlight: images land in the internal registry — no Docker Hub push required.

### 3. Application walkthrough (5 min)

1. Open the Route URL
2. Add a laptop and monitor to cart
3. Checkout with a work email
4. Show order confirmation with order number
5. Refresh catalog — stock counts decremented

### 4. Resilience & scale (3 min)

```bash
# Scale catalog tier
oc scale deployment/catalog-service --replicas=3 -n retail-hub

# Watch HPA (if applied)
oc get hpa -n retail-hub -w

# Tail gateway logs — correlation IDs
oc logs deployment/api-gateway -n retail-hub --tail=20
```

### 5. Config change rollout (2 min)

```bash
oc set env deployment/frontend APP_BANNER="ROSA Demo" -n retail-hub
oc rollout status deployment/frontend -n retail-hub
```

### 6. Developer talking points

- **Compared to monolith:** independent deploy/scale per service
- **Compared to VMs:** declarative manifests, rolling updates, built-in load balancing
- **OpenShift extras:** Routes, BuildConfigs, Topology, integrated registry, SCC-aware defaults
- **Next steps:** Service Mesh (see `demo-deploying-an-app-with-service-mesh`), GitOps (see `deploying-gitops-on-rosa-or-aro`), OpenShift Pipelines

## API Endpoints (via frontend proxy)

| Method | Path | Service |
|--------|------|---------|
| GET | `/api/products` | catalog-service |
| GET | `/api/products/:id` | catalog-service |
| GET | `/api/cart/:sessionId` | cart-service |
| POST | `/api/cart/:sessionId/items` | cart-service |
| POST | `/api/orders` | order-service |
| GET | `/api/orders/:orderNumber` | order-service |
| GET | `/health` | all services |

## Import from Git (alternative)

To demo **Developer Console → Import from Git** per service:

1. Push this repo to GitHub
2. For each service, use **+ Add → Import from Git** with:
   - **Context dir:** `openshift-demos/enterprise-retail-hub/services/<service-name>`
   - **Builder:** Node.js (for S2I) *or* point BuildConfig at the Dockerfile

For the full multi-service topology, `deploy.sh` with Docker BuildConfigs is faster and more reliable.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails `COPY services/shared` | Run `oc start-build` with `--from-dir=.` from the **demo root**, not the service subfolder |
| Pods `CrashLoopBackOff` on catalog/cart/order | Rebuild after `shared/db` path fix: `oc start-build catalog-service --from-dir=. --wait -n retail-hub` (repeat for cart, order), then `oc rollout restart deployment/catalog-service -n retail-hub` |
| Pods `ImagePullBackOff` | Wait for builds to finish: `oc get builds -n retail-hub` |
| Catalog pod `503` on `/health` | Postgres not ready: `oc logs deployment/postgres -n retail-hub` |
| Postgres `role "retail" does not exist` | Stale PVC from prior `postgres:alpine` deploy. Fix in place: `oc delete job db-init -n retail-hub --ignore-not-found && oc apply -f openshift/postgres.yaml && oc wait --for=condition=complete job/db-init -n retail-hub --timeout=180s`. Clean slate: `oc delete pvc postgres-data -n retail-hub` then redeploy |
| Postgres SCC / `fsGroup 999` forbidden | Use Red Hat image in `openshift/postgres.yaml` (not `postgres:alpine`) |
| PVC pending | Check storage class: `oc get pvc -n retail-hub` |
| HPA shows `<unknown>` | Metrics server warming up; wait 2–3 min or skip HPA |

```bash
# Useful debug commands
oc get pods,builds,route -n retail-hub
oc describe pod -l app=catalog-service -n retail-hub
oc rsh deployment/postgres -n retail-hub -- psql -U retail -c 'SELECT sku, stock FROM products;'
```

## Cleanup

```bash
./scripts/cleanup.sh
# or
oc delete project retail-hub
```

## Source Attribution

- Architecture inspired by [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo) (Online Boutique / Hipster Shop)
- Enterprise service decomposition patterns from [kuturogi/ecom-microservices](https://github.com/kuturogi/ecom-microservices)
- OpenShift deployment conventions aligned with [rosa-101-welcome](../rosa-101-welcome/)

## License

Demo code in this directory is provided for educational workshops. Upstream inspirations retain their respective licenses.

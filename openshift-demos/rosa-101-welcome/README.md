# ROSA 101 Welcome Demo

A minimal single-service web app for **ROSA 101** workshops. Inspired by [CoolStore web-nodejs](https://github.com/OpenShiftDemos/web-nodejs) but stripped down to one container — no database, no gateway, no mesh.

**Good for demonstrating:**
- Developer Console → **Import from Git**
- Build → Deploy → Route
- Scaling replicas and seeing which pod serves traffic
- Health probes and resource requests

## What's in the box

| Component | Purpose |
|-----------|---------|
| `server.js` | Express API + static UI |
| `public/` | Simple catalog page with runtime info |
| `Dockerfile` | UBI9 Node.js 20 image for OpenShift builds |
| `kubernetes/deployment.yaml` | Optional manifests for `oc apply` |

**Endpoints:**
- `/` — demo UI
- `/health` — liveness/readiness probe
- `/api/info` — pod name, namespace, version
- `/api/products` — static catalog (no DB)

## Deploy: Import from Git (recommended)

Use this path in the OpenShift **Developer** perspective.

1. Switch to **Developer** perspective → **+ Add** → **Import from Git**
2. Set:
   - **Git repo URL:** your fork of this repo (or the upstream URL once pushed)
   - **Context dir:** `openshift-demos/rosa-101-welcome`
   - **Builder:** Dockerfile
   - **Resource type:** Deployment
   - **Create a route:** checked
3. Click **Create**

OpenShift creates a BuildConfig, ImageStream, Deployment, Service, and Route. Watch the build in **Topology**, then open the route URL.

### Demo talking points

1. **First deploy** — show build logs, pod coming up, route created
2. **Scale** — `oc scale deployment/rosa-101-welcome --replicas=3` (or use the UI); refresh the page and note the **Pod** field changing
3. **Config** — add env var `WELCOME_MESSAGE` on the Deployment and roll out

## Deploy: CLI (import from Git)

```bash
oc new-project rosa-101-demo

oc new-app https://github.com/YOUR_ORG/mcs.git \
  --context-dir=openshift-demos/rosa-101-welcome \
  --name=rosa-101-welcome

oc expose svc/rosa-101-welcome
oc get route rosa-101-welcome
```

Replace `YOUR_ORG/mcs` with your Git remote.

## Deploy: pre-built manifests

If you already built and pushed an image to the cluster's internal registry:

```bash
# Build locally and push, or use the cluster build from above first
oc apply -f kubernetes/deployment.yaml

# Point deployment at your built image if needed:
oc set image deployment/rosa-101-welcome \
  rosa-101-welcome=image-registry.openshift-image-registry.svc:5000/rosa-101-demo/rosa-101-welcome:latest \
  -n rosa-101-demo
```

## Local run

```bash
cd openshift-demos/rosa-101-welcome
npm install
npm start
# http://localhost:8080
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Listen port |
| `WELCOME_MESSAGE` | `Welcome to ROSA!` | Hero title text |
| `APP_VERSION` | `1.0.0` | Shown in runtime panel |
| `POD_NAME` | hostname | Set via downward API in manifests |
| `OPENSHIFT_NAMESPACE` | `local` | Set via downward API in manifests |

## Cleanup

```bash
# If deployed via import from git in project rosa-101-demo:
oc delete project rosa-101-demo

# If applied manifests directly:
oc delete -f kubernetes/deployment.yaml
```

## Why not CoolStore?

[CoolStore](https://github.com/OpenShiftDemos/web-nodejs) needs catalog, inventory, gateway, and database services — great for microservices demos, heavy for a 30-minute ROSA intro. This app gives you a visual storefront and pod identity in one git import.

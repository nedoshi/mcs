# ROSA 101 Welcome Demo

A minimal single-service web app for **ROSA 101** workshops. Inspired by [CoolStore web-nodejs](https://github.com/OpenShiftDemos/web-nodejs) but stripped down to one container — no database, no gateway, no mesh.

**Good for demonstrating:**
- Developer Console → **Import from Git**
- Build → Deploy → Route
- Scaling replicas and seeing which pod serves traffic
- Health probes and resource requests/limits (see [kubernetes/DEMO-resource-limits.md](kubernetes/DEMO-resource-limits.md))

## What's in the box

| Component | Purpose |
|-----------|---------|
| `server.js` | Express API + static UI |
| `public/` | Simple catalog page with runtime info |
| `package.json` | Node.js S2I build (recommended for import) |
| `docker/Dockerfile` | Optional container build (not in repo root on purpose) |
| `kubernetes/deployment.yaml` | Optional manifests for `oc apply` after build |
| `kubernetes/load-test-job.yaml` | Load test Job for resource limits demo |
| `kubernetes/limit-range.yaml` | LimitRange for quota workshop |
| `kubernetes/resource-quota.yaml` | ResourceQuota for quota workshop |
| `kubernetes/DEMO-resource-limits.md` | Step-by-step resource limits workshop script |
| `scripts/demo-resource-limits.sh` | Interactive instructor demo script |
| `openshift/buildconfig-nodejs.yaml` | Fallback build definition |

**Endpoints:**
- `/` — demo UI
- `/health` — liveness/readiness probe
- `/api/info` — pod name, namespace, version
- `/api/products` — static catalog (no DB)

## Deploy: Import from Git (recommended)

Use this path in the OpenShift **Developer** perspective.

1. **Delete any failed attempt first** (see [Troubleshooting](#troubleshooting) if you already hit `manifest unknown`)
2. Developer → **+ Add** → **Import from Git**
3. Set:
   - **Git repo URL:** `https://github.com/nedoshi/mcs.git` (repo root only — see below)
   - **Git reference:** `main`
   - **Context dir:** `openshift-demos/rosa-101-welcome`
   - **Builder Image:** **Node.js** (auto-detected from `package.json`)
   - **Resource type:** Deployment
   - **Create a route:** checked

   **Wrong (browser URL — will fail clone):**
   ```
   https://github.com/nedoshi/mcs/tree/main/openshift-demos/rosa-101-welcome
   ```

   **Right (two separate fields):**
   ```
   Git repo URL:  https://github.com/nedoshi/mcs.git
   Context dir:   openshift-demos/rosa-101-welcome
   Git ref:       main
   ```
4. **Important:** do **not** choose Dockerfile builder and do **not** deploy a pre-existing image named `rosa-demo:latest`
5. Click **Create**

OpenShift creates a BuildConfig (Git + S2I), ImageStream, Deployment, Service, and Route. Watch the build in **Topology**, then open the route URL.

> **Why Node.js, not Dockerfile?** A root-level `Dockerfile` can cause the console to create a Docker build that pulls `image-registry.../rosa-demo:latest` before any image exists (`manifest unknown`). The Dockerfile lives under `docker/` for optional use; import uses S2I instead.

### Demo talking points

1. **First deploy** — show build logs, pod coming up, route created
2. **Scale** — `oc scale deployment/rosa-demo --replicas=3` (or use the UI); refresh the page and note the **Pod** field changing
3. **Config** — add env var `WELCOME_MESSAGE` on the Deployment and roll out
4. **Resources** — run `./scripts/demo-resource-limits.sh rosa-demo rosa-demo`

## Deploy: CLI (import from Git)

```bash
oc new-project rosa-demo

oc new-app https://github.com/YOUR_ORG/mcs.git \
  --context-dir=openshift-demos/rosa-101-welcome \
  --image-stream=nodejs \
  --name=rosa-demo

oc expose svc/rosa-demo
oc get route rosa-demo
```

Replace `YOUR_ORG/mcs` with your Git remote.

## Deploy: pre-built manifests

Only use this **after** a successful build pushed an image to the internal registry:

```bash
oc apply -f kubernetes/deployment.yaml

oc set image deployment/rosa-demo \
  rosa-demo=image-registry.openshift-image-registry.svc:5000/rosa-demo/rosa-demo:latest \
  -n rosa-demo
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

## Troubleshooting

### `requested repository ... not found`

You pasted the **GitHub browser URL** (`/tree/main/...`) into the Git repo field. OpenShift clones the repository root, not a folder path in the URL.

Use:
- **Git repo URL:** `https://github.com/nedoshi/mcs.git`
- **Context dir:** `openshift-demos/rosa-101-welcome`
- **Git ref:** `main`

### `manifest unknown` for `image-registry.../rosa-demo:latest`

OpenShift tried to **pull** an image from the internal registry instead of **building from Git**. Common causes:

- Dockerfile builder selected on first deploy (image does not exist yet)
- Deployment configured with image `rosa-demo:latest` without a completed build
- Retrying after a failed import left a broken BuildConfig/ImageStream

**Fix — wipe and re-import with Node.js builder:**

```bash
# In your project (e.g. rosa-demo)
oc delete route,svc,deploy,bc,is -l app=rosa-demo 2>/dev/null || true
oc delete route,svc,deploy,bc,is rosa-demo 2>/dev/null || true
```

Then re-run **Import from Git** with **Node.js** builder (steps above).

**Fallback — explicit BuildConfig:**

```bash
# Edit openshift/buildconfig-nodejs.yaml: set your GIT_REPO
oc apply -f openshift/buildconfig-nodejs.yaml -n rosa-demo
oc start-build rosa-demo -n rosa-demo --wait
oc new-app rosa-demo:latest --name=rosa-demo -n rosa-demo
oc expose svc/rosa-demo -n rosa-demo
```

### Build succeeds but route returns 503

Wait for the deployment rollout; check `oc get pods` and `oc logs deploy/rosa-demo`.

### Catalog empty / page still shows `Loading...` and `/app.js`

Your cluster is still running an **old image**. The live HTML should include product cards directly (no `/app.js`).

Verify what is deployed:

```bash
curl -sI https://YOUR_ROUTE/ | grep -i x-build-id
curl -s https://YOUR_ROUTE/ | grep -E 'product-card|app.js'
```

- **No `X-Build-Id` header** and **`app.js` in HTML** → old build still serving
- **Fix:** push latest code to GitHub, then force a rebuild:

```bash
git add openshift-demos/rosa-101-welcome
git commit -m "fix: embed static catalog in index.html for ROSA demo"
git push origin main

oc start-build rosa-demo -n rosa-demo --wait
oc rollout restart deployment/rosa-demo -n rosa-demo
oc rollout status deployment/rosa-demo -n rosa-demo
```

Hard-refresh the browser (`Cmd+Shift+R`) after rollout completes.

## Cleanup

```bash
oc delete project rosa-demo
# or
oc delete -f kubernetes/deployment.yaml
```

## Why not CoolStore?

[CoolStore](https://github.com/OpenShiftDemos/web-nodejs) needs catalog, inventory, gateway, and database services — great for microservices demos, heavy for a 30-minute ROSA intro. This app gives you a visual storefront and pod identity in one git import.

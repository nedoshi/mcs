# ING-06 — OpenShift Service Mesh (Istio)

**Provenance:** [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §6.

## Summary

Deploy **OpenShift Service Mesh** (Istio-based) for L7 **canary/blue-green** splits, retries, circuit breaking, and **mTLS** between microservices; optional **Envoy ingress gateway** for north-south traffic.

## Why this matters

- Microservice teams need traffic shifting without multiple physical ingress tiers.
- Resilience patterns (retries, outlier detection) at sidecar level.
- Complements Routes (ING-01) for east-west; mesh gateway for advanced ingress.

## Architecture

```
 [Client]
    |
 [Envoy Ingress Gateway] (optional)
    |
 [Service A sidecar] <--mTLS--> [Service B sidecar]
    |
 VirtualService / DestinationRule (canary weights)
```

## Prerequisites

- Cluster resources for control plane + data plane (istio-system, etc.).
- For Entra-integrated mesh auth scenarios see [rosa_service_mesh_entraid.md](../../troubleshooting/ROSA/rosa_service_mesh_entraid.md)—this runbook covers generic install smoke.

## Steps

1. Install **Red Hat OpenShift Service Mesh** operator and create `ServiceMeshControlPlane` (version aligned to cluster OCP).

   ```bash
   oc get csv -n openshift-operators | grep -i servicemesh
   oc get servicemeshcontrolplane -n istio-system
   ```

2. Label namespace for injection:

   ```bash
   oc create namespace mesh-demo
   oc label namespace mesh-demo istio-injection=enabled
   ```

3. Deploy two versions of a sample app (v1/v2) and a `VirtualService` with weighted routes (e.g. 90/10 canary).

4. Generate load; confirm traffic split via access logs or Kiali (if installed).

5. (Optional) Configure `Gateway` + `VirtualService` for external ingress through mesh gateway.

## Expected output

- SMCP `Ready`
- Sidecars injected (`oc get pod -n mesh-demo -o jsonpath='{.items[0].spec.containers[*].name}'` includes `istio-proxy`)
- Canary ratio observable under load

## Success criteria

```bash
oc get servicemeshcontrolplane -n istio-system -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q True
oc get pods -n mesh-demo -o json | jq -e '.items[0].spec.containers | map(.name) | index("istio-proxy")'
```

## Failure signals

- SMCP not Ready → incompatible versions, insufficient resources.
- No sidecar → missing injection label or revision tags.
- mTLS errors → PeerAuthentication / DestinationRule policy mismatch.

## Rollout safety (PDF)

- L7 traffic shifting replaces ALB readiness gates for in-mesh rollouts; combine with health checks on workload pods.

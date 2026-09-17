# ING-01 — OpenShift Ingress Controller (Routes and HAProxy)

**Provenance:** [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §1.

## Summary

Validate the **default OpenShift Ingress Controller** (HAProxy router): expose apps with **Route** objects, TLS termination modes (edge, passthrough, reencrypt), and rollout safety via readiness probes and EndpointSlices.

## Why this matters

- Default path for OpenShift apps; no extra AWS controllers required.
- HAProxy talks to **pod overlay IPs** directly on OVN—no NodePort translation for standard Routes.
- cert-manager / External DNS optional for automated certs and Route53 sync.

## Architecture

```
 Internet or corp network
        |
        v
 [Route host apps.example.com]
        |
 [IngressController / router-default (HAProxy)]
        |
 direct pod IP (OVN)
        |
 [Application Pods]
```

## Prerequisites

- Cluster `ready`; default ingress operator available:

  ```bash
  oc get co ingress
  oc get ingresscontroller default -n openshift-ingress-operator
  ```

## Steps

1. Create project and deployment + Service:

   ```bash
   oc new-project route-demo
   oc create deployment web --image=nginx -n route-demo
   oc expose deployment web --port=80 -n route-demo
   ```

2. Expose **edge** Route:

   ```bash
  oc create route edge web --service=web --hostname=web-route-demo.apps.${CLUSTER_NAME}.${DOMAIN_SUFFIX} -n route-demo
  ```

   Or use generated hostname:

   ```bash
  oc expose svc web -n route-demo
  ROUTE="$(oc get route -n route-demo -o jsonpath='{.items[0].spec.host}')"
  ```

3. Curl route (from network that can reach ingress):

   ```bash
  curl -sk "https://${ROUTE}/" -o /dev/null -w "%{http_code}\n"
  ```

4. (Optional) Test **passthrough** or **reencrypt** with TLS backend—document which mode your app requires.

5. Rolling update test: scale deployment, confirm no user-visible errors while readiness gates endpoints.

## Expected output

- Route `Admitted`
- HTTP 200 from route URL
- `oc get endpointslices -n route-demo` reflects ready pods only

## Success criteria

```bash
oc get route -n route-demo -o jsonpath='{.items[0].status.ingress[0].conditions[?(@.type=="Admitted")].status}' | grep -q True
curl -sk "https://${ROUTE}/" -w "%{http_code}" | grep -q 200
oc get co ingress -o json | jq -e '.status.conditions[] | select(.type=="Available" and .status=="True")'
```

## Failure signals

- Route pending → DNS or ingress controller not available.
- 503 from router → pods not ready or Service selector mismatch.

## Rollout safety (PDF)

- Use `readinessProbe`, **PodDisruptionBudgets**, and rolling updates—HAProxy removes unready pods from endpoints before terminating old replicas.

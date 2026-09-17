# TC-09 — Private ingress and connectivity validation

**Provenance:** Inferred from repo ([ROSA_HCP_Troubleshooting_Guide.md](../../troubleshooting/ROSA/ROSA_HCP_Troubleshooting_Guide.md)).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

On a **private ingress** ROSA HCP cluster, confirms internal reachability to the ingress NLB/VPC endpoints and documents behavior when accessing routes from outside the VPC (expected failure unless a public ALB chain is added).

## Why this matters

- Most private-cluster incidents are “works on bastion, fails from laptop”—this test codifies expected behavior.
- Validates security groups on VPC endpoints and router service health.
- Optional pattern: public ALB → private NLB for controlled exposure.

## Architecture

```
 Internet                VPC (private)
    │                         │
    │ (no direct path)        ├── Bastion ──► NLB (internal) ──► router-default
    │                         │                      ▲
    └──── optional public ALB ┴──────────────────────┘
```

## Prerequisites

- TC-03 private cluster `ready`.
- Bastion in same VPC as workers.
- Sample route deployed:

  ```bash
  oc create deployment hello --image=registry.redhat.io/ubi9/httpd-24
  oc expose deployment hello --port=8080
  ROUTE="$(oc get route hello -o jsonpath='{.spec.host}')"
  ```

## Steps

1. Describe ingress privacy:

   ```bash
   rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq '.ingress, .private_link'
   oc get ingresscontroller default -n openshift-ingress-operator -o yaml | grep -A10 endpointPublishingStrategy
   ```

2. Resolve router LB from bastion:

   ```bash
   NLB="$(oc get svc router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
   dig +short "${NLB}"
   ```

3. Curl route from **bastion**:

   ```bash
   curl -sk "https://${ROUTE}/" -o /dev/null -w "%{http_code}\n"
   ```

4. Curl route from **laptop** (outside VPC):

   ```bash
   curl -sk --connect-timeout 5 "https://${ROUTE}/" -o /dev/null -w "%{http_code}\n" || echo "timeout expected"
   ```

5. VPC endpoint check (console):

   ```bash
   aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}" \
     --query 'VpcEndpoints[].{Service:ServiceName,State:State}' --output table
   ```

## Expected output

- Bastion curl returns `200` or `403` (app dependent), not connection timeout.
- External curl times out or fails DNS unless split-horizon DNS exists.
- VPC endpoints `available` if PrivateLink ingress used.

## Success criteria

| Location | Route HTTPS | Result |
|----------|-------------|--------|
| Bastion | `curl https://${ROUTE}` | HTTP 2xx/3xx/403 (connected) |
| Internet | same | Timeout/refused (PASS for private design) |

```bash
oc get co ingress -o json | jq -e '.status.conditions[] | select(.type=="Available").status' | grep -q True
```

## Failure signals

- Bastion cannot reach route → SG on VPC endpoint or NLB targets unhealthy (`aws elbv2 describe-target-health`).
- Internet reachable on private cluster without ALB design → security regression.
- `router-default` has no hostname → ingress operator not provisioning LB.

## Optional extension (document only)

Implement public ALB chaining per troubleshooting guide §4—record as separate exploratory test, not required for private ingress PASS.

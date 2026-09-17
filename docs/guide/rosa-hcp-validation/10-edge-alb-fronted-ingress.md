# ING-02 — Edge ALB/NLB in front of OpenShift Ingress

**Provenance:** [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §2.

## Summary

Place an internet-facing **AWS ALB or NLB** (ACM cert, optional WAF/CloudFront) **in front of** the OpenShift Ingress Controller so corporate policy meets AWS edge services while HAProxy still routes to pod IPs internally.

## Why this matters

- Mandate **ACM** public certificates and **AWS WAF** inspection at the edge.
- Keeps application Route semantics while satisfying landing-zone networking reviews.
- Supports **router sharding** via secondary `IngressController` CRs for isolated listeners.

## Architecture

```
 Internet
    |
    v
 [AWS ALB/NLB + ACM (+ WAF)]
    |
    v
 [OpenShift IngressController (private/internal publishing)]
    |
 HAProxy -> Pod IPs
```

## Prerequisites

- Understanding of cluster ingress publishing strategy (`HostNetwork`, `LoadBalancerService`, private NLB).
- ACM certificate; ALB subnets tagged for ELB.
- Reference: ROSA troubleshooting **public ALB → private NLB** patterns in [ROSA_HCP_Troubleshooting_Guide.md](../../troubleshooting/ROSA/ROSA_HCP_Troubleshooting_Guide.md).

## Steps

1. Document current ingress endpoint:

   ```bash
   oc get ingresscontroller default -n openshift-ingress-operator -o yaml | grep -A15 endpointPublishingStrategy
   oc get svc router-default -n openshift-ingress -o wide
   ```

2. Design edge chain (lab-specific):
   - Create ALB listener with ACM cert.
   - Target group points to **internal NLB** or router service endpoints per your architecture doc.

3. Configure DNS (Route53 or corporate DNS) for app hostname → ALB.

4. Create Route on cluster; verify traffic: Client → ALB → ingress → pods.

5. (Optional) Create secondary `IngressController` for platform vs tenant routes (router sharding).

## Expected output

- ALB healthy targets toward ingress tier.
- Application URL returns 200 through full chain.
- WAF (if enabled) shows allowed traffic for test client.

## Success criteria

Document lab-specific checks, minimally:

```bash
curl -sk "https://app.example.com/" -w "%{http_code}" | grep -q 200
aws elbv2 describe-target-health --target-group-arn "<edge-tg-arn>" \
  --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' | jq 'length >= 1'
```

## Failure signals

- TLS mismatch → ACM cert SAN vs hostname.
- 502 at ALB → wrong backend (NLB/security group).
- Bypassing intended private ingress → security review failure.

## Notes

- Full automation is not in MCS; treat as architecture validation or **BLOCKED** until edge infra exists.

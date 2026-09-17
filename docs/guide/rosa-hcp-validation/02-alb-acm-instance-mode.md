# UC-01 — ALB ingress with ACM (instance mode)

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 1 · [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §3 (ING-03 merged here).

## Summary

Expose an HTTP(S) app on ROSA using the **AWS Load Balancer Operator / Controller** with an **ACM** TLS certificate on an internet-facing ALB. **Pass path:** `target-type: instance` (NodePort → worker → pod via OVN).

## Why this matters

- Enterprises standardize on **ACM** and AWS WAF at the edge while still using Kubernetes Ingress CRDs.
- **Instance mode** is the supported ROSA pattern; EKS-style **IP mode** breaks on OVN overlay networking.
- Shared ALB / IngressGroup reduces cost when many microservices share one edge load balancer.

## Architecture

```
 Internet (HTTPS:443, ACM cert)
        |
        v
 +---------------------------+
 | AWS Application Load Balancer |
 | target-type: instance     |
 +-------------+-------------+
               | NodePort on workers
               v
 +---------------------------+
 | OVN-Kubernetes -> Pod     |
 +---------------------------+
```

## Prerequisites

- [01-prerequisites.md](01-prerequisites.md) complete; standard HCP cluster.
- ACM **public** certificate in `AWS_DEFAULT_REGION` for your app hostname (or use cert on ALB listener).
- ALBO installed — see [alb-ingress-grouping](../../../networking/load-balancers/alb-ingress-grouping/README.md):

  ```bash
  cd networking/load-balancers/alb-ingress-grouping
  ./scripts/install-albo.sh
  oc get pods -n aws-load-balancer-operator
  ```

- App namespace with **NodePort** Service (required for instance mode).

## Steps

1. Create namespace and deployment + NodePort Service (adapt from PDF or use demo manifests under `alb-ingress-grouping`).

2. Request or identify ACM certificate ARN:

   ```bash
   aws acm list-certificates --region "${AWS_DEFAULT_REGION}" \
     --query 'CertificateSummaryList[?DomainName==`app.example.com`].CertificateArn' --output text
   export ACM_ARN="arn:aws:acm:..."
   ```

3. Apply Ingress (instance mode + ACM) — from Technical Solutions PDF:

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: webserver-alb-ingress
     namespace: my-app
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/certificate-arn: "${ACM_ARN}"
       alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
       alb.ingress.kubernetes.io/target-type: instance
   spec:
     ingressClassName: alb   # or your ALBO IngressClass name
     rules:
       - host: app.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: webserver-svc
                   port:
                     number: 80
   ```

4. Wait for ALB hostname:

   ```bash
   oc get ingress webserver-alb-ingress -n my-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
   ```

5. Validate target group health (instance targets = worker nodes):

   ```bash
   ALB_DNS="$(oc get ingress webserver-alb-ingress -n my-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
   curl -sk "https://${ALB_DNS}/" -H "Host: app.example.com" -o /dev/null -w "%{http_code}\n"
   ```

## Expected output

- Ingress `.status.loadBalancer.ingress[0].hostname` populated (ELB DNS name).
- `curl` returns `200` (or app-specific success code).
- AWS console: target group **healthy** instance targets.

## Success criteria (PASS)

```bash
test -n "${ALB_DNS}"
aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' | jq 'length >= 1'
```

- Ingress annotation `target-type: instance` (not `ip`).

## Failure signals

- Ingress stuck with no hostname → ALBO logs, subnet tags `kubernetes.io/role/elb`, IAM for controller.
- Unhealthy targets → Service must be **NodePort**; check security groups and health check path.
- **Do not FAIL the platform** if `target-type: ip` fails — that is expected on ROSA.

---

## UC-01N — Negative test: IP mode (N/A on ROSA)

**Provenance:** Technical Solutions Scenario 1 (`target-type: ip`) vs Ingress PDF (OVN — IP mode unsupported).

### Summary

Document that **IP target mode** and ALB **Pod Readiness Gates** are **not** supported on ROSA; attempting them is an expected negative result.

### Steps

1. Change annotation to `alb.ingress.kubernetes.io/target-type: ip` (as in PDF).
2. Observe ALBO rejection, Ingress error events, or targets never healthy.

### Success criteria (negative test PASS)

- Platform behavior matches documentation: instance mode works; IP mode does **not** become production-ready.
- Record result **PASS (negative)** or **N/A** in [validation-report.md](validation-report.md), not a cluster defect.

### Reference

- [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf)
- [alb-ingress-grouping README — instance only](../../../networking/load-balancers/alb-ingress-grouping/README.md)

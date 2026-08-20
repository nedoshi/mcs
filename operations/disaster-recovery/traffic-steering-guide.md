# Traffic Steering — Cross-Cloud DR (ARO ↔ ROSA HCP)

Global traffic management for failover between Azure (ARO) and AWS (ROSA HCP).

**Related:** [Failover Runbook](./failover-runbook-aro-rosa.md) · [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Design Principles

1. User-facing DNS points to **your app domain** — not cluster-internal OpenShift domains
2. TTL on failover records must support target RTO (60–300 seconds typical)
3. Health checks must probe **application** endpoints, not just TCP to ingress
4. Private clusters require hybrid DNS — Front Door alone is insufficient

---

## Public Ingress Options

| Provider | Mechanism | Notes |
|----------|-----------|-------|
| **AWS Route 53** | Failover routing policy + health checks | Origins: ARO ingress IP/hostname + ROSA ALB |
| **Cloudflare** | Load balancing + health monitors | Cloud-agnostic; good for multi-cloud |
| **Akamai** | Global traffic management | Enterprise |
| **Azure Front Door** | Multi-origin | Can origin to AWS ALB with public endpoints |

### Route 53 Failover Example

```
app.example.com  (Failover PRIMARY)
  └── Primary: ARO ingress health check → <aro-lb-hostname>
  └── Secondary: ROSA ALB health check → <rosa-alb-hostname>
```

Health check:

```
HTTPS GET /healthz
Expected: 200
Failure threshold: 3 consecutive failures
```

---

## Private Ingress Options

| Approach | Description |
|----------|-------------|
| **Hybrid DNS repoint** | Private hosted zone (Route 53 + Azure Private DNS linked via VPN). CNAME `app.internal.example.com` repointed on failover |
| **Internal global LB** | F5, NGINX Plus, or cloud LB in shared network zone with backends in both clouds |
| **Manual cutover** | Runbook step: update DNS record via CLI — rehearse every drill |

Provision custom domain and internal DNS **at initial build**, not during an incident.

---

## Health Check Endpoints

Deploy a lightweight health route on every production app:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: healthz
  namespace: production
spec:
  host: healthz.apps.<cluster-domain>
  to:
    kind: Service
    name: app
  path: /healthz
```

Global LB probes should hit the **public app domain** `/healthz` through the same path users take.

---

## Session Handling

| Tier | Approach |
|------|----------|
| Active/Passive | Drain connections before cutover; accept brief session loss or use shared Redis |
| Active/Active | Sticky sessions per region OR shared session store |
| Cold / Pilot | Session loss expected — document in comms plan |

---

## Failover DNS Checklist

- [ ] TTL documented: ______ seconds
- [ ] Primary health check URL: ____________________
- [ ] DR health check URL: ____________________
- [ ] Automated failover: ☐ Yes ☐ Manual (document CLI steps)
- [ ] SaaS allowlists include both ingress egress IPs
- [ ] TLS certificates valid for app domain on **both** clusters
- [ ] DNS repoint rehearsed in last DR drill (date): ____________

---

## Manual Cutover Commands (Route 53 Example)

```bash
# Failover to DR (ROSA)
aws route53 change-resource-record-sets \
  --hosted-zone-id ZONE_ID \
  --change-batch file://failover-to-dr.json

# Failback to primary (ARO)
aws route53 change-resource-record-sets \
  --hosted-zone-id ZONE_ID \
  --change-batch file://failback-to-primary.json
```

Store JSON change batches in Git: `operations/disaster-recovery/examples/route53/`

---

## Validation

During DR drill, measure:

| Metric | Value |
|--------|-------|
| Time from DNS change to global propagation | |
| Health check detection time | |
| First successful user request on DR | |

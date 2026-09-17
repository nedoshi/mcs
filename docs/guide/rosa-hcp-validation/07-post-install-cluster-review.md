# TC-06 — Post-install cluster review (DNS, security, network, capacity)

**Provenance:** Inferred from repo ([rosa_cluster_review_guide.md](../../troubleshooting/ROSA/rosa_cluster_review_guide.md)).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Structured review of DNS, IAM/RBAC, network paths, ingress, and worker capacity on a `ready` ROSA HCP cluster.

## Why this matters

- Customer acceptance checklists before workload onboarding.
- Catches misconfigured Route53 delegation and internal ingress scope early.
- Baseline snapshot for DR pairs (ARO ↔ ROSA) and audit evidence.

## Architecture

```
 External DNS (Route53)          Cluster interior
 ┌────────────────────┐         ┌─────────────────────┐
 │ api.*  apps.*      │────────►│ CoreDNS + OVN-K     │
 │ A / CNAME records  │         │ SCC + RBAC + NetPol │
 └────────────────────┘         └─────────────────────┘
```

## Prerequisites

- Cluster `ready`; `oc` logged in as cluster-admin.
- `aws` CLI read access to Route53 and ELB in cluster region.
- `CLUSTER_DOMAIN` from `rosa describe cluster`.

## Steps

1. **DNS — API**

   ```bash
   API_HOST="$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.api.url' | sed 's|https://||')"
   dig +short "${API_HOST}"
   aws route53 list-hosted-zones --query "HostedZones[?contains(Name, '${CLUSTER_NAME}')]"
   ```

2. **DNS — routes**

   ```bash
   oc get routes -A
   ROUTE_HOST="$(oc get route -n openshift-console console -o jsonpath='{.spec.host}')"
   dig +short "${ROUTE_HOST}"
   ```

3. **Security — RBAC**

   ```bash
   oc get clusterrolebinding | grep cluster-admin
   oc get identity
   oc get users
   ```

4. **Network — ingress**

   ```bash
   oc get ingresscontroller -n openshift-ingress-operator
   aws elbv2 describe-load-balancers --region "${AWS_DEFAULT_REGION}" \
     --query 'LoadBalancers[?contains(LoadBalancerName, `k8s`)].[LoadBalancerName,Scheme,State.Code]' --output table
   ```

5. **Capacity**

   ```bash
   oc get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone',CPU:.status.capacity.cpu,MEM:.status.capacity.memory
   oc adm top nodes 2>/dev/null || echo "metrics-server not ready"
   ```

6. **In-cluster DNS**

   ```bash
   oc run dns-test --image=registry.redhat.io/ubi9/ubi-minimal --restart=Never --command -- sleep 3600
   oc exec dns-test -- nslookup kubernetes.default.svc.cluster.local
   oc delete pod dns-test
   ```

## Expected output

- API and console hosts resolve to load balancer targets.
- Ingress controllers `Available=True`.
- Nodes spread across expected AZs; capacity matches machine pool definition.

## Success criteria

```bash
oc get co ingress -o json | jq -e '.status.conditions[] | select(.type=="Available" and .status=="True")'
oc get nodes --no-headers | wc -l | xargs test "${REPLICAS}" -le
dig +short "${API_HOST}" | grep -q .
```

Document any `Degraded` operators with `oc describe co <name>`.

## Failure signals

- NXDOMAIN on API → DNS delegation or private DNS not reachable from test host.
- Single-AZ nodes on multi-AZ cluster → subnet or machine pool misconfiguration.
- All cluster-admin bindings are unexpected users → RBAC hygiene fail.

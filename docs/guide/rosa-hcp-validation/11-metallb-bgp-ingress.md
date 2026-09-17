# ING-04 — MetalLB BGP mode and route advertisements

**Provenance:** [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §4.

## Summary

Validate **MetalLB Operator** in **BGP** mode with **RouteAdvertisements** / **FRRConfiguration** to advertise service or network prefixes to upstream routers (e.g. TGW, Direct Connect)—Layer 3 ingress for bare metal or hybrid topologies.

## Why this matters

- Bare metal worker pools often need **L3** ingress without cloud LB per service.
- ECMP + **BFD** supports fast failover for stateless edge routing.
- Advanced customers integrate ROSA with existing BGP fabrics.

## Architecture

```
 External router / TGW (BGP peer)
        |
   BGP session
        |
 [MetalLB speaker pods]
        |
 [Service LoadBalancer IP or advertised prefix]
        |
 [Worker nodes / pods]
```

## Prerequisites

- MetalLB Operator installed from OperatorHub.
- **BGP peer** available in lab (ASN, peer IP, allowed prefixes)—without this → **BLOCKED**.
- Often paired with bare metal pools.

## Steps

1. Install MetalLB Operator; verify CRDs:

   ```bash
   oc get csv -n metallb-system
   oc get ipaddresspool,bgppeer,bgpadvertisement -A
   ```

2. Configure `BGPPeer`, `IPAddressPool`, and advertisement CRs per OpenShift MetalLB docs (adapt to your peer).

3. Expose a test Service type `LoadBalancer`:

   ```bash
   oc expose deployment test-lb --port=80 -n route-demo
   oc get svc test-lb -n route-demo
   ```

4. Confirm prefix advertised to peer (peer-side `show ip bgp` or equivalent).

5. Send traffic from external network that uses learned route.

## Expected output

- Service receives `EXTERNAL-IP` or advertised prefix from pool.
- BGP session **Established**.
- External client reaches backend.

## Success criteria

Lab-dependent; minimum:

```bash
oc get bgppeer -A -o json | jq '.items[].status? // empty'
# Peer documents Established + external curl succeeds
```

## Failure signals

- No peer → **BLOCKED**, not FAIL.
- Session down → ASN/IP mismatch, firewall, or BFD config.
- See [openshift-port-strategy.md](../../architecture/networking/openshift-port-strategy.md) for MetalLB context.

# ING-05 — Direct ingress to Virt VMs (Site-to-Site IPsec VPN)

**Provenance:** [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) — §5 · [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) (Virt VPN next steps).

## Summary

Establish **Site-to-Site IPsec VPN** (Libreswan + Keepalived gateway VMs on a **Cluster User-Defined Network**) to **AWS Transit Gateway** so external VPC workloads reach **VM overlay addresses** without per-VM load balancers.

## Why this matters

- Legacy VMs need **routable, non-NAT** access from AWS VPCs or on-prem.
- Complements [UC-07](08-virt-rhel-cloudinit.md) when apps stay on Virt, not containers.
- Certificate-based TGW authentication for enterprise WAN designs.

## Architecture

```
 [External AWS VPC / on-prem]
        |
   IPsec (Libreswan)
        |
 [Gateway VMs + Keepalived VIP]
   on CUDN
        |
 [OpenShift Virt VM overlay IPs]
```

## Prerequisites

- UC-07 or equivalent Virt workloads running.
- **TGW**, VPN attachment, and CUDN design completed in lab—otherwise **BLOCKED**.
- Bare metal workers; network policy allows gateway VMs.

## Steps

1. Deploy redundant gateway VMs (PDF: Libreswan + Keepalived) on CUDN per MOBB/tutorial linked from Technical Solutions PDF.

2. Configure IPsec tunnels to TGW with certificate auth.

3. Advertise VM subnet routes to external VPC route tables.

4. From external VPC instance, ping/connect to VM overlay IP (e.g. nginx on RHEL VM).

5. Fail over Keepalived VIP; confirm session recovery within lab SLO.

## Expected output

- IPsec tunnels **UP**
- External host reaches VM service on overlay IP
- VIP failover documented

## Success criteria

Lab-specific; record:

- Tunnel status from gateway (`ipsec status`)
- Successful `curl` or `ssh` from external test host to VM IP

## Failure signals

- Missing TGW/CUDN → **BLOCKED**
- Phase 1/2 IPsec mismatch → IKE proposals, cert trust, route propagation
- Asymmetric routing → verify TGW route tables and security groups

## References

- PDF: *Ingress to ROSA Virt VMs with Site-to-Site IPsec VPN*
- [ROSA_Network_Troubleshooting_Guide.md](../../network-troubleshooting/ROSA/ROSA_Network_Troubleshooting_Guide.md)

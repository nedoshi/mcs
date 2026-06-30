# Network Troubleshooting

Guides for troubleshooting networking and DNS issues in private and managed OpenShift clusters (ARO, GCP/OSD, ROSA).

## Platform guides

### ARO (Azure Red Hat OpenShift)
- [ARO Network Troubleshooting Guide](ARO/ARO_Network_Troubleshooting_Guide.md) — Networking and DNS in private ARO clusters
- [ARO Operators Catalog Troubleshooting](ARO/aro_catalog_troubleshooting.md) — Red Hat Operators catalog connection issues
- [ARO Private Cluster Networking](ARO/aro_networking_troubleshooting.md) — Connectivity, API server, and Azure network configuration

### GCP (OpenShift on GCP)
- [GCP OSD Network Troubleshooting Guide](GCP/GCP_OSD_Network_Troubleshooting_Guide.md) — Networking in OpenShift Dedicated on GCP

### ROSA (Red Hat OpenShift Service on AWS)
- [ROSA Network Troubleshooting Guide](ROSA/ROSA_Network_Troubleshooting_Guide.md) — Classic ROSA, HCP, and OpenShift Virtualization networking

## Cross-platform
- [OpenShift DNS Troubleshooting](openshift_dns_troubleshooting.md) — DNS resolution and CoreDNS

## General approach

1. Check pod and operator logs (`oc logs`, `oc describe`).
2. Verify connectivity and DNS from a test pod in the same namespace.
3. Review platform-specific network (security groups, NACLs, route tables, VPC endpoints).
4. Confirm proxy and firewall rules if the cluster uses an outbound proxy.

See the [docs index](../README.md) for storage and general troubleshooting.

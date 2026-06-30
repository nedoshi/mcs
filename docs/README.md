# MCS Documentation

Central documentation for OpenShift managed services: troubleshooting, storage, and operations.

## Structure

| Section | Description |
|--------|-------------|
| [Cost Management](cost-management/README.md) | ARO cost visibility; ROSA Splunk log routing and ingestion caps |
| [Network Troubleshooting](network-troubleshooting/README.md) | Network and DNS troubleshooting for ARO, GCP/OSD, and ROSA |
| [Storage](storage/README.md) | Storage options, setup guides, backup/restore (ROSA, ARO, ODF) |
| [Troubleshooting](troubleshooting/index.md) | General cluster troubleshooting, platform guides (ARO, ROSA), ArgoCD, reference notes |

## Quick links

### Cost Management
- [ARO Hybrid Cloud Cost Management](cost-management/aro_hybrid_cost_management_guide.md) — Metrics Operator + Azure billing integration
- [ROSA Splunk Log Filtering & Routing](cost-management/rosa_splunk_log_filtering_routing_guide.md) — Tiered routing, audit filters, flow control, and Cribl pre-processing

### Network troubleshooting
- [ARO Network & Catalog](network-troubleshooting/ARO/) — ARO networking and operator catalog issues
- [GCP OSD Network](network-troubleshooting/GCP/) — OpenShift on GCP networking
- [ROSA Network](network-troubleshooting/ROSA/) — ROSA networking
- [OpenShift DNS](network-troubleshooting/openshift_dns_troubleshooting.md)

### Storage
- [Storage index](storage/Index.md) — Full storage docs index
- [OpenShift storage guide](storage/openshift_storage_guide.md) — ROSA & ARO setup
- [ARO storage & backup](storage/aro_storage_guide.md), [ARO backup & restore](storage/aro_backup_restore.md)
- [Storage vendor support](storage/storage_vendor_openshift_support.md)

### Troubleshooting (platform & operations)
- [ROSA cluster troubleshooting](troubleshooting/index.md) — Connection timeouts, routing, AWS network
- [ARO](troubleshooting/ARO/) — Cron scaling, F5 load balancer, upgrades
- [ROSA](troubleshooting/ROSA/) — HCP, private network, service mesh, VPC endpoints, security groups
- [ArgoCD RBAC](troubleshooting/argocd-rbac-config.md), [Airgat](troubleshooting/airgat.md)
- [Reference notes](troubleshooting/reference/) — Misc technical notes

## Related in this repo

- **Example manifests:** [../examples/yaml/](../examples/yaml/) — Sample YAML for ArgoCD, OADP, service mesh, etc.
- **Network tools image:** [../tools/network-tools-image/](../tools/network-tools-image/) — Dockerfile and deployment for network debugging pods
- **Operator install:** [../install-operators/](../install-operators/) — Argo CD, ACS, AI, GitOps, etc.
- **Demos:** [../openshift-demos/](../openshift-demos/) — GitOps on ROSA/ARO, Service Mesh demos

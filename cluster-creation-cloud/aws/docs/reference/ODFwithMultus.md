# ODF with Multus on ROSA (AWS) - Research & Deployment Guide

## Platform Decision: ROSA Classic vs ROSA HCP

| Feature | ROSA Classic | ROSA HCP |
|---|---|---|
| Multus CNI | Supported via OVN-Kubernetes secondary networks | **NOT supported by default** |
| Third-party CNI | Supported | Must deploy cluster without CNI, then install manually — Red Hat won't support CNI issues |
| ODF + Multus | Possible (see caveats below) | Not a supported path |

**Recommendation:** Use **ROSA Classic** for Red Hat-supported Multus + ODF.

**Sources:**
- [Third-party CNI in OSD, ROSA, and ARO](https://access.redhat.com/solutions/7029059)
- [ROSA HCP cluster creation docs](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-cluster-no-cli)

---

## Multus CNI on AWS

Multus is a meta-plugin that chains multiple CNI plugins, enabling pods to have multiple network interfaces beyond the single default interface.

### How It Works on AWS

- **Primary CNI**: Must be Amazon VPC CNI (EKS) or OVN-Kubernetes (ROSA/OpenShift) — Multus adds secondary interfaces only
- **Secondary interfaces**: Configured via `NetworkAttachmentDefinition` (NAD) custom resources
- **Pod annotation**: `k8s.v1.cni.cncf.io/networks: <nad-name>`
- **Packet acceleration**: Connect to EC2 Elastic Network Adapters (ENA) through Multus-managed `host-device` and `ipvlan` plugins
- **ENI tagging**: Tag secondary ENIs with `node.k8s.amazonaws.com/no_manage: true` to prevent VPC CNI from managing them

### Supported Secondary CNI Plugins

- `macvlan` — each pod gets a unique MAC address on a physical interface
- `ipvlan` — pods share the host MAC but get unique IPs
- `host-device` — directly assigns a host network device to a pod

### Key Limitations

- Network policies must be enriched to include ports and IPs of secondary interfaces
- AWS provides support for Multus chaining itself, but NOT for IPAM of secondary interfaces
- Only Amazon VPC CNI is officially supported as the default delegate plugin

**Sources:**
- [AWS EKS Multus Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-multus.html)
- [Amazon EKS now supports Multus CNI](https://aws.amazon.com/blogs/containers/amazon-eks-now-supports-multus-cni/)
- [OpenShift Multiple Networks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/networking/multiple-networks)

---

## ODF + Multus: Dedicated Storage Network

OpenShift Data Foundation can leverage Multus to isolate storage traffic from application traffic for improved performance, security, and bandwidth management.

### Architecture Options

| Configuration | Description | Complexity |
|---|---|---|
| **Public network only** (recommended start) | All storage traffic (client + replication) on one dedicated interface, separate from OCP SDN | Low |
| **Public + Cluster networks** | Client storage traffic (public) and replication/heartbeat traffic (cluster) on separate interfaces | High |

### How ODF Uses Multus

- **macvlan** CNI gives each ODF pod a unique MAC address on a physical interface
- **whereabouts** IPAM (the only supported IPAM) assigns IPs from a configured range
- NADs must be created in the `openshift-storage` namespace **before** creating the StorageCluster
- `ipRanges` and plugin chaining are **not** supported
- All network interface names must be identical across all nodes attached to the Multus network

### Ceph Network Model

ODF (backed by Ceph) uses two optional networks:

- **Public network**: Client communications, PVC access — pods and applications connect here
- **Cluster network**: Internal replication, recovery, heartbeat traffic between OSD daemons

### Example NAD for ODF

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ocs-public-cluster
  namespace: openshift-storage
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "ens2",
    "mode": "bridge",
    "ipam": {
      "type": "whereabouts",
      "range": "192.168.1.0/24"
    }
  }'
```

**Sources:**
- [ODF 4.18 Creating Multus Networks](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.18/html/managing_and_allocating_storage_resources/creating-multus-networks_rhodf)
- [ODF 4.19 Multus Architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.19/html/red_hat_openshift_data_foundation_architecture/multus-architecture-for-openshift-data-foundation_mcg)

---

## Deployment Prerequisites

### Required Operators

1. **Kubernetes NMState Operator** — for NodeNetworkConfigurationPolicy (NNCP) to configure VLAN interfaces on worker nodes
2. **Red Hat Local Storage Operator** — for local disk management
3. **Red Hat OpenShift Data Foundation Operator** — for ODF/Ceph storage cluster

### Additional Requirements

- DHCP server (for cross-AZ L3 routing since macvlan is L2 only)
- Worker nodes with multiple network interfaces or ENIs
- Proper subnet/VLAN planning before deployment

---

## Deployment Workflow

### Step 1: Deploy ROSA Classic Cluster

Deploy with worker nodes across multiple availability zones.

### Step 2: Install NMState Operator & Configure NNCP

Use NodeNetworkConfigurationPolicy to configure VLAN interfaces, bonds, and the ODF Multus shim on worker nodes.

### Step 3: Configure DHCP

Set up DHCP server to provide IP addresses and static routes to each AZ. This is necessary because macvlan is limited to L2 and cannot provide routing across AZs natively.

### Step 4: Create NetworkAttachmentDefinitions

Apply NADs in the `openshift-storage` namespace. Must be done **before** StorageCluster creation.

### Step 5: Run Rook Multus Validation Tool

Verify connectivity and configuration before deploying storage:

```bash
./rook multus validation run \
  --cluster-network=odf-cluster-network \
  --public-network=odf-public-network
```

The tool runs validation tests to confirm NADs and system configurations support ODF with Multus. Download from Red Hat Knowledgebase.

### Step 6: Deploy ODF StorageCluster

Create the StorageCluster, selecting the Multus NADs during creation.

**Sources:**
- [Red Hat Developer Learning Path: Deploy ODF Across AZs with Multus](https://developers.redhat.com/learn/openshift/deploy-openshift-data-foundation-across-availability-zones-using-multus) (Published Oct 2025, ~1.5 hr guided walkthrough)
- [Rook Multus Validation Tool Guide](https://medium.com/@amzaky/using-rook-multus-validation-tool-prior-to-using-openshift-data-foundation-odf-with-dedicated-78fefeaaffac)

---

## AWS-Specific Caveats

1. **ODF + Multus is primarily documented for bare metal.** Running on AWS EC2 may require a support exception (SUPPORTEX Jira) from Red Hat.
2. **NMState operator platform support**: Documented for bare metal, IBM Power/Z, VMware vSphere, and OpenStack. AWS EC2 is **not explicitly listed**.
3. **macvlan on AWS**: EC2 instances don't natively support VLAN trunking like bare metal. Use ENI-based approaches (attach multiple ENIs to EC2 instances) instead of traditional VLAN tagging.
4. **L2 requirement**: ODF secondary networks must be Layer 2 (non-routable). AWS VPC subnets are inherently L3, requiring creative subnet/ENI designs.
5. **Support exceptions**: For configurations deviating from the bare-metal reference architecture, Red Hat requires opening a support exception through SUPPORTEX Jira.

---

## EKS Alternative (Multus without ODF)

If a simpler AWS-native Multus path is acceptable without ODF:

- EKS natively supports Multus as an add-on
- VPC CNI stays as primary, Multus manages secondary ENIs
- No ODF equivalent — use EBS CSI or FSx for storage instead
- AWS manages Multus lifecycle but not secondary interface IPAM

**Source:** [AWS EKS Multus Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-multus.html)

---

## Key References

| Resource | URL |
|---|---|
| ODF Multus Architecture (4.19) | https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.19/html/red_hat_openshift_data_foundation_architecture/multus-architecture-for-openshift-data-foundation_mcg |
| ODF Creating Multus Networks (4.18) | https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.18/html/managing_and_allocating_storage_resources/creating-multus-networks_rhodf |
| ODF Planning Deployment - Network Reqs | https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.17/html/planning_your_deployment/network-requirements_rhodf |
| Red Hat Developer Learning Path | https://developers.redhat.com/learn/openshift/deploy-openshift-data-foundation-across-availability-zones-using-multus |
| AWS EKS Multus Docs | https://docs.aws.amazon.com/eks/latest/userguide/pod-multus.html |
| OpenShift Multiple Networks (4.17) | https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/networking/multiple-networks |
| OpenShift Secondary Networks (4.18) | https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/multiple_networks/secondary-networks |
| Multus CNI Usage Guide | https://k8snetworkplumbingwg.github.io/multus-cni/docs/how-to-use.html |

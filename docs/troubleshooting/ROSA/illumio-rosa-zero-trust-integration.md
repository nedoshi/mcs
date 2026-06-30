# Illumio Zero Trust Segmentation on ROSA (Hosted Control Plane)

This guide describes infrastructure design, deployment steps, policy patterns, and operational procedures for integrating **Illumio** with **Red Hat OpenShift Service on AWS (ROSA)**, including **Hosted Control Plane (HCP)** clusters. It is written for architects and platform operators; always validate against your Illumio Core version and [Illumio product documentation](https://docs.illumio.com/) before production changes.

---

## 1. Scope and design goals

- **Objective:** Enforce least-privilege, identity- and label-driven segmentation for workloads on ROSA while preserving visibility for incident response and compliance.
- **Platform:** ROSA on AWS with customer-managed worker nodes; control plane is Red Hat–managed (HCP or classic ROSA). Illumio components run on **worker nodes** and in **customer namespaces** you control; they do not run on the managed control plane.
- **Complementary controls:** Illumio addresses workload-to-workload policy; combine with **AWS security groups**, **OpenShift `NetworkPolicy`**, **Egress Firewall / EgressIP** (where used), and **identity/IAM** for defense in depth.

---

## 2. Architecture overview

### 2.1 Logical components

| Component | Role on ROSA |
|-----------|----------------|
| **Policy Compute Engine (PCE)** | Central policy, object model, and pairing; typically SaaS or customer-hosted outside the cluster. Not installed on ROSA. |
| **Kubelink** | Cluster-scoped workload that watches the API (`Namespace`, `Pod`, `Service`, workloads, nodes) and syncs inventory and labels to the PCE. Deployed via Helm into a dedicated namespace (commonly `illumio-system`). |
| **C-VEN (containerized VEN)** | Privileged **DaemonSet** on each worker: enforces policy using host networking hooks (e.g., iptables/nftables per Illumio version). Required for **agent-based** enforcement on nodes. |
| **Agentless / CloudSecure path (OVN-Kubernetes)** | On OpenShift with **OVN-Kubernetes**, Illumio supports flow visibility via **IPFIX export** from OVN to Illumio components (see Illumio docs for *Configure OpenShift OVN-Kubernetes*). Use when your subscription and architecture target agentless visibility/enforcement patterns. |

Choose **agent-based (C-VEN + Kubelink)** vs **agentless (OVN IPFIX + CloudSecure)** based on Illumio licensing, required enforcement point, and your security architecture. Many enterprises use **Kubelink + C-VEN** for enforcement on ROSA workers; agentless augments visibility where supported.

### 2.2 ROSA HCP specifics

- **Data plane:** Policies and daemons apply to **worker nodes** in your AWS account. Machine pools, node scaling, and zones are your responsibility within ROSA limits.
- **Network:** Default CNI is **OVN-Kubernetes**. Pod and Service networks are consistent with standard OpenShift; ensure Illumio Helm values account for **worker node CIDRs** if you lock down IPFIX or metrics ingress (see Illumio Helm values such as `openshift.workerNodeCidrs` where applicable).
- **Privileges:** C-VEN requires **privileged** pods and compatible **Security Context Constraints (SCCs)**. Plan for `cluster-admin` or equivalent automation for initial install and upgrades.
- **Immutable infrastructure:** Do not rely on manual node SSH; all configuration should be **GitOps- or pipeline-driven** (`Helm`/`oc`).

---

## 3. Prerequisites (before any cluster pairing)

### 3.1 Organizational

- Named owners for **PCE administration**, **ROSA cluster-admin**, **network/firewall**, and **change management**.
- **Label taxonomy** defined in the PCE (e.g., `Environment`, `Application`, `Role`, `Location`, `Cluster`). Align with Kubernetes/OpenShift labels where you will map them (Illumio Core for Kubernetes supports mapping K8s labels to Illumio labels via Helm values in supported versions).
- **Certificate strategy:** If the PCE uses a **private CA**, prepare a **ConfigMap** in `illumio-system` with the root (or chain) CA so Kubelink/C-VEN trust the PCE TLS endpoint.

### 3.2 Cluster and nodes

- **Unique machine ID per node:** Illumio expects a **unique** Linux machine-id on each node. Duplicates break pairing and policy correlation. ROSA-managed nodes normally satisfy this; validate after any custom image or restore scenarios.
- **OpenShift CLI:** `oc` with **cluster-admin** (or delegated install permissions).
- **Version alignment:** Match **Illumio Core for Kubernetes / OpenShift** version to Illumio’s published compatibility matrix for your OpenShift minor version.

### 3.3 Network and AWS

- **Egress from workers to PCE:** Allow HTTPS (and any Illumio-documented ports) from **worker subnets/NAT** to the PCE. For **private clusters**, use **VPC endpoints**, **egress firewall**, or **proxy** per your standard.
- **Ingress (if any):** Restrict admin APIs and metrics exposure; prefer **ClusterIP** and internal-only routes where Illumio allows.
- **OVN IPFIX (agentless visibility path):** If used, configure OVN to export flows to Illumio’s collector service in-cluster; **restrict IPFIX** sources to **node CIDRs** via Helm (per Illumio guidance) to reduce spoofing risk.

---

## 4. Step-by-step: deploy Illumio on ROSA

Execute in **lower environments first**, then promote via GitOps.

### Phase A — Namespace and secrets

1. Create or confirm the target namespace (e.g., `illumio-system`).
2. If using a **private PKI** for PCE:
   - Store the **root CA** in a **ConfigMap** (Illumio docs: `root-ca-config` pattern).
3. Create any **image pull secrets** if your registry requires authentication.

### Phase B — Helm values preparation

1. Obtain the **Illumio Helm chart** and **values** template for your Illumio Core version.
2. Set **pairing** parameters: PCE FQDN, pairing profile or credentials per Illumio’s model.
3. For **OpenShift**, set flags/values that enable **SCC** and **privileged** C-VEN as required by the chart (Illumio charts typically wire `ServiceAccount` + SCC bindings; confirm against current chart README).
4. If mapping **Kubernetes labels → Illumio labels**, add the **Container Resource Definition** / values block per Illumio documentation for your release.
5. For **OVN IPFIX** (if applicable), set `openshift.workerNodeCidrs` (or current equivalent) to your **worker node CIDRs**.

### Phase C — Install

1. **Pre-check:** `oc get nodes`, `oc adm policy`, and confirm no conflicting host-level firewall managers (uncommon on ROSA).
2. **Install:** `helm install` (or `helm upgrade --install`) with your values file; use a **pinned chart version** in CI/CD.
3. **Verify pods:** Kubelink and C-VEN pods **Running**; C-VEN is **DaemonSet** on all **worker** nodes.
4. **PCE pairing:** In PCE UI, confirm cluster and nodes appear; resolve pairing/certificate errors before policy enforcement.

### Phase D — Post-install validation

1. **Traffic:** Generate test traffic between two labeled apps; confirm **visibility** in Illumio (flows, workloads).
2. **Enforcement:** Start in **visibility-only** or **simulation** if your product edition supports it, then enable enforcement in a narrow scope.
3. **Upgrades:** Document **Helm upgrade** order and Illumio release notes; test in non-prod during maintenance windows.

---

## 5. Zero-trust segmentation policies (best practices)

### 5.1 Policy design principles

- **Default deny for application tiers:** Once visibility is trusted, move toward **deny-by-default** between tiers (e.g., front end → API → data), with explicit **allow** rules.
- **Use Illumio labels, not IPs:** Prefer **workload identity** via labels mapped from namespaces, `Deployment`/`DeploymentConfig` labels, or PCE-defined dimensions. Reserve IPs for infrastructure exceptions (DNS, NTP, shared services).
- **Layered segmentation:** Combine **Illumio** (east-west workload policy) with **Kubernetes `NetworkPolicy`** for baseline namespace isolation if your team uses both; avoid duplicate contradictory rules—document **which layer owns** which traffic class.
- **Supervision window:** Run new policies in **monitor/simulate** mode (per product capability) before **enforcing**, with a defined **rollback** procedure.

### 5.2 Drafting rules (recommended order)

1. **Inventory:** Let Kubelink populate workloads; **normalize labels** in OpenShift (e.g., `app`, `team`, `env`).
2. **Map labels** into Illumio dimensions (manual or automated mapping per version).
3. **Allowlist critical dependencies:** DNS, OpenShift **API**, **image registry**, **logging/metrics** endpoints (cluster-internal and external).
4. **Application pairing:** For each app, document **required** peers (same namespace, shared services, external SaaS).
5. **Ring rollout:** Enforce one **namespace** or **application** at a time; maintain a **break-glass** allow rule with tight scope and change record.

### 5.3 ROSA-specific policy notes

- **Control plane traffic:** Worker → Kubernetes API and internal service network behavior must remain allowed per Illumio/OpenShift guidance; do not block **kubelet**, **SDN/OVN**, or **DNS** without explicit Illumio-tested patterns.
- **Operators and CNI:** Exempt **openshift-*` and **OVN** components per Illumio’s documented exclusions or label strategy—mis-segmentation can break cluster operations.
- **Multi-AZ:** Policies should not assume single-subnet peers; use **labels** and **services**, not node IPs.

---

## 6. Ongoing enforcement and monitoring

### 6.1 Operational procedures

| Activity | Practice |
|----------|----------|
| **Change management** | Any PCE policy change that affects production namespaces requires ticket, approver, and backout (disable enforcement or revert ruleset). |
| **RBAC** | Restrict `cluster-admin` and `illumio-system` namespace access; use **OpenShift RBAC** for day-2 operations. |
| **Secrets rotation** | Rotate pairing credentials and registry tokens per org policy; rehearse in staging. |
| **Upgrades** | Coordinate **ROSA upgrade** with **Illumio compatibility**; upgrade Illumio chart after validating release notes. |
| **Node lifecycle** | After **machine pool** scaling or **repair**, confirm **C-VEN** schedules on new nodes and PCE shows correct inventory. |

### 6.2 Monitoring and alerting

- **Kubernetes:** Alert on **DaemonSet** not fully scheduled, **CrashLoopBackOff**, and **SCC** denial events for Illumio service accounts.
- **Illumio PCE:** Use Illumio’s **policy exposure**, **unmanaged flows**, and **violations** dashboards as signals for incomplete policy or attacks.
- **SIEM:** Forward Illumio and OpenShift audit logs per your security standard (note **data residency** and **PII** in flow metadata).

### 6.3 Incident response

- **Suspected false positive:** Narrowly **allowlist** in PCE with time-bound rules; capture **flow records** for analysis.
- **Cluster instability:** Have a **documented** sequence: disable **enforcement** for affected scope → restore connectivity → root-cause (policy vs platform).
- **Forensics:** Preserve **PCE** history and **OpenShift** events; align timestamps with **AWS CloudTrail** for API changes.

---

## 7. Security and compliance checklist

- **Data in transit:** TLS to PCE; private CA ConfigMap when needed.
- **Least privilege:** SCC and `ServiceAccount` scoped to Illumio components only; periodic review.
- **Network:** No public exposure of Illumio admin interfaces without MFA and IP allowlisting.
- **Audit:** Track who can change **pairing** and **global rules** in PCE; correlate with **OpenShift** audit logs.

---

## 8. References (external)

- [Illumio Core for Kubernetes and OpenShift](https://www.illumio.com/resource-center/illumio-core-for-kubernetes-and-openshift) (product overview)
- Illumio documentation: **Prepare Your Environment**, **Host and Cluster Requirements**, **Helm deployment** (paths change by version—use your Illumio Core version tree on [docs.illumio.com](https://docs.illumio.com/))
- Illumio: **Configure OpenShift OVN-Kubernetes** (IPFIX / agentless-related configuration)
- Red Hat: [ROSA documentation](https://docs.openshift.com/rosa/) for networking, upgrades, and support boundaries

---

## 9. Document maintenance

- Revisit this guide when **Illumio Core**, **ROSA**, or **OVN-Kubernetes** versions change.
- Record your organization’s **label schema**, **Helm value file location**, and **break-glass** contacts in your internal runbooks (not in this generic repo doc unless your process requires it).

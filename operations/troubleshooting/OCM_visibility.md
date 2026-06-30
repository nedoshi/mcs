
# OpenShift Self-Managed on Azure: Troubleshooting Guide  
**Why Your Cluster Is Not Visible in Red Hat Hybrid Cloud Console (IPI & UPI)**

> **Target Audience**: SREs, Platform Engineers  
> **Scope**: OpenShift 4.x self-managed (IPI or UPI) on Microsoft Azure  
> **Goal**: Diagnose and fix visibility in [console.redhat.com/openshift](https://console.redhat.com/openshift)

---

## Table of Contents
1. [Prerequisites](#prerequisites)  
2. [Cluster Health Check (Both IPI & UPI)](#cluster-health-check)  
3. [IPI-Specific Troubleshooting](#ipi-specific-troubleshooting)  
4. [UPI-Specific Troubleshooting](#upi-specific-troubleshooting)  
5. [Register Cluster in Red Hat Console](#register-cluster)  
6. [Pull Secret & Org Mismatch](#pull-secret-org-mismatch)  
7. [Network & Telemetry](#network-telemetry)  
8. [Validation & Final Checks](#validation)  
9. [Support Escalation](#support-escalation)  

---

<a name="prerequisites"></a>
## 1. Prerequisites

| Tool | Command |
|------|--------|
| `oc` CLI | `oc version --client` |
| `openshift-install` | `openshift-install version` |
| Azure CLI | `az --version` ≥ 2.50.0 |
| jq | `jq --version` |
| Red Hat Account | Active OpenShift entitlement |

```bash
# Install missing tools
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz -C /usr/local/bin oc
az extension add --name aro --yes
```

---

<a name="cluster-health-check"></a>
## 2. Cluster Health Check (Applies to IPI & UPI)

### 2.1 Access kubeconfig
```bash
export KUBECONFIG=~/<cluster-dir>/auth/kubeconfig
oc whoami  # → kubeadmin
```

### 2.2 Core Health
```bash
oc get nodes
oc get co
oc get clusteroperators
```

| Expected |
|--------|
| All nodes `Ready` |
| All COs: `Available=True`, `Progressing=False`, `Degraded=False` |

> **Degraded?** → `oc describe co <name>`

### 2.3 API & Console URLs
```bash
API_URL=$(oc whoami --show-server)
CONSOLE_URL=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}')
echo "API: $API_URL"
echo "Console: https://$CONSOLE_URL"
```

Test:
```bash
curl -k $API_URL/version
```

---

<a name="ipi-specific-troubleshooting"></a>
## 3. IPI-Specific Troubleshooting

> **Installer-Provisioned Infrastructure**  
> Azure resources created by `openshift-install create cluster`

### 3.1 Verify Azure Resource Group
```bash
az group show --name <cluster-name>-<random> --query "{name:name, location:location}"
```

### 3.2 List Key Resources
```bash
az resource list --resource-group <rg> --output table
```

| Resource Type | Expected Count |
|---------------|----------------|
| `Microsoft.Compute/virtualMachines` | 3 masters + N workers |
| `Microsoft.Network/virtualNetworks` | 1 |
| `Microsoft.Network/loadBalancers` | 2 (internal + external) |
| `Microsoft.Network/publicIPAddresses` | 1+ |

### 3.3 Check Installer Logs
```bash
tail -50 ~/.openshift_install.log | grep -i error
```

### 3.4 Recreate Manifests (if needed)
```bash
openshift-install create manifests --dir=~/ipi-cluster
# Inspect: manifests/cluster-network-*.yaml, etc.
```

---

<a name="upi-specific-troubleshooting"></a>
## 4. UPI-Specific Troubleshooting

> **User-Provisioned Infrastructure**  
> You pre-created VNet, subnets, VMs, LB, DNS, etc.

### 4.1 Validate Pre-Reqs

| Item | Command |
|------|--------|
| VNet & Subnets | `az network vnet subnet list --resource-group <rg> --vnet-name <vnet>` |
| Master VMs | `az vm list --resource-group <rg> --query "[?contains(name,'master')]"` |
| Bootstrap VM | `az vm show -d -g <rg> -n <cluster>-bootstrap` |
| Load Balancer | `az network lb show -g <rg> -n <cluster>-lb` |
| DNS A Records | `nslookup api.<cluster>.<domain>` |

### 4.2 Bootstrap Ignition
```bash
# From bootstrap host
journalctl -b -u bootkube.service | tail -50
```

### 4.3 Approval of CSRs
```bash
oc get csr -w
# Approve pending:
oc get csr -o name | xargs oc adm certificate approve
```

### 4.4 Destroy & Retry (if stuck)
```bash
openshift-install destroy cluster --dir=~/upi-cluster
# Then re-run ignition configs
```

---

<a name="register-cluster"></a>
## 5. Register Cluster in Red Hat Hybrid Cloud Console

> **Critical**: Self-managed clusters **do NOT auto-register**

### 5.1 Generate Registration Token
1. Go to: https://console.redhat.com/openshift/create
2. Click **"Connect an existing cluster"**
3. Select **"Self-managed"** → **"Azure"**
4. **Generate token**

### 5.2 Register via API
```bash
CLUSTER_ID=$(oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}')
TOKEN="sha256~xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

curl -X POST https://api.openshift.com/api/registration/v1/register-cluster \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$(oc cluster-info | head -1 | awk '{print $NF}' | cut -d'/' -f3)\",
    \"cluster_id\": \"$CLUSTER_ID\",
    \"platform\": \"azure\",
    \"region\": \"$(az account show --query name -o tsv | tr ' ' '-' | tr '[:upper:]' '[:lower:]')\"
  }"
```

> Success → `{"cluster_id": "..."}`

### 5.3 Wait & Verify
```text
Wait 5–15 minutes → Refresh console.redhat.com/openshift
```

---

<a name="pull-secret-org-mismatch"></a>
## 6. Pull Secret & Org Mismatch

### 6.1 Extract Current Pull Secret
```bash
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > current.json
jq -r '.auths."cloud.openshift.com".email // empty' current.json
```

### 6.2 Download Correct Pull Secret
→ https://console.redhat.com/openshift/token → **Download**

### 6.3 Patch Pull Secret
```bash
oc patch secret pull-secret -n openshift-config -p="$(cat <<EOF
{
  "data": {
    ".dockerconfigjson": "$(base64 -w 0 new-pull-secret.json)"
  }
}
EOF
)"
```

> **Wait 2 min** → `oc get pods -n openshift-image-registry`

---

<a name="network-telemetry"></a>
## 7. Network & Telemetry

### 7.1 Required Outbound URLs
```text
*.api.openshift.com:443
infogw.api.openshift.com:443
console.redhat.com:443
sso.redhat.com:443
cert-api.access.redhat.com:443
api.access.redhat.com:443
```

### 7.2 Test Telemetry
```bash
oc run telemetry-test --image=registry.redhat.io/ubi9/ubi --rm -it -- \
  curl -s https://infogw.api.openshift.com/metrics/v1/telemetry
```

### 7.3 Enable Insights
```bash
oc create -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    telemeterClient:
      telemeterServerURL: https://infogw.api.openshift.com
EOF
```

---

<a name="validation"></a>
## 8. Validation & Final Checks

```bash
#!/bin/bash
echo "=== FINAL VALIDATION ==="
echo "1. Cluster Operators:"
oc get co | awk '{print $1,$3,$4,$5}'

echo -e "\n2. Cluster ID:"
oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}'

echo -e "\n3. Pull Secret Org:"
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths."cloud.openshift.com".email // "N/A"'

echo -e "\n4. Console Visibility: https://console.redhat.com/openshift"
```

---

<a name="support-escalation"></a>
## 9. Support Escalation

### Red Hat Case
1. Go to: https://access.redhat.com/support
2. Open case: **"Self-managed OpenShift on Azure not visible in console"**
3. Attach:
   - `oc adm must-gather` (tar.gz)
   - `oc get clusterversion -o yaml`
   - `install-config.yaml` (redact secrets)
   - Pull secret org email
   - Output of validation script

### Azure Case (if needed)
- Subscription ID
- Resource Group
- Cluster name
- Activity logs (failed operations)

---

## Summary Checklist

| Task | IPI | UPI |
|------|-----|-----|
| Cluster boots in Azure | Yes | Yes |
| `oc login` works | Yes | Yes |
| All COs healthy | Yes | Yes |
| Pull secret matches console.redhat.com org | Yes | Yes |
| Cluster registered via token | Yes | Yes |
| Appears in console.redhat.com | Yes | Yes |
| Telemetry enabled | Yes | Yes |

---

**Download this file**: [openshift-azure-troubleshooting.md](https://gist.github.com/yourname/xxxx)

---

*Last Updated: November 07, 2025*  
*References*:  
- [Red Hat Docs: Registering a Cluster](https://docs.openshift.com/container-platform/4.15/installing/installing_azure/installing-azure-account.html#installation-registering-cluster_installing-azure-account)  
- [Azure OpenShift IPI](https://learn.microsoft.com/en-us/azure/openshift/tutorial-create-cluster)  
- [UPI on Azure](https://docs.openshift.com/container-platform/4.15/installing/installing_azure/installing-azure-upi.html)
```
```

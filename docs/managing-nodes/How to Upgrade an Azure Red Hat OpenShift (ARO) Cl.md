<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" class="logo" width="120"/>

## How to Upgrade an Azure Red Hat OpenShift (ARO) Cluster

**Prerequisites**

- Ensure you have admin privileges on the ARO cluster.
- Update your Azure CLI to the latest supported version.
- Make sure your Red Hat pull secret is up to date, including the `cloud.openshift.com` entry.
- Validate that your service principal or managed identity credentials are current and valid before starting the upgrade[^1][^2][^3].

---

**Upgrade Methods**

You can upgrade an ARO cluster using either:

- The OpenShift web console
- The managed-upgrade-operator (MUO)

---

### Upgrading via the OpenShift Web Console

1. **Access the Console**: Sign in as `kubeadmin` and navigate to the OpenShift web console.
2. **Navigate to Cluster Settings**:
    - Go to **Administration** > **Cluster Settings** > **Details**.
    - Review the current version, update status, and channel.
3. **Select Update Channel**:
    - Click the **Channel** link and enter your desired update channel (e.g., `stable-4.10`).
    - A graph of available releases appears.
4. **Initiate Upgrade**:
    - If **Updates Available** is shown, select the version you want to upgrade to and click **Update**.
    - The status will show `Update to <product-version> in progress`.
    - Monitor progress via the console, which displays operator and node upgrade status[^1][^2].

---

### Upgrading via the Managed-Upgrade-Operator (MUO)

The MUO automates and schedules upgrades but delegates the actual upgrade to the OpenShift platform itself.

1. **Prepare UpgradeConfig File**: Create a YAML file specifying the upgrade details:

```yaml
apiVersion: upgrade.managed.openshift.io/v1alpha1
kind: UpgradeConfig
metadata:
  name: managed-upgrade-config
  namespace: openshift-managed-upgrade-operator
spec:
  type: "ARO"
  upgradeAt: "2025-04-08T03:20:00Z"
  PDBForceDrainTimeout: 60
  desired:
    channel: "stable-4.16"
    version: "4.16.37"
```

    - `channel`: The update channel (e.g., `stable-4.16`)
    - `version`: Target OpenShift version (e.g., `4.16.37`)
    - `upgradeAt`: Scheduled upgrade time[^1][^2].
2. **Apply the Configuration**:

```sh
oc create -f <file_name>.yaml
```

This schedules the upgrade according to the specified time and parameters[^1][^2].

---

## How the Upgrade Works Behind the Scenes

- **Desired State Model**: OpenShift upgrades use a "desired state" approach. When you select a new version, the cluster's `ClusterVersion` object is updated to reflect the new desired version[^6].
- **Operators and Automation**: Cluster operators (for monitoring, logging, etc.) run in a loop, reconciling the cluster state to match the desired version. The upgrade process is orchestrated by these operators, which sequentially upgrade cluster components and nodes.
- **Rolling Upgrades**: The upgrade is performed in a rolling manner to minimize downtime. Control plane components are upgraded first, followed by worker nodes, ensuring workloads remain available[^6].
- **Progress Monitoring**: The upgrade status and progress can be tracked in the web console, showing which operators and nodes are upgrading.

---

## Initiating and Monitoring the Upgrade

- **Web Console**: Initiate the upgrade by selecting the desired version and channel, then monitor progress bars for each operator and node.
- **MUO**: Schedule upgrades in advance using the configuration file and monitor via the console or CLI.
- **CLI (for managed identities)**: For clusters with managed identities, set the `upgradeable-to` annotation using:

```sh
az aro update --name <CLUSTER_NAME> --resource-group <RESOURCE_GROUP> --upgradeable-to <VERSION>
```

This prepares the cluster for upgrade; you must still complete the process via the console or MUO[^2].

---

## Summary Table: Upgrade Methods

| Method | How to Initiate | Scheduling | Monitoring |
| :-- | :-- | :-- | :-- |
| Web Console | Select version \& update in UI | Immediate | Console progress UI |
| Managed-Upgrade-Operator | Apply UpgradeConfig YAML | Scheduled (`upgradeAt`) | Console/CLI |
| CLI (Managed Identity) | `az aro update` + console/MUO | N/A | Console/CLI |


---

Upgrading your ARO cluster ensures you receive the latest features and security updates. The process is designed to be automated, safe, and observable, leveraging OpenShift's operator framework and desired state model for minimal disruption[^1][^2][^6].

<div style="text-align: center">⁂</div>

[^1]: https://learn.microsoft.com/en-us/azure/openshift/howto-upgrade

[^2]: https://learn.microsoft.com/en-us/azure/openshift/howto-upgrade-aro-openshift-cluster

[^3]: https://access.redhat.com/solutions/7015418

[^4]: https://cloud.redhat.com/experts/aro/upgrade-disconnected-aro/

[^5]: https://www.ibm.com/docs/en/netezza?topic=unpscpdao4-upgrading-red-hat-openshift-container-platform-azure-ocp-412

[^6]: https://www.redhat.com/en/blog/the-ultimate-guide-to-openshift-release-and-upgrade-process-for-cluster-administrators

[^7]: https://docs.openshift.com/container-platform/3.11/upgrading/index.html

[^8]: https://www.youtube.com/watch?v=7j8yjisMh8o


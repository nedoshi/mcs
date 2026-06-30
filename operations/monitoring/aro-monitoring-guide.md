Got it — you want a **practical, step-by-step setup guide** for monitoring and alerting in **Azure Red Hat OpenShift (ARO)**.

The short version is:

* ARO runs on Azure, so you can monitor with **Azure Monitor** and **Prometheus/Grafana** inside OpenShift.
* Alerts can be handled in both Azure and OpenShift’s Alertmanager.
* Integration between the two ensures you see OpenShift cluster metrics in Azure Monitor.

Here’s a **full setup guide** for both Azure-native and OpenShift-native monitoring.

---

## **1. Decide Your Monitoring Approach**

You can:

* **Option A**: Use Azure Monitor for container insights (good for infra + pod metrics in Azure Portal).
* **Option B**: Use OpenShift’s built-in monitoring stack (Prometheus, Alertmanager, Grafana).
* **Option C**: Integrate both for full visibility.

I recommend **C** if you want a complete picture.

---

## **2. Enable Azure Monitor for ARO**

1. **Prerequisites**

   * `az` CLI installed and logged in
   * Access to the ARO resource group and subscription
   * A Log Analytics Workspace

2. **Create or Use an Existing Log Analytics Workspace**

   ```bash
   az monitor log-analytics workspace create \
     --resource-group <RESOURCE_GROUP> \
     --workspace-name <WORKSPACE_NAME> \
     --location <LOCATION>
   ```

3. **Enable Container Insights for the ARO Cluster**

   ```bash
   az monitor container insights enable \
     --workspace <WORKSPACE_ID> \
     --resource-group <RESOURCE_GROUP> \
     --cluster-name <ARO_CLUSTER_NAME> \
     --cluster-type openshift
   ```

   > This will deploy the `omsagent` DaemonSet to collect logs/metrics.

4. **Verify in Azure Portal**

   * Go to **Monitor → Insights → Containers**
   * Select your ARO cluster
   * You should now see node, pod, and container metrics.

---

## **3. Enable and Configure OpenShift Native Monitoring**

ARO comes with **two monitoring stacks**:

* **Cluster monitoring** (for platform components, managed by Red Hat)
* **User workload monitoring** (for your apps, opt-in)

### **Enable User Workload Monitoring**

1. Log in to OpenShift as a cluster admin:

   ```bash
   oc login <API_SERVER> --token=<TOKEN>
   ```
2. Edit the config map to enable:

   ```bash
   oc -n openshift-monitoring edit configmap cluster-monitoring-config
   ```

   Add:

   ```yaml
   data:
     config.yaml: |
       enableUserWorkload: true
   ```
3. Save and exit — this will deploy Prometheus and Alertmanager for user workloads in `openshift-user-workload-monitoring`.

---

## **4. Create a Sample Alert in OpenShift**

1. Create an alert rule file:

   ```yaml
   groups:
   - name: example.rules
     rules:
     - alert: HighPodCPUUsage
       expr: sum(rate(container_cpu_usage_seconds_total{namespace="my-app"}[5m])) > 0.8
       for: 2m
       labels:
         severity: warning
       annotations:
         summary: "High CPU usage detected in my-app namespace"
   ```

2. Apply it:

   ```bash
   oc apply -f high_cpu_alert.yaml -n openshift-user-workload-monitoring
   ```

3. View in OpenShift Console:

   * Go to **Observe → Alerts** to see it fire.

---

## **5. Configure Alert Routing**

### **In OpenShift Alertmanager**

1. Get the Alertmanager secret:

   ```bash
   oc -n openshift-monitoring get secret alertmanager-main -o jsonpath="{.data.alertmanager\.yaml}" | base64 --decode > alertmanager.yaml
   ```
2. Edit `alertmanager.yaml` to add a receiver (example: send to email):

   ```yaml
   receivers:
   - name: 'team-email'
     email_configs:
     - to: 'alerts@example.com'
       from: 'openshift@example.com'
       smarthost: 'smtp.example.com:587'
       auth_username: 'openshift@example.com'
       auth_password: 'SMTP_PASSWORD'
   route:
     receiver: 'team-email'
   ```
3. Update the secret:

   ```bash
   oc -n openshift-monitoring create secret generic alertmanager-main --from-file=alertmanager.yaml --dry-run=client -o yaml | oc apply -f -
   ```
4. Restart Alertmanager pods:

   ```bash
   oc -n openshift-monitoring delete pod -l app=alertmanager
   ```

---

## **6. (Optional) Forward Prometheus Metrics to Azure Monitor**

If you want ARO’s Prometheus metrics in Azure Monitor:

* Use **Azure Monitor Managed Prometheus** or an **Azure Data Collection Rule (DCR)** to scrape your Prometheus endpoint.
* This requires an Azure Monitor workspace with **Prometheus add-on** enabled.

---

## **7. Ongoing Monitoring**

* Use **Azure Monitor Alerts** for infrastructure-level triggers (node down, CPU > 80%, etc.).
* Use **OpenShift Alertmanager** for Kubernetes-specific and application-specific metrics.
* Use **Grafana** in OpenShift (`openshift-monitoring` namespace) for dashboards.

---

✅ **End Result**:
You’ll have:

* Azure Monitor giving you infra & container health
* Prometheus & Grafana inside OpenShift for app-level metrics
* Alertmanager sending notifications to email/Slack/MS Teams
* The ability to correlate issues from Azure side and OpenShift side

---

If you’d like, I can make you a **diagram showing the full flow** of monitoring + alerts for ARO so it’s easy to present to your team. That will also help clarify where Azure Monitor ends and OpenShift’s Prometheus begins.

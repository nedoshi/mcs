# Bug Report: AWS neuron-scheduler Overwrites OVN-Kubernetes Pod Network Annotations

| Field | Value |
|-------|-------|
| **Status** | Open -- Production Workaround Available (MutatingAdmissionWebhook verified), Long-Term Fix Identified (Neuron DRA) |
| **Severity** | Critical -- Blocks all multi-core Inferentia pod deployments on OVN-Kubernetes clusters |
| **Date Filed** | April 2026 |
| **Affected Platform** | Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) |
| **Upstream Tracker** | None filed yet -- no existing issue covers this specific conflict |
| **Related Issues** | [awslabs/operator-for-ai-chips-on-aws #65](https://github.com/awslabs/operator-for-ai-chips-on-aws/issues/65), [aws-neuron/aws-neuron-sdk #1300](https://github.com/aws-neuron/aws-neuron-sdk/issues/1300) |

---

## Summary

The AWS `neuron-scheduler` extension overwrites the `k8s.ovn.org/pod-networks` annotation set by OVN-Kubernetes during its pod Bind callback. This destroys the pod's network configuration, causing the OVN CNI plugin to time out waiting for the missing annotation. Every pod that requests multiple NeuronCores and uses the `neuron-scheduler` on an OVN-Kubernetes cluster is affected. The pod becomes permanently stuck in `ContainerCreating` and never receives an IP address.

---

## Environment and Component Versions

| Component | Version | Role in This Issue |
|-----------|---------|-------------------|
| **OpenShift** | 4.21.6 | ROSA HCP, Kubernetes v1.34.4 |
| **CNI** | OVN-Kubernetes (default on ROSA HCP) | Sets `k8s.ovn.org/pod-networks` annotation -- the annotation that gets overwritten |
| **AWS Neuron Operator** | 1.1.1 | Deploys the neuron-scheduler, device plugin, and scheduler extension |
| **neuron-scheduler** | `public.ecr.aws/neuron/neuron-scheduler:2.24.23.0` | Custom Kubernetes scheduler for NeuronCore topology-aware placement |
| **neuron-scheduler-extension** | `public.ecr.aws/neuron/neuron-scheduler:2.24.23.0` (same image) | Scheduler extension that writes device allocation annotations via Bind callback |
| **Neuron device plugin** | `public.ecr.aws/neuron/neuron-device-plugin:2.24.23.0` | Reads scheduler annotations to assign specific Neuron hardware devices to containers |
| **AWS Neuron SDK** | 2.28.0 | Runtime on the Inferentia2 node |
| **Instance type** | `inf2.24xlarge` (12 NeuronCores) and `inf2.48xlarge` (24 NeuronCores) | Both affected |
| **vLLM (Neuron)** | 0.13.0 (`public.ecr.aws/neuron/pytorch-inference-vllm-neuronx:0.13.0-neuronx-py312-sdk2.28.0-ubuntu24.04`) | The workload pod -- any workload using neuron-scheduler is affected |
| **RHCOS** | 9.6 (Plow), Kernel 5.14.0-570.98.1.el9_6.x86_64 | Node OS |

---

## Symptom

Pods requesting `aws.amazon.com/neuroncore` resources with `schedulerName: neuron-scheduler` become permanently stuck in `ContainerCreating`. The kubelet reports:

```
Warning  FailedCreatePodSandBox  <timestamp>  kubelet  Failed to create pod sandbox:
  rpc error: code = Unknown desc = failed to configure pod interface:
  failed to get pod annotation: timed out waiting for annotations:
  context deadline exceeded
```

The kubelet retries every ~2 minutes. Each attempt times out after 120 seconds (the OVN CNI's annotation wait deadline). The pod never gets an IP address and never transitions to `Running`.

**Key observations from pod inspection while stuck:**

```yaml
metadata:
  annotations:
    AWS_NEURON_IDS: "0,1,2,3,4,5,6,7"
    NEURON_ALLOCATED: "true"
    NEURON_ALLOC_TIME: "1743574052764891534"
    # k8s.ovn.org/pod-networks is ABSENT
```

The Neuron annotations are present. The OVN annotation is missing -- even though OVN controller logs confirm it was successfully written earlier.

---

## Root Cause

### The Annotation Lifecycle

Two independent controllers must write annotations to the same pod object at nearly the same time:

**Step 1 -- Pod creation:** The pod object is created in etcd with only the annotations specified in the pod spec (typically none relevant here).

**Step 2 -- OVN-Kubernetes acts first (~15-30ms):** The `ovnkube-controller` watches for new pods, assigns an IP from the logical switch, and writes:

```
k8s.ovn.org/pod-networks: '{"default":{"ip_addresses":["10.128.x.y/23"],
  "mac_address":"0a:58:0a:80:xx:yy","gateway_ips":["10.128.x.1"],
  "ip_address":"10.128.x.y/23","gateway_ip":"10.128.x.1",
  "routes":[...]}}'
```

**Step 3 -- neuron-scheduler Bind callback (~50-200ms):** The neuron-scheduler extension determines which physical Neuron devices to allocate and writes its annotations. However, the extension performs a **full object update** (or non-strategic patch) on the pod, replacing the entire `metadata.annotations` map with a new map containing only its own keys:

```
AWS_NEURON_IDS: "0,1,2,3,4,5,6,7"
NEURON_ALLOCATED: "true"
NEURON_ALLOC_TIME: "1743574052764891534"
```

This replaces the OVN annotation that was already written in Step 2.

**Step 4 -- kubelet calls CNI:** The kubelet's container runtime calls the OVN CNI plugin to set up the pod's network namespace. The CNI plugin reads `k8s.ovn.org/pod-networks` from the pod object -- it is now missing. The CNI polls for 120 seconds, then times out.

### Why the neuron-scheduler Overwrites (Not Merges)

The neuron-scheduler extension's RBAC grants both `patch` and `update` verbs on pods ([scheduler_extension_cluster_role.yaml](https://github.com/awslabs/operator-for-ai-chips-on-aws/blob/main/config/rbac/scheduler_extension_cluster_role.yaml)). The extension's source code is not published -- it ships only as a compiled binary in the container image `public.ecr.aws/neuron/neuron-scheduler:2.24.23.0`. Based on observed behavior:

- The extension reads the current pod object
- It sets its three annotation keys on the local copy
- It writes the pod back using a method that does **not** preserve other annotations

This could be a `PUT` (full object replacement) or a JSON patch that targets the entire `metadata.annotations` field rather than individual keys within it. Either would produce the observed behavior.

A correct implementation would use **JSON Merge Patch** targeting individual annotation keys, **strategic merge patch**, or **server-side apply** with a field manager.

---

## When It Happens

| Condition | Affected? | Why |
|-----------|-----------|-----|
| Pod requests ≥1 `aws.amazon.com/neuroncore` with `schedulerName: neuron-scheduler` | **Yes** | neuron-scheduler Bind callback writes annotations, overwriting OVN's |
| Pod requests `aws.amazon.com/neuroncore` with `schedulerName: default-scheduler` | **No** (fails differently) | Default scheduler does not write Neuron annotations; device plugin rejects allocation |
| Pod with no NeuronCore request on an Inferentia node | **No** | Default scheduler binds the pod; no annotation conflict |
| NVIDIA GPU pod with `default-scheduler` | **No** | NVIDIA device plugin does not use custom annotations for allocation |
| Any pod on a cluster using Calico or another CNI (not OVN-Kubernetes) | **Unknown** | Other CNIs may not rely on `k8s.ovn.org/pod-networks`; untested |
| First pod creation after node boot | **Yes** | Occurs on every neuron-scheduled pod, not just edge cases |
| Pod restart / rescheduling | **Yes** | Race occurs again on each new pod object creation |

This is **not** specific to any particular workload, model, llm-d, KServe, or vLLM. It affects any pod using the neuron-scheduler on an OVN-Kubernetes cluster.

---

## Why It Happens

The root cause is an **impedance mismatch** between two components that were not designed to coexist:

1. **OVN-Kubernetes** expects that once it writes `k8s.ovn.org/pod-networks`, the annotation will persist on the pod object. It does not re-check or re-write this annotation after the initial write.

2. **neuron-scheduler extension** expects that it is the only controller writing to `metadata.annotations` during the Bind phase. It was likely developed and tested on Amazon EKS, which uses the AWS VPC CNI -- a CNI that does not use Kubernetes annotations for pod network configuration. The annotation overwrite is harmless on EKS but destructive on OVN-Kubernetes.

3. **Kubernetes API** does not protect individual annotation keys from being overwritten by full-object updates. There is no built-in mechanism to mark specific annotations as "must preserve."

---

## Current Workaround (Verified)

Force-restart the `ovnkube-node` pod on the Inferentia node **after** the neuron-scheduler has completed its annotation writes. This triggers OVN to re-reconcile all pods on the node, re-applying the `k8s.ovn.org/pod-networks` annotation.

### Procedure

```bash
NAMESPACE="<model-namespace>"
POD_LABEL="<pod-selector>"

POD_NAME=$(oc get pod -n $NAMESPACE -l $POD_LABEL \
  -o jsonpath='{.items[0].metadata.name}')

echo "Waiting for NEURON_ALLOCATED=true..."
while true; do
  ALLOC=$(oc get pod -n $NAMESPACE $POD_NAME \
    -o jsonpath='{.metadata.annotations.NEURON_ALLOCATED}' 2>/dev/null)
  if [ "$ALLOC" = "true" ]; then
    echo "Neuron allocation complete."
    break
  fi
  sleep 2
done

sleep 5

INF_NODE=$(oc get pod -n $NAMESPACE $POD_NAME \
  -o jsonpath='{.spec.nodeName}')
OVN_POD=$(oc get pods -n openshift-ovn-kubernetes \
  --field-selector spec.nodeName=$INF_NODE -o name | head -1)

echo "Restarting $OVN_POD on $INF_NODE..."
oc delete $OVN_POD -n openshift-ovn-kubernetes --grace-period=0 --force
echo "OVN will re-reconcile. Pod should get an IP within 30-60 seconds."
```

### Conditions for Reliability

- **Single clean pod creation** -- do not rapidly create/delete pods, which leaves the scheduler extension in stale state
- **Wait for `NEURON_ALLOCATED=true`** before restarting OVN -- this ensures the neuron-scheduler is finished writing annotations
- **5-second buffer** after `NEURON_ALLOCATED=true` -- gives time for any final annotation writes to settle
- **Restart the scheduler extension** if it has been processing many force-deletes (its internal `NEURON_CORE_USAGE_MAP` can become stale)

### Limitations

- Requires manual intervention or a custom controller on every pod creation
- Restarting `ovnkube-node` briefly disrupts networking for all pods on that node (existing connections may see a ~5-10s blip)
- Does not fix the root cause; the annotation will be overwritten again on next pod creation

---

## Recommended Fixes

### Fix 1: MutatingAdmissionWebhook (Annotation Preservation)

**Concept:** Deploy a custom webhook that intercepts pod UPDATE operations. When the incoming update would remove `k8s.ovn.org/pod-networks` (present in `oldObject` but absent in `newObject`), the webhook re-adds it from the old object.

**How it works:**

The Kubernetes API populates `request.oldObject` on UPDATE operations in AdmissionReview requests. The webhook compares `oldObject.metadata.annotations["k8s.ovn.org/pod-networks"]` with the new object. If the annotation was present and is now missing, the webhook returns a JSON Patch that restores it.

**Implementation:**

```go
package main

import (
    "encoding/json"
    "fmt"
    "net/http"

    admissionv1 "k8s.io/api/admission/v1"
    corev1 "k8s.io/api/core/v1"
)

const ovnAnnotation = "k8s.ovn.org/pod-networks"

func handleMutate(w http.ResponseWriter, r *http.Request) {
    var review admissionv1.AdmissionReview
    json.NewDecoder(r.Body).Decode(&review)

    if review.Request.Operation != admissionv1.Update {
        allow(&review, w)
        return
    }

    oldPod := &corev1.Pod{}
    newPod := &corev1.Pod{}
    json.Unmarshal(review.Request.OldObject.Raw, oldPod)
    json.Unmarshal(review.Request.Object.Raw, newPod)

    oldVal := oldPod.Annotations[ovnAnnotation]
    _, newHas := newPod.Annotations[ovnAnnotation]

    if oldVal != "" && !newHas {
        escapedKey := "k8s.ovn.org~1pod-networks"
        patch := fmt.Sprintf(
            `[{"op":"add","path":"/metadata/annotations/%s","value":%s}]`,
            escapedKey, jsonMarshalString(oldVal),
        )
        patchType := admissionv1.PatchTypeJSONPatch
        review.Response = &admissionv1.AdmissionResponse{
            UID:       review.Request.UID,
            Allowed:   true,
            PatchType: &patchType,
            Patch:     []byte(patch),
        }
    } else {
        allow(&review, w)
        return
    }

    json.NewEncoder(w).Encode(review)
}
```

**Webhook configuration:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: preserve-ovn-pod-networks
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
webhooks:
  - name: preserve-ovn.neuron-fix.io
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    timeoutSeconds: 5
    reinvocationPolicy: IfNeeded
    namespaceSelector:
      matchExpressions:
        - key: neuron-workload
          operator: In
          values: ["true"]
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
        operations: ["UPDATE"]
    clientConfig:
      service:
        name: ovn-annotation-preserver
        namespace: neuron-webhook
        path: /mutate
```

**TLS on OpenShift:** Use the OpenShift Service CA operator. Annotate the webhook's `Service` with `service.beta.openshift.io/serving-cert-secret-name: webhook-tls` and the `MutatingWebhookConfiguration` with `service.beta.openshift.io/inject-cabundle: "true"`. OpenShift will auto-provision and inject the CA bundle.

**ROSA HCP compatibility:** Custom `MutatingWebhookConfiguration` resources are supported on ROSA HCP. There is no documented blanket prohibition. ROSA HCP does restrict certain webhooks that interfere with cluster upgrades, but a narrowly scoped webhook on pod UPDATEs in labeled namespaces does not fall into restricted categories. Validate with your Red Hat account team for contractual support implications.

| Dimension | Assessment |
|-----------|------------|
| **Confidence** | High -- the Kubernetes admission API is well-documented and this pattern (preserving annotations on UPDATE) is straightforward |
| **Effort** | 3-5 days for production deployment (Go code, tests, Dockerfile, Helm chart, OpenShift cert wiring, staging validation) |
| **Risk** | Medium -- a misconfigured `failurePolicy: Fail` webhook that is down will block all pod updates in scoped namespaces. Mitigate with health checks, replicas, and PodDisruptionBudget |
| **Blast radius** | Limited to namespaces with `neuron-workload=true` label |
| **Maintenance** | Ongoing -- must be kept running, monitored, and upgraded with OpenShift |
| **Can be done now** | **Yes** -- no upstream changes required |

**Pros:**
- Fixes the issue inline, before the annotation is persisted to etcd
- Full control over logic and scope
- Works with any Kubernetes version that supports dynamic admission (all modern versions)
- No disruption to OVN or other node components
- Can be extended to preserve other annotations if needed

**Cons:**
- You own the lifecycle: availability, upgrades, monitoring, incident response
- JSON Patch escaping for annotation keys containing `/` requires careful handling (`k8s.ovn.org~1pod-networks`)
- Adds latency to every pod UPDATE in scoped namespaces (typically <5ms per call)
- If the webhook is unavailable and `failurePolicy: Fail`, pod updates are blocked
- Need to consider webhook ordering if other mutating webhooks exist

---

### Fix 2: Kyverno Mutate Policy

**Concept:** Same logic as the webhook, but implemented as a Kyverno `ClusterPolicy` using Kyverno's policy engine instead of custom Go code.

**How it works:**

Kyverno runs as a mutating admission webhook itself. It provides access to `request.oldObject` and `request.object` in policy rules, allowing you to detect when an annotation has been removed and restore it.

**Implementation:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: preserve-ovn-pod-networks
  annotations:
    policies.kyverno.io/title: Preserve OVN Pod Network Annotations
    policies.kyverno.io/description: >-
      Restores the k8s.ovn.org/pod-networks annotation when the
      neuron-scheduler extension overwrites it during pod bind.
    policies.kyverno.io/severity: critical
spec:
  failurePolicy: Fail
  webhookTimeoutSeconds: 5
  rules:
    - name: restore-ovn-annotation-on-update
      match:
        any:
          - resources:
              kinds:
                - Pod
              operations:
                - UPDATE
              namespaces:
                - "llm-serving"
                - "llm-d-gpu"
      preconditions:
        all:
          - key: "{{ request.oldObject.metadata.annotations.\"k8s.ovn.org/pod-networks\" || '' }}"
            operator: NotEquals
            value: ""
          - key: "{{ request.object.metadata.annotations.\"k8s.ovn.org/pod-networks\" || '' }}"
            operator: Equals
            value: ""
      mutate:
        patchStrategicMerge:
          metadata:
            annotations:
              k8s.ovn.org/pod-networks: "{{ request.oldObject.metadata.annotations.\"k8s.ovn.org/pod-networks\" }}"
```

**Kyverno on ROSA HCP:**
- Kyverno is **not** a Red Hat-supported product. It is a CNCF incubating project with its own commercial support (Nirmata).
- Red Hat has published blog content on using Kyverno with OpenShift ([Guide to Mutations on OpenShift with Kyverno](https://www.redhat.com/en/blog/guide-to-mutations-of-a-resource-on-openshift-with-kyverno)), but it is not part of the ROSA subscription.
- Installation on ROSA HCP is via Helm or the Kyverno Operator. No special ROSA HCP restrictions apply to Kyverno installation.

**Known caveats:**
- **JMESPath escaping for annotation keys with `/`**: Kyverno uses JMESPath for variable references. The `/` in `k8s.ovn.org/pod-networks` requires careful quoting with backslash-escaped double quotes. This has been a source of issues ([kyverno/kyverno #6410](https://github.com/kyverno/kyverno/issues/6410)). Test thoroughly.
- **`mutateExisting` is asynchronous**: Kyverno's `mutateExisting` rules run in the background, not at admission time. The policy above uses standard admission-time mutation (not `mutateExisting`), which is correct for this use case.
- **`oldObject` support in newer Kyverno APIs**: The `MutatingPolicy` CRD (newer Kyverno versions) has had gaps with `oldObject` access in some scenarios ([kyverno/kyverno #15610](https://github.com/kyverno/kyverno/issues/15610)). Stick to the stable `ClusterPolicy` API.

| Dimension | Assessment |
|-----------|------------|
| **Confidence** | High in theory; medium in practice due to JMESPath escaping edge cases |
| **Effort** | 1-2 days if Kyverno is already installed and approved; 4-7 days if installing Kyverno from scratch on ROSA HCP (install, harden, RBAC, HA, monitoring) |
| **Risk** | Medium -- Kyverno itself is a mutating webhook; its availability affects all resources it watches |
| **Blast radius** | Scoped to listed namespaces; Kyverno failure affects all policies, not just this one |
| **Maintenance** | Kyverno operator upgrades, policy management, monitoring dashboard |
| **Can be done now** | **Yes** -- no upstream changes required |

**Pros:**
- Policy-as-YAML, no custom Go code to maintain
- Faster iteration on policy logic
- Rich ecosystem (audit mode, reporting, policy sets)
- Well-understood OpenShift deployment model
- Can be extended to other annotation-preservation rules

**Cons:**
- Introduces a new cluster-wide component (Kyverno) if not already installed
- **Not Red Hat-supported** on ROSA -- community/Nirmata support only
- JMESPath handling of annotation keys with `/` has known issues
- Kyverno webhook latency under load can be problematic ([kyverno/kyverno #8635](https://github.com/kyverno/kyverno/issues/8635))
- Adding a dependency for a single policy may be excessive if Kyverno has no other use

---

### Fix 3: hostNetwork: true

**Concept:** Configure the Inferentia model pods to use the node's network namespace instead of a dedicated pod network namespace. This bypasses the OVN CNI entirely -- if the pod doesn't need a pod-specific network interface, OVN never needs to write the `k8s.ovn.org/pod-networks` annotation.

**Implementation:**

For KServe `InferenceService` (raw deployment mode), add to the predictor pod spec:

```yaml
spec:
  predictor:
    hostNetwork: true
    dnsPolicy: ClusterFirstWithHostNet
    containers:
      - name: kserve-container
        ports:
          - containerPort: 8080
            hostPort: 8080
```

For a standalone Deployment:

```yaml
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      schedulerName: neuron-scheduler
      containers:
        - name: vllm
          ports:
            - containerPort: 8080
              hostPort: 8080
```

**Critical: `dnsPolicy: ClusterFirstWithHostNet`** is mandatory. Without it, the pod inherits the node's `/etc/resolv.conf`, which does not resolve Kubernetes service names (e.g., `kubernetes.default.svc`).

| Dimension | Assessment |
|-----------|------------|
| **Confidence** | Medium -- avoids the OVN annotation dependency but introduces significant networking trade-offs |
| **Effort** | 1-2 days for prototype; 1-2 weeks to make production-safe (if possible at all) |
| **Risk** | **High** for production |
| **Blast radius** | Affects networking for all pods on the node |
| **Maintenance** | Ongoing port management, security review |
| **Can be done now** | **Yes** -- no upstream changes required, but may not be acceptable for production |

**What breaks or changes:**

| Area | Impact | Severity |
|------|--------|----------|
| **Pod IP** | Pod uses the node's IP, not a cluster Pod CIDR IP. `Endpoints` and `Service` backends reflect `<node-ip>:<port>`. | Medium |
| **Multiple replicas on same node** | **Port conflicts.** If two model pods both bind port 8080, the second fails. Must use different ports per replica or enforce one-pod-per-node with anti-affinity. On Inferentia where you might want 2-3 instances on an `inf2.48xlarge`, this is a significant constraint. | High |
| **Kubernetes Service discovery** | Works with `dnsPolicy: ClusterFirstWithHostNet`, but hairpin traffic (pod accessing its own Service) may have edge cases with OVN. | Medium |
| **NetworkPolicy** | Standard `NetworkPolicy` objects do **not** apply to host-network pods. The pod can see and bind to any port on the node. This breaks network isolation in multi-tenant clusters. | High |
| **Service Mesh / Istio** | Istio sidecar injection does **not work correctly** with host-network pods. The sidecar relies on iptables rules in the pod network namespace, which does not exist for host-network pods. This breaks mTLS, traffic routing, and observability. | High |
| **KServe integration** | KServe's readiness probes, Service creation, and Route exposure assume pod-network semantics. Host-network changes the pod's IP and may confuse KServe's reconciliation. Requires testing. | Medium |
| **Security** | Host-network pods can: bind any port on the node, observe node-level traffic, and bypass namespace network isolation. On multi-tenant clusters or clusters with compliance requirements (PCI-DSS, SOC2), this is typically not allowed. | High |
| **OpenShift SCC** | Requires a `SecurityContextConstraints` that allows `hostNetwork: true`. The default `restricted-v2` SCC does not permit this. | Medium |

**Pros:**
- Completely avoids the OVN annotation race -- no CNI annotation needed
- Simplest code change (two lines in pod spec)
- No new components to deploy

**Cons:**
- **Port conflicts** prevent multiple model instances on the same node
- **Breaks Service Mesh** -- no sidecar injection, no mTLS
- **Breaks NetworkPolicy** -- host-network pods are not subject to namespace isolation
- **Security risk** in multi-tenant environments
- **Not production-grade** for enterprise deployments with compliance requirements
- Trades one problem (annotation race) for multiple others (networking, security, operations)

---

### Fix 4: Neuron DRA (Dynamic Resource Allocation) Driver

**Concept:** Replace the legacy neuron-scheduler + device plugin with the [AWS Neuron DRA driver](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/containers/neuron-dra.html) (Neuron SDK 2.28.0+, [announced March 2026](https://aws.amazon.com/about-aws/whats-new/2026/03/neuron-eks-dra-support/)). DRA is a Kubernetes-native framework for hardware-aware scheduling that uses `ResourceClaim` objects for device allocation instead of pod annotations. The default Kubernetes scheduler handles topology-aware placement through DRA extensions, eliminating the custom `neuron-scheduler` and its Bind callback entirely.

**How it fixes the root cause:**

The annotation conflict exists because the neuron-scheduler's Bind callback writes device-allocation data into pod annotations using a full object replacement. DRA eliminates this by:
1. Removing the `neuron-scheduler` -- pods use `schedulerName: default-scheduler`
2. Replacing annotation-based device allocation with `ResourceClaim` / `ResourceClaimTemplate` API objects
3. Passing device information to containers via CDI (Container Device Interface), not annotations
4. OVN's `k8s.ovn.org/pod-networks` annotation is never overwritten because no component performs full annotation replacement

**Implementation:**

Install the Neuron DRA driver via the Neuron Helm chart:
```bash
helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart \
  --set "devicePlugin.enabled=false" \
  --set "npd.enabled=false" \
  --set "draDriver.enabled=true"
```

Replace legacy pod specs:
```yaml
# Legacy (triggers annotation conflict):
spec:
  schedulerName: neuron-scheduler
  containers:
    - resources:
        limits:
          aws.amazon.com/neuroncore: "8"

# DRA (no annotation conflict):
spec:
  containers:
    - resources:
        claims:
          - name: neurons
  resourceClaims:
    - name: neurons
      resourceClaimTemplateName: inferentia-8-cores
```

**Platform readiness:**

| Requirement | Status |
|-------------|--------|
| Kubernetes DRA API | GA in Kubernetes 1.32+; available in OpenShift 4.21 (K8s 1.34) |
| OpenShift DRA support | [GA in OpenShift 4.21](https://developers.redhat.com/articles/2026/03/25/dynamic-resource-allocation-goes-ga-red-hat-openshift-421-smarter-gpu) (March 2026) |
| Neuron DRA driver | Neuron SDK 2.28.0 (Feb 2026). Supports Inf1, Inf2, Trn1, Trn2, Trn3 |
| KServe integration | **Not yet supported.** KServe uses `resources.limits`, not `resourceClaims`. Requires upstream changes or raw Deployment mode. |
| ROSA HCP validation | **Not yet tested.** Validated on EKS; needs ROSA HCP testing. |

| Dimension | Assessment |
|-----------|------------|
| **Confidence** | **Very High** -- eliminates the root cause structurally |
| **Effort** | High -- architecture change: new Helm chart install, pod spec changes, KServe integration work |
| **Risk** | Medium -- new technology (March 2026), not validated on ROSA HCP |
| **Blast radius** | Replaces the entire Neuron scheduling stack |
| **Maintenance** | Lower long-term -- maintained by AWS as part of the Neuron stack |
| **Can be done now** | **Partially** -- DRA driver can be deployed, but KServe InferenceService integration requires upstream changes or switching to raw Deployments |

**Pros:**
- **Eliminates the root cause** -- no annotation-based device allocation means no annotation overwrite
- Aligns with Kubernetes direction (DRA is the future of device management)
- Maintained by AWS as part of the official Neuron stack
- Better topology-aware scheduling through native DRA constraints
- Reduces component count (removes neuron-scheduler, scheduler-extension)

**Cons:**
- KServe does not yet support `resourceClaims` in InferenceService -- the primary deployment method used in this project
- Very new (released Feb/March 2026) -- limited production validation
- Not yet validated on ROSA HCP specifically
- Requires changing the Neuron installation method from Operator to Helm chart
- Larger migration effort than the webhook fix

---

## Fix Comparison Matrix

| Criterion | MutatingAdmissionWebhook | Kyverno Policy | hostNetwork: true | Neuron DRA Driver |
|-----------|--------------------------|----------------|-------------------|-------------------|
| **Fixes root cause** | No (preserves annotation at admission) | No (preserves annotation at admission) | No (bypasses CNI) | **Yes** (eliminates annotation-based allocation) |
| **Prevents annotation loss** | Yes | Yes | N/A (no annotation needed) | N/A (no annotation written) |
| **Effort to implement** | 3-5 days | 1-7 days (depends on Kyverno state) | 1-2 days prototype | 2-4 weeks (incl. KServe integration) |
| **Production-ready** | Yes, with proper HA/monitoring | Yes, with Kyverno hardening | **No** -- significant trade-offs | Not yet (KServe gaps, ROSA HCP unvalidated) |
| **New components** | 1 Deployment + Service | Kyverno operator (if not installed) | None | Neuron DRA driver (replaces device plugin + scheduler) |
| **Red Hat supported** | Custom code -- your support | Community/Nirmata | N/A | AWS-maintained; DRA GA in OpenShift 4.21 |
| **Multi-replica on same node** | No impact | No impact | **Blocked** by port conflicts | No impact |
| **Service Mesh compatible** | Yes | Yes | **No** | Yes |
| **NetworkPolicy compatible** | Yes | Yes | **No** | Yes |
| **Risk level** | Medium (webhook availability) | Medium (Kyverno + JMESPath) | **High** (networking/security) | Medium (new technology, KServe gaps) |
| **Scope of disruption** | None (inline admission) | None (inline admission) | Node-wide networking changes | Replaces Neuron scheduling stack |
| **Needs upstream fix** | Not for the workaround itself | Not for the workaround itself | Not for the workaround itself | Needs KServe `resourceClaims` support |

---

## What Can Be Done Now vs. What Needs Upstream Fix

### Immediately Actionable (No Upstream Changes)

| Action | Who | Effort |
|--------|-----|--------|
| **OVN restart workaround** (current approach) | Cluster operator | Scripted (~30 min to automate) |
| **MutatingAdmissionWebhook** (**verified working** -- see [private_code_assistant.md Appendix B](private_code_assistant.md#appendix-b-ovn-annotation-fix----live-test-results-april-2-2026)) | Platform engineering team | 3-5 days |
| **Kyverno policy** (blocked by TLS init on OpenShift -- needs additional config) | Platform engineering team | 1-7 days |
| **Neuron DRA driver** (partially actionable -- driver install works, KServe integration pending) | Platform engineering team | 2-4 weeks |
| **File upstream bug** on `awslabs/operator-for-ai-chips-on-aws` | Anyone | 1 hour |

### Requires Upstream Fix

| Action | Owner | What Needs to Change |
|--------|-------|---------------------|
| **neuron-scheduler extension: use merge patch** | AWS Neuron team | The scheduler extension's Bind callback must use `application/merge-patch+json` or `application/strategic-merge-patch+json` instead of `PUT` (full object replacement) when writing `AWS_NEURON_IDS`, `NEURON_ALLOCATED`, `NEURON_ALLOC_TIME` annotations. Alternatively, use server-side apply with a dedicated field manager. |
| **OVN-Kubernetes: re-check annotations after Bind** | Red Hat / OVN-Kubernetes team | OVN could watch for pods that have been scheduled but are missing `k8s.ovn.org/pod-networks` and re-apply the annotation. This is a defensive fix on the OVN side and does not address the root cause. |
| **KServe: support DRA `resourceClaims`** | KServe community | KServe `InferenceService` needs to support `resourceClaims` in the pod spec alongside the existing `resources.limits` model. This would enable DRA-based Neuron device allocation without requiring raw Deployment mode. |

---

## Recommended Path Forward

### Short Term (Now)

Use the **OVN restart workaround** as documented in the Current Workaround section. Automate it with a watch script that monitors for pods stuck in `ContainerCreating` on Inferentia nodes, waits for `NEURON_ALLOCATED=true`, then restarts `ovnkube-node`.

### Medium Term (1-2 Sprints)

Deploy a **MutatingAdmissionWebhook** to eliminate the need for OVN restarts. This is the recommended programmatic fix because:

1. It is the most **surgical** -- only affects pod UPDATEs that would remove the OVN annotation
2. It requires **no new cluster-wide components** (unlike Kyverno)
3. It is **compatible with Service Mesh, NetworkPolicy, and multi-replica** deployments (unlike hostNetwork)
4. It can be scoped narrowly to Inferentia workload namespaces

If Kyverno is already installed or planned for other policy use cases, use the Kyverno policy instead -- it achieves the same result with less custom code.

### Long Term

**Migrate to the Neuron DRA driver.** The DRA driver (Neuron SDK 2.28.0+) eliminates the neuron-scheduler entirely, removing the root cause of the annotation conflict. DRA is GA in OpenShift 4.21 and supported for Inf1, Inf2, Trn1, Trn2, and Trn3 instances.

Prerequisites for DRA migration:
1. **KServe `resourceClaims` support** -- either upstream KServe adds this, or switch to raw Deployment mode for Inferentia workloads
2. **ROSA HCP validation** -- the Neuron DRA driver has been validated on EKS but not explicitly on ROSA HCP
3. **Neuron Helm chart compatibility** -- DRA installation uses the Helm chart (`draDriver.enabled=true`), which may differ from the current Operator-based installation

**File an upstream bug** with the AWS Neuron team regardless of which short/medium-term fix is chosen. The proper fix is for the neuron-scheduler extension to use merge patches for annotation writes. Reference this document and the annotation comparison (old vs new pod state) as evidence.

Track upstream releases of:
- `awslabs/operator-for-ai-chips-on-aws` -- for annotation patch behavior changes
- `public.ecr.aws/neuron/neuron-scheduler` -- for new image versions
- Red Hat OpenShift / OVN-Kubernetes -- for defensive annotation re-reconciliation
- `kserve/kserve` -- for DRA `resourceClaims` support in InferenceService
- [AWS Neuron DRA documentation](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/containers/neuron-dra.html) -- for ROSA/OpenShift validation updates

---

## Appendix: Upstream References

| Resource | URL | Relevance |
|----------|-----|-----------|
| AWS Neuron Scheduler Extension Flow | [docs](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/containers/tutorials/k8s-neuron-scheduler-flow.html) | Confirms annotation update happens in the extension |
| Neuron scheduler extension RBAC | [GitHub](https://github.com/awslabs/operator-for-ai-chips-on-aws/blob/main/config/rbac/scheduler_extension_cluster_role.yaml) | Shows `patch` and `update` verbs on pods |
| Stale node annotations issue | [GitHub #65](https://github.com/awslabs/operator-for-ai-chips-on-aws/issues/65) | Related annotation state issue (node-level, not pod-level) |
| Cross-filed scheduler state issue | [GitHub #1300](https://github.com/aws-neuron/aws-neuron-sdk/issues/1300) | Scheduler extension state management |
| Operator v1.1.0..v1.1.1 changelog | [GitHub diff](https://github.com/awslabs/operator-for-ai-chips-on-aws/compare/v1.1.0...v1.1.1) | No fix for annotation semantics |
| Kubernetes Dynamic Admission Control | [docs](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) | Webhook API reference |
| OpenShift Service CA Operator | [docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/security_and_compliance/configuring-certificates#understanding-service-serving-certs) | TLS cert automation for webhooks on OpenShift |
| Kyverno mutate rules | [docs](https://kyverno.io/docs/policy-types/cluster-policy/mutate/) | Kyverno policy authoring reference |
| Kyverno variables (oldObject) | [docs](https://kyverno.io/docs/policy-types/cluster-policy/variables/) | How Kyverno accesses old/new objects |
| Red Hat blog: Kyverno on OpenShift | [blog](https://www.redhat.com/en/blog/guide-to-mutations-of-a-resource-on-openshift-with-kyverno) | Red Hat guidance on Kyverno |
| Kyverno JMESPath + `/` issue | [GitHub #6410](https://github.com/kyverno/kyverno/issues/6410) | Known escaping issue |
| ROSA admission plug-ins | [docs](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/architecture/admission-plug-ins) | ROSA webhook support |
| Istio sidecar + host network | [docs](https://istio.io/latest/docs/ops/common-problems/injection/) | Host-network sidecar limitations |
| Kubernetes DNS for pods | [docs](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) | `ClusterFirstWithHostNet` DNS policy |
| AWS Neuron DRA documentation | [docs](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/containers/neuron-dra.html) | DRA driver that eliminates the neuron-scheduler |
| AWS Neuron DRA announcement | [announcement](https://aws.amazon.com/about-aws/whats-new/2026/03/neuron-eks-dra-support/) | March 2026 GA announcement |
| DRA GA in OpenShift 4.21 | [blog](https://developers.redhat.com/articles/2026/03/25/dynamic-resource-allocation-goes-ga-red-hat-openshift-421-smarter-gpu) | Red Hat confirmation of DRA GA in OpenShift 4.21 |
| Kubernetes DRA overview | [docs](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/) | Kubernetes upstream DRA documentation |

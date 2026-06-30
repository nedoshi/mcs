# Private Code Assistant -- End-to-End Deployment & Test Plan

> **Date**: April 2026
> **Cluster**: ROSA HCP `rosa-pca` (us-east-2, OCP 4.21.7)
> **RHOAI**: 3.3 | **Service Mesh**: 3.2.0 | **KServe**: 0.15 (with LLMInferenceService CRD)

---

## Table of Contents

- [Agent Execution Guidelines](#agent-execution-guidelines)
- [Part 1: End-to-End Deployment Plan](#part-1-end-to-end-deployment-plan)
  - [Step 0: Cluster Availability Check](#step-0-cluster-availability-check)
- [Part 2: Test Phases](#part-2-test-phases)
  - [Phase A: Per-Accelerator Throughput Consolidation](#phase-a-per-accelerator-throughput-consolidation)
  - [Phase B: Neuron DRA Driver Retest on Inferentia2](#phase-b-neuron-dra-driver-retest-on-inferentia2)
  - [Phase C: Heterogeneous llm-d Routing -- HTTPS Solution](#phase-c-heterogeneous-llm-d-routing----https-solution)
  - [Phase D: Same-Namespace Heterogeneous Deployment (VERIFIED — Default Method)](#phase-d-same-namespace-heterogeneous-deployment-verified--default-method)
  - [Phase E: GuideLLM Benchmark](#phase-e-guidellm-benchmark)
  - [Phase G: Dual Qwen3-Coder-30B on inf2.48xlarge](#phase-g-dual-qwen3-coder-30b-on-inf248xlarge)
  - [Phase F: Scale Down](#phase-f-scale-down)
- [Post-Deployment: Consolidated Access Report](#post-deployment-consolidated-access-report)

---

## Agent Execution Guidelines

When executing this plan (whether manually or via an AI coding agent), follow these guidelines:

### Reference Documentation

- **Primary reference**: `private_code_assistant.md` in this project contains the verified deployment steps, architecture details, component versions, troubleshooting history, and all known workarounds (OVN annotation fix, memory right-sizing, SELinux PVC sharing, Neuron compiler issues). Consult it before executing any step.
- **Inferentia-specific reference**: `vllmoninferentia.md` contains the detailed Inferentia2 deployment guide including operator installation, DeviceConfig, ServingRuntime, and KServe integration.
- **Performance baselines**: `inferentia_vllm_test_results.md` contains GuideLLM benchmark results for Inferentia2 across multiple instance types and configurations.

### Agent Skill Usage

When using a Cursor AI agent to execute this plan, the agent should leverage the **deploy-on-aws** skill (plugin: `plugin-deploy-on-aws`) for AWS infrastructure tasks including:
- ROSA cluster creation and configuration
- Machine pool management (GPU, Inferentia, worker nodes)
- IAM role and OIDC configuration
- AWS CLI operations (ECR image inspection, resource queries)

The agent should also use the **parallel-web-search** skill for researching current documentation, checking for updated driver versions, and verifying compatibility.

### Credential and Configuration Management

- Before starting, check stored credentials (AWS access keys, OCM token, HuggingFace token, cluster admin passwords).
- If credentials are missing, ask the user to provide them before proceeding.
- Never commit credentials to files. Use `oc create secret` or environment variables.

### NEFF Artifact Preservation (MANDATORY)

All Neuron NEFF (Neuron Executable File Format) compilation artifacts must be preserved on **EBS-backed persistent storage** for reuse. **Ephemeral storage (`/tmp`, `emptyDir`) must NEVER be used for NEFF or model caches.**

- Set `NEURON_COMPILE_CACHE_URL` to a path on the EBS PVC (e.g., `/models/neuron-cache`) for every Inferentia model deployment.
- Set `HF_HOME` to a path on the EBS PVC (e.g., `/models/hf-cache`) so downloaded model weights (~57 GB) persist across pod restarts.
- Use a **dedicated EBS PVC** (≥200Gi, `gp3-csi` StorageClass) that persists across pod restarts and redeployments. This PVC holds both the HuggingFace model cache and the compiled NEFF artifacts.
- When deploying a new model on Inferentia, first check if a cached NEFF exists on the PVC for the same model + `tp_degree` + `max_model_len` + SDK version combination.
- When scaling down Inferentia nodes, do **not** delete the EBS PVCs. The NEFF cache saves **30-45 minutes** of compilation time per model on subsequent startups.
- For disaster recovery, periodically back up NEFF artifacts to S3: `aws s3 sync /models/neuron-cache s3://<bucket>/neuron-cache/`.

### Container Memory Sizing for Neuron Compilation (MANDATORY)

Neuron compilation of large MoE models (e.g., Qwen3-Coder-30B) requires significantly more memory than steady-state inference:

| Phase | Peak RSS | Duration | Notes |
|-------|----------|----------|-------|
| Model weight loading | ~60-70 GB | 5-8 min | 57 GB BF16 weights + runtime buffers |
| Bucket compilation | **~120 GB** | 30-45 min | Compiler workspace for 10 bucket configs |
| NEFF loading to NeuronCores | ~15-20 GB | 5-10 min | Loading compiled artifacts onto hardware |
| Steady-state serving | ~15-20 GB | Ongoing | Model offloaded to NeuronCores |

**Memory limit guidance:**
- **64Gi** → OOMKill during weight loading (exit code 137)
- **128Gi** → OOMKill during bucket compilation (exit code 137)
- **200Gi** → Tested minimum for cold-cache compilation of Qwen3-Coder-30B
- Set `requests: 128Gi, limits: 200Gi` to balance scheduler placement vs. compilation headroom.

---

# Part 1: End-to-End Deployment Plan

## Step 0: Cluster Availability Check

Before creating new infrastructure, verify whether an existing ROSA cluster with the required components is available.

### 0a. Check for existing ROSA cluster

```bash
rosa list clusters
```

If a cluster exists (e.g., `rosa-pca`), verify its status:

```bash
rosa describe cluster --cluster=rosa-pca
```

**Expected**: State `ready`, version 4.21+, region `us-east-2`.

### 0b. Check cluster login and components

```bash
oc whoami
oc get nodes
rosa list machinepools --cluster=rosa-pca
```

Verify the following operators are installed:

```bash
oc get csv -n redhat-ods-operator | grep rhods
oc get csv -n openshift-service-mesh | grep servicemesh
oc get csv -n openshift-devspaces | grep devspaces
oc get crd leaderworkersets.leaderworkerset.x-k8s.io
oc get crd inferenceservices.serving.kserve.io
oc get crd llminferenceservices.serving.kserve.io
```

### 0c. Check machine pools

```bash
rosa list machinepools --cluster=rosa-pca
```

Look for:
- GPU pool (`g6e.2xlarge`) -- may be at 0 replicas
- Inferentia pool (`inf2.24xlarge`) -- may be at 0 replicas
- Worker pools (`m5.xlarge`)

### 0d. Decision tree

```
Cluster exists and is ready?
├── YES
│   ├── All operators installed?
│   │   ├── YES → Skip to Step 4 (machine pools). Scale up GPU/Inferentia pools as needed.
│   │   └── NO → Install missing operators (Step 3), then continue.
│   └── Login works?
│       └── NO → Re-authenticate: rosa login, oc login
└── NO → Ask user for AWS credentials to create a new cluster
    ├── Required from user:
    │   ├── AWS Access Key ID
    │   ├── AWS Secret Access Key
    │   ├── AWS Region (default: us-east-2)
    │   ├── OCM token (from console.redhat.com/openshift/token)
    │   ├── HuggingFace token
    │   └── Desired cluster name
    └── Proceed to Step 1 (Create ROSA HCP Cluster)
```

### 0e. Verify stored credentials

Check that the following are available in the environment or stored configuration:

| Credential | How to Check | Where to Get |
|------------|-------------|--------------|
| AWS CLI configured | `aws sts get-caller-identity` | User provides Access Key + Secret |
| ROSA CLI logged in | `rosa whoami` | `rosa login --token=<OCM_TOKEN>` |
| oc CLI logged in | `oc whoami` | `oc login <API_URL> --username=<user> --password=<pass>` |
| HuggingFace token | `oc get secret hf-token -n llm-d-gpu` | User provides token |

If any credential is missing, **stop and ask the user** before proceeding.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **AWS Account** | With permissions for ROSA, EC2 (g6e, inf2), EBS, ELB, IAM |
| **ROSA CLI** | v1.2+ with OCM token configured |
| **oc CLI** | 4.21+ |
| **Helm** | v3.12+ |
| **HuggingFace Token** | With access to `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` and `Qwen/Qwen3-Coder-30B-A3B-Instruct` |

## Step 1: Create ROSA HCP Cluster

```bash
rosa create cluster \
  --cluster-name=rosa-pca \
  --hosted-cp \
  --region=us-east-2 \
  --version=4.21 \
  --compute-machine-type=m5.xlarge \
  --replicas=2 \
  --machine-cidr=10.0.0.0/16 \
  --service-cidr=172.30.0.0/16 \
  --pod-cidr=10.128.0.0/14
```

**Verification:**

```bash
rosa describe cluster --cluster=rosa-pca
oc get nodes
```

## Step 2: Create IDP and Users

Create an HTPasswd IDP with **three developer test users** and one admin:

```bash
# Create the IDP with the first user
rosa create idp --cluster=rosa-pca --type=htpasswd --name=htpasswd \
  --username=dev-user1 --password=<14+ char password>

# Add additional users to the same IDP
rosa create user --cluster=rosa-pca --username=dev-user2 --password=<14+ char password>
rosa create user --cluster=rosa-pca --username=dev-user3 --password=<14+ char password>

# Grant cluster-admin to the admin user
rosa grant user cluster-admin --cluster=rosa-pca --user=dev-user1
```

**Record all credentials** for the post-deployment access report (Step 14).

**Verification:**

```bash
oc login <API_URL> --username=dev-user1 --password=<password>
oc login <API_URL> --username=dev-user2 --password=<password>
oc login <API_URL> --username=dev-user3 --password=<password>
```

## Step 3: Install Prerequisite Operators

Install in this order (dependencies flow top-down):

| Order | Operator | Source | Namespace |
|-------|----------|--------|-----------|
| 1 | Node Feature Discovery | OperatorHub (Red Hat) | openshift-nfd |
| 2 | Kernel Module Management | OperatorHub (Red Hat) | openshift-kmm |
| 3 | cert-manager Operator | OperatorHub (Red Hat) | cert-manager |
| 4 | LeaderWorkerSet Operator | OperatorHub (Red Hat) | openshift-lws-operator |
| 5 | Red Hat OpenShift AI | OperatorHub (Red Hat) | redhat-ods-operator |
| 6 | Red Hat OpenShift Service Mesh 3 | OperatorHub (Red Hat) | openshift-service-mesh |
| 7 | Red Hat OpenShift Dev Spaces | OperatorHub (Red Hat) | openshift-devspaces |

```bash
# cert-manager (required before LeaderWorkerSet)
oc apply -k "https://github.com/rhoai-rhtap/llm-d-playbook/main/kustomize/cert-manager/operator/overlays/stable"
oc apply -k "https://github.com/rhoai-rhtap/llm-d-playbook/main/kustomize/cert-manager/instance/overlays/default"

# LeaderWorkerSet Operator
oc apply -k "https://github.com/rhoai-rhtap/llm-d-playbook/main/kustomize/lws/operator/overlays/stable"
```

Create LeaderWorkerSetOperator instance:

```bash
oc apply -f - <<EOF
apiVersion: leaderworkersetoperator.openshift.io/v1
kind: LeaderWorkerSetOperator
metadata:
  name: cluster
spec:
  managementState: Managed
EOF
```

**Verification:**

```bash
oc get crd leaderworkersets.leaderworkerset.x-k8s.io
oc get csv -n redhat-ods-operator
oc get csv -n openshift-service-mesh
```

## Step 4: Create Machine Pools

### 4a. NVIDIA GPU Pool

```bash
rosa create machinepool \
  --cluster=rosa-pca \
  --name=gpu-l40s \
  --instance-type=g6e.2xlarge \
  --replicas=2 \
  --labels="nvidia.com/gpu.present=true" \
  --subnet=<private-subnet-id>
```

### 4b. Inferentia2 Pool

```bash
rosa create machinepool \
  --cluster=rosa-pca \
  --name=inf2-24xl \
  --instance-type=inf2.24xlarge \
  --replicas=1 \
  --subnet=<private-subnet-id>
```

**Verification:**

```bash
rosa list machinepools --cluster=rosa-pca
oc get nodes -l nvidia.com/gpu.present=true
oc get nodes -l node.kubernetes.io/instance-type=inf2.24xlarge
```

## Step 5: Install NVIDIA GPU Operator

Install from OperatorHub (certified, `nvidia-gpu-operator` namespace). Create ClusterPolicy:

```bash
oc apply -f - <<EOF
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
  daemonsets: {}
  driver:
    enabled: true
  toolkit:
    enabled: true
  devicePlugin:
    enabled: true
  dcgmExporter:
    enabled: true
  gfd:
    enabled: true
EOF
```

If NFD does not create the vendor PCI label:

```bash
oc label node <gpu-node> feature.node.kubernetes.io/pci-10de.present=true
```

**Verification:**

```bash
oc get node <gpu-node> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
# Expected: 1
```

## Step 6: Install AWS Neuron Operator

Install from OperatorHub (`awslabs-gpu-operator`). Create DeviceConfig:

```bash
oc apply -f - <<'EOF'
apiVersion: neuron.aws.com/v1alpha1
kind: DeviceConfig
metadata:
  name: neuron-device-config
  namespace: openshift-operators
spec:
  neuronDevicePlugin:
    enabled: true
  neuronScheduler:
    enabled: true
  neuronMonitor:
    enabled: true
EOF
```

**Verification:**

```bash
oc get pods -n openshift-operators -l app=neuron
oc get node <inf2-node> -o jsonpath='{.status.allocatable.aws\.amazon\.com/neuroncore}'
# Expected: 12
```

## Step 7: Deploy MutatingAdmissionWebhook (OVN Annotation Preserver)

Required on ROSA HCP before creating any Inferentia workloads. See `private_code_assistant.md` Appendix B for full implementation.

```bash
oc new-project neuron-webhook
# Deploy webhook ConfigMap, Deployment, Service, MutatingWebhookConfiguration
# (see private_code_assistant.md Appendix B for complete YAML)
```

**Verification:**

```bash
oc get mutatingwebhookconfiguration preserve-ovn-pod-networks
oc get pods -n neuron-webhook
```

## Step 8: Configure DataScienceCluster

```bash
oc patch datasciencecluster default-dsc --type='merge' \
  -p '{"spec":{"components":{"kserve":{"rawDeploymentServiceConfig":"Headed"}}}}'
```

## Step 9: Ensure Gateway TLS Secret

```bash
oc get secret data-science-gatewayconfig-tls -n openshift-ingress 2>/dev/null || \
  oc get secret data-science-gateway-service-tls -n openshift-ingress -o json | \
  jq '.metadata.name = "data-science-gatewayconfig-tls" | del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' | \
  oc apply -f -
```

## Step 10: Deploy NVIDIA Model via LLMInferenceService

```bash
oc new-project llm-d-gpu
oc create secret generic hf-token -n llm-d-gpu --from-literal=HF_TOKEN=<your-hf-token>
```

```bash
oc apply -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: qwen3-coder-fp8
  namespace: llm-d-gpu
  annotations:
    opendatahub.io/model-type: generative
    openshift.io/display-name: qwen3-coder-fp8
    security.opendatahub.io/enable-auth: "false"
spec:
  model:
    name: Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8
    uri: hf://Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8
  replicas: 2
  router:
    gateway:
      refs:
      - name: maas-default-gateway
        namespace: openshift-ingress
    route: {}
    scheduler:
      template:
        containers:
        - name: main
          args:
          - --pool-group
          - inference.networking.x-k8s.io
          - --pool-name
          - "{{ ChildName .ObjectMeta.Name `-inference-pool` }}"
          - --pool-namespace
          - "{{ .ObjectMeta.Namespace }}"
          - --zap-encoder
          - json
          - --grpc-port
          - "9002"
          - --grpc-health-port
          - "9003"
          - --secure-serving
          - --model-server-metrics-scheme
          - https
          - --config-text
          - |
            apiVersion: inference.networking.x-k8s.io/v1alpha1
            kind: EndpointPickerConfig
            plugins:
            - type: single-profile-handler
            - type: queue-scorer
            - type: kv-cache-utilization-scorer
            - type: prefix-cache-scorer
            schedulingProfiles:
            - name: default
              plugins:
              - pluginRef: queue-scorer
                weight: 2
              - pluginRef: kv-cache-utilization-scorer
                weight: 2
              - pluginRef: prefix-cache-scorer
                weight: 3
          env:
          - name: TOKENIZER_CACHE_DIR
            value: /tmp/tokenizer-cache
          - name: HF_HOME
            value: /tmp/tokenizer-cache
          - name: TRANSFORMERS_CACHE
            value: /tmp/tokenizer-cache
          - name: XDG_CACHE_HOME
            value: /tmp
          volumeMounts:
          - mountPath: /tmp/tokenizer-cache
            name: tokenizer-cache
          - mountPath: /cachi2
            name: cachi2-cache
        volumes:
        - emptyDir: {}
          name: tokenizer-cache
        - emptyDir: {}
          name: cachi2-cache
  template:
    containers:
    - name: main
      env:
      - name: VLLM_ADDITIONAL_ARGS
        value: "--disable-uvicorn-access-log --max-model-len 32768 --gpu-memory-utilization 0.90 --enable-prefix-caching"
      resources:
        requests:
          cpu: "4"
          memory: "48Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "4"
          memory: "48Gi"
          nvidia.com/gpu: "1"
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
          scheme: HTTPS
        initialDelaySeconds: 300
        periodSeconds: 30
        timeoutSeconds: 30
        failureThreshold: 10
      readinessProbe:
        httpGet:
          path: /health
          port: 8000
          scheme: HTTPS
        initialDelaySeconds: 120
        periodSeconds: 15
        timeoutSeconds: 10
        failureThreshold: 5
    tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
EOF
```

**Verification:**

```bash
oc get pods -n llm-d-gpu -w
GW_URL=$(oc get gateway -n openshift-ingress maas-default-gateway \
  -o jsonpath='{.status.addresses[0].value}')
curl -sk "https://${GW_URL}/llm-d-gpu/qwen3-coder-fp8/v1/models" | python3 -m json.tool
```

## Step 11: Deploy Inferentia Model via KServe InferenceService

### 11a. Create Namespace and PVC

```bash
oc new-project llm-serving
oc create secret generic hf-token -n llm-serving --from-literal=token=<your-hf-token>

oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage
  namespace: llm-serving
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 200Gi
  storageClassName: gp3-csi
EOF
```

### 11b. Download Model to PVC

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: model-downloader
  namespace: llm-serving
spec:
  nodeSelector:
    node.kubernetes.io/instance-type: inf2.24xlarge
  restartPolicy: Never
  containers:
  - name: downloader
    image: python:3.11-slim
    command: ["/bin/bash", "-c"]
    args:
    - |
      pip install huggingface_hub && \
      huggingface-cli download Qwen/Qwen3-Coder-30B-A3B-Instruct \
        --local-dir /models/qwen3-coder-30b \
        --token $HF_TOKEN
    env:
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:
          name: hf-token
          key: token
    volumeMounts:
    - name: models
      mountPath: /models
  volumes:
  - name: models
    persistentVolumeClaim:
      claimName: model-storage
EOF
```

### 11c. Create ServingRuntime

```bash
oc apply -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-neuron-runtime
  namespace: llm-serving
  annotations:
    openshift.io/display-name: "vLLM Neuron Runtime"
spec:
  supportedModelFormats:
  - name: vllm-neuron
    autoSelect: true
  multiModel: false
  containers:
  - name: kserve-container
    image: public.ecr.aws/neuron/pytorch-inference-vllm-neuronx:0.13.0-neuronx-py312-sdk2.28.0-ubuntu24.04
    command: ["python3", "-m", "vllm.entrypoints.openai.api_server"]
    ports:
    - containerPort: 8000
      name: http
      protocol: TCP
EOF
```

### 11d. Deploy InferenceService with PVC NEFF Cache and Right-Sized Memory

> **CRITICAL REQUIREMENTS — Inferentia Model Deployments:**
>
> 1. **EBS-backed PVC for ALL caches:** Both `NEURON_COMPILE_CACHE_URL` and `HF_HOME` **must** point to EBS PVC paths, never ephemeral storage (`/tmp`, `emptyDir`). NEFF artifacts are 20-40 GB and take 30-45 minutes to regenerate. HF model cache is ~57 GB.
> 2. **Memory limits for Neuron compilation:** Set `requests: 128Gi, limits: 200Gi`. Compilation peaks at ~120 GB RSS. See "Container Memory Sizing" section above.
> 3. **PVC sizing:** ≥200Gi (`gp3-csi`) for HF cache + NEFF artifacts + headroom.

**SELinux**: When multiple pods share a ReadWriteOnce PVC, all pods must set `seLinuxOptions.level: "s0:c0,c0"` for matching MCS labels.

```bash
oc apply -f - <<'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen3-coder-neuron
  namespace: llm-serving
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    opendatahub.io/model-type: generative
    openshift.io/display-name: "Qwen3-Coder-30B (Inferentia2, TP=8)"
    security.opendatahub.io/enable-auth: "false"
spec:
  predictor:
    nodeSelector:
      node.kubernetes.io/instance-type: inf2.24xlarge
    schedulerName: neuron-scheduler
    securityContext:
      fsGroup: 0
      runAsUser: 0
      seLinuxOptions:
        level: "s0:c0,c0"
    terminationGracePeriodSeconds: 60
    volumes:
    - name: models
      persistentVolumeClaim:
        claimName: model-storage
    - name: dshm
      emptyDir:
        medium: Memory
        sizeLimit: 16Gi
    initContainers:
    - name: fix-perms
      image: registry.access.redhat.com/ubi9/ubi-minimal:latest
      command: ["sh", "-c", "chmod -R 777 /models/ && echo perms fixed"]
      securityContext:
        runAsUser: 0
      volumeMounts:
      - name: models
        mountPath: /models
    model:
      modelFormat:
        name: vllm-neuron
      runtime: vllm-neuron-runtime
      command:
      - /bin/bash
      - -c
      - |
        echo "Waiting for model files to be accessible..."
        for i in $(seq 1 60); do
          if python3 -c "import os; os.stat('/models/qwen3-coder-30b/config.json')" 2>/dev/null; then
            echo "Model directory accessible after ${i}s"
            break
          fi
          sleep 1
        done
        exec python3 -m vllm.entrypoints.openai.api_server \
          --model /models/qwen3-coder-30b \
          --served-model-name qwen3-coder-neuron \
          --tensor-parallel-size 8 \
          --max-model-len 8192 \
          --max-num-seqs 16 \
          --block-size 32 \
          --no-enable-prefix-caching \
          --num-gpu-blocks-override 32 \
          --additional-config '{"tp_degree":8,"moe_tp_degree":1,"moe_ep_degree":8,"batch_size":16,"seq_len":8192,"context_encoding_buckets":[[16,128],[16,512],[16,1024],[16,2048],[16,4096],[16,8192]],"token_generation_buckets":[[16,128],[16,512],[16,1024],[16,2048],[16,4096],[16,8192]],"on_device_generation":{"do_sample":true},"enable_fused_rmsnorm_quantization":true,"enable_fused_experts_quantization":true,"enable_nki_quantized_kernels":true}' \
          --port 8000 --host 0.0.0.0
      env:
      - name: NEURON_RT_VISIBLE_CORES
        value: "0-7"
      - name: NEURON_COMPILE_CACHE_URL
        # CRITICAL: Must be on EBS PVC. First compile: 30-45 min. Warm cache: ~10s.
        value: "/models/neuron-cache"
      - name: VLLM_ENGINE_ITERATION_TIMEOUT_S
        value: "7200"
      - name: VLLM_RPC_TIMEOUT
        value: "7200"
      - name: VLLM_NEURON_FRAMEWORK
        value: "neuronx-distributed-inference"
      - name: HF_HOME
        # CRITICAL: Must be on EBS PVC. Model download is ~57 GB.
        value: "/models/hf-cache"
      ports:
      - containerPort: 8000
        name: http
        protocol: TCP
      securityContext:
        capabilities:
          add: [IPC_LOCK, SYS_ADMIN]
      resources:
        requests:
          cpu: "8"
          memory: 128Gi
          aws.amazon.com/neuroncore: "8"
        limits:
          cpu: "16"
          # Neuron compilation peaks at ~120 GB RSS. 200Gi is the tested minimum.
          memory: 200Gi
          aws.amazon.com/neuroncore: "8"
      volumeMounts:
      - name: models
        mountPath: /models
      - name: dshm
        mountPath: /dev/shm
      readinessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 10
        periodSeconds: 30
        timeoutSeconds: 5
        failureThreshold: 60
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 3600
        periodSeconds: 60
        timeoutSeconds: 10
        failureThreshold: 10
EOF
```

### 11e. Verify Inferentia Deployment

```bash
oc get inferenceservice qwen3-coder-neuron -n llm-serving -w
# Wait for READY=True

INF_URL=$(oc get inferenceservice qwen3-coder-neuron -n llm-serving \
  -o jsonpath='{.status.url}')
curl -s "${INF_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder-neuron","messages":[{"role":"user","content":"Write a Python hello world"}],"max_tokens":100}' | python3 -m json.tool
```

### 11f. Verify NEFF Cache Persistence

After the model serves its first request (compilation complete), verify NEFF artifacts are on the PVC:

```bash
INF_POD=$(oc get pods -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron -o name | head -1)

# Check NEFF cache directory exists and has content
oc exec -n llm-serving $INF_POD -- du -sh /models/neuron-cache
# Expected: 20-40 GB of compiled NEFF artifacts

# List the cache structure
oc exec -n llm-serving $INF_POD -- ls /models/neuron-cache/ | head -10
```

The NEFF cache is keyed by model + `tp_degree` + `max_model_len` + SDK version. As long as the PVC is preserved, subsequent pod restarts skip compilation entirely (~10s startup vs **30-45 min** first compile).

**Do NOT delete the PVC when scaling down Inferentia nodes.** The EBS volume persists independently of the node and will be reattached on next scale-up.

For disaster recovery, back up NEFF artifacts to S3:

```bash
# Run from a pod with S3 access or use a one-off job
oc exec -n llm-serving $INF_POD -- \
  python3 -c "import subprocess; subprocess.run(['aws','s3','sync','/models/neuron-cache','s3://<BUCKET>/neuron-cache/'])"
```

## Step 12: Deploy OpenShift Dev Spaces with AI Extensions

### 12a. Install Dev Spaces Operator and CheCluster

```bash
oc apply -f - <<EOF
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  name: devspaces
  namespace: openshift-devspaces
spec:
  components:
    cheServer:
      debug: false
    dashboard: {}
    devWorkspace: {}
    devfileRegistry: {}
    pluginRegistry: {}
  networking: {}
EOF
```

Wait for the Dev Spaces dashboard to become available:

```bash
oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.cheURL}'
```

### 12b. Create Extension Configuration ConfigMaps (Red Hat Recommended)

Red Hat OpenShift Dev Spaces 3.27 distributes IDE configuration via **ConfigMaps in the `openshift-devspaces` namespace** with specific labels. This is the [documented approach](https://docs.redhat.com/en/documentation/red_hat_openshift_dev_spaces/3.27/html-single/administration_guide/index) for cluster-wide extension configuration.

**Key labels required on all ConfigMaps:**
- `app.kubernetes.io/component: workspaces-config`
- `app.kubernetes.io/part-of: che.eclipse.org`
- `controller.devfile.io/watch-configmap: "true"`

ConfigMaps with `controller.devfile.io/watch-configmap: "true"` are auto-replicated to user workspaces. **Changing them restarts running workspaces.**

The model endpoint URL for extensions:

```
# Internal (pod-to-pod, used by extensions inside Dev Spaces workspaces):
https://qwen3-coder-fp8-kserve-workload-svc.<MODEL_NAMESPACE>.svc.cluster.local:8000/v1

# External (via Service Mesh gateway, for external clients):
https://<GW_URL>/<MODEL_NAMESPACE>/qwen3-coder-fp8/v1/chat/completions
```

Replace `<MODEL_NAMESPACE>` with the namespace where models are deployed (e.g., `llm-d-multi-gpu` for heterogeneous setup).

**Continue extension config** (`config.json` format, injected via ConfigMap):

```json
{
  "models": [
    {
      "title": "Qwen3-Coder (Private - Heterogeneous llm-d)",
      "provider": "openai",
      "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
      "apiBase": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
      "apiKey": "EMPTY",
      "requestOptions": {
        "verifySsl": false
      }
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen3-Coder Autocomplete (Heterogeneous llm-d)",
    "provider": "openai",
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
    "apiBase": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
    "apiKey": "EMPTY",
    "requestOptions": {
      "verifySsl": false
    }
  }
}
```

**Cline extension config** (OpenAI-compatible provider settings):

```json
{
  "apiProvider": "openai-compatible",
  "openAiCompatibleApiBaseUrl": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
  "openAiCompatibleModelId": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
  "openAiCompatibleApiKey": "EMPTY"
}
```

### 12c. Apply Cluster-Wide Extension ConfigMaps

Apply the three ConfigMaps in `openshift-devspaces`. These replicate to all user workspaces automatically:

```bash
# 1. Extension recommendations (installs Continue + Cline in all workspaces)
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vscode-extensions-config
  namespace: openshift-devspaces
  labels:
    app.kubernetes.io/component: workspaces-config
    app.kubernetes.io/part-of: che.eclipse.org
    controller.devfile.io/watch-configmap: "true"
data:
  .vscode-extensions.json: |
    {
      "recommendations": [
        "Continue.continue",
        "saoudrizwan.claude-dev"
      ]
    }
EOF

# 2. Continue extension config (points to llm-d heterogeneous endpoint)
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: continue-config
  namespace: openshift-devspaces
  labels:
    app.kubernetes.io/component: workspaces-config
    app.kubernetes.io/part-of: che.eclipse.org
    controller.devfile.io/watch-configmap: "true"
data:
  continue-config.json: |
    {
      "models": [
        {
          "title": "Qwen3-Coder (Private - Heterogeneous llm-d)",
          "provider": "openai",
          "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
          "apiBase": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
          "apiKey": "EMPTY",
          "requestOptions": {
            "verifySsl": false
          }
        }
      ],
      "tabAutocompleteModel": {
        "title": "Qwen3-Coder Autocomplete (Heterogeneous llm-d)",
        "provider": "openai",
        "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
        "apiBase": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
        "apiKey": "EMPTY",
        "requestOptions": {
          "verifySsl": false
        }
      }
    }
EOF

# 3. Cline extension config (OpenAI-compatible provider)
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cline-settings-config
  namespace: openshift-devspaces
  labels:
    app.kubernetes.io/component: workspaces-config
    app.kubernetes.io/part-of: che.eclipse.org
    controller.devfile.io/watch-configmap: "true"
data:
  .cline-settings.json: |
    {
      "apiProvider": "openai-compatible",
      "openAiCompatibleApiBaseUrl": "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1",
      "openAiCompatibleModelId": "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8",
      "openAiCompatibleApiKey": "EMPTY"
    }
EOF
```

### 12d. Create DevWorkspace for Each User

For each of the three users (`dev-user1`, `dev-user2`, `dev-user3`), create a DevWorkspace. The extension ConfigMaps from step 12c are automatically available in all workspaces:

```bash
for USER in dev-user1 dev-user2 dev-user3; do
  NS="${USER}-devspaces"

  oc create namespace $NS 2>/dev/null || true
  oc label namespace $NS app.kubernetes.io/part-of=che.eclipse.org --overwrite

  oc apply -n $NS -f - <<DWEOF
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: code-assistant-workspace
  namespace: $NS
  annotations:
    che.eclipse.org/devfile-source: |
      custom:
        type: inline
spec:
  started: true
  contributions:
  - name: ide
    kubernetes:
      name: che-code
  template:
    components:
    - name: dev-tools
      container:
        image: registry.redhat.io/devspaces/udi-rhel8:latest
        memoryLimit: 4Gi
        cpuLimit: "2"
        env:
        - name: VLLM_ENDPOINT
          value: "https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1"
        - name: VLLM_MODEL_ID
          value: "Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8"
DWEOF

  echo "Created workspace for $USER in namespace $NS"
done
```

### 12e. Verify Extension Configuration

For each user, log in as that user and:

1. Open the Dev Spaces dashboard at `https://<DEVSPACES_URL>/`
2. Open the `code-assistant-workspace`
3. Verify **Continue** extension appears in the sidebar and lists the Qwen3-Coder model
4. Verify **Cline** extension is installed — select "OpenAI Compatible" provider and confirm the endpoint URL matches
5. Send a test prompt via Continue chat (e.g., "Write a Python hello world")
6. Verify the response comes from the private model (check model name in response)

**Endpoint change procedure:** When the model-serving namespace changes, update `apiBase`/`openAiCompatibleApiBaseUrl` in the three ConfigMaps in `openshift-devspaces` (step 12c). Running workspaces restart automatically.

## Step 13: Verify End-to-End

| Check | Command / Action | Expected |
|-------|-----------------|----------|
| NVIDIA model serving | `curl -sk https://<GW_URL>/llm-d-gpu/qwen3-coder-fp8/v1/models` | Model info returned |
| Inferentia model serving | `curl -s <INF_URL>/v1/models` | Model info returned |
| llm-d EPP routing | Send 10 requests, check pod metrics distribution | Weighted across replicas |
| Dev Spaces `dev-user1` | Login, open workspace, test Continue chat | Model responds via private endpoint |
| Dev Spaces `dev-user2` | Login, open workspace, test Cline code gen | Model responds via private endpoint |
| Dev Spaces `dev-user3` | Login, open workspace, test both extensions | Both extensions functional |
| OpenShift AI console | Navigate to Model Serving | Both models visible |
| Extension endpoint | Check Continue/Cline target URL in each workspace | Points to internal `svc.cluster.local` endpoint |

## Step 14: Consolidated Deployment Access Report

After all components are deployed and verified, compile and share the following access information:

### Cluster Access

| Resource | URL / Command |
|----------|--------------|
| **OpenShift Console** | `oc whoami --show-console` |
| **OpenShift API** | `oc whoami --show-server` |
| **OpenShift AI Dashboard** | `https://<CONSOLE_URL>/ai` (or via OpenShift AI route in `redhat-ods-applications`) |
| **Dev Spaces Dashboard** | `oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.cheURL}'` |

### User Credentials

| User | Role | Password | Purpose |
|------|------|----------|---------|
| `dev-user1` | cluster-admin | `<recorded>` | Admin + developer testing |
| `dev-user2` | developer | `<recorded>` | Developer testing |
| `dev-user3` | developer | `<recorded>` | Developer testing |

### Model Endpoints

| Endpoint | URL | Auth |
|----------|-----|------|
| **llm-d Gateway (external)** | `https://<GW_URL>/llm-d-multi-gpu/qwen3-coder-fp8/v1` | None (auth disabled) |
| **llm-d Workload Svc (internal)** | `https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc.cluster.local:8000/v1` | None |
| **Continue/Cline extensions** | Use the internal workload svc URL above as `apiBase` | `apiKey: "EMPTY"` |

### Component Status Summary

```bash
# Generate this report after deployment:
echo "=== Cluster ===" && oc get clusterversion
echo "=== Nodes ===" && oc get nodes -o wide
echo "=== Machine Pools ===" && rosa list machinepools --cluster=rosa-pca
echo "=== Operators ===" && oc get csv -A | grep -E "(rhods|servicemesh|devspaces|gpu|neuron|lws|cert-manager)"
echo "=== Model Pods ===" && oc get pods -n llm-d-gpu -o wide && oc get pods -n llm-serving -o wide
echo "=== InferenceServices ===" && oc get inferenceservice -A
echo "=== LLMInferenceServices ===" && oc get llminferenceservice -A
echo "=== Gateway ===" && oc get gateway -n openshift-ingress
echo "=== Dev Spaces ===" && oc get devworkspace -A
```

Record all output in a message to the user with the deployment summary.

---

# Part 2: Test Phases

## Phase A: Per-Accelerator Throughput Consolidation

### Objective

Consolidate per-accelerator maximum throughput data for capacity planning. The private code assistant deployment serves multiple developers concurrently, so peak aggregate throughput per accelerator unit is the key metric.

### Data Sources

| Accelerator | Source File | Run |
|-------------|------------|-----|
| NVIDIA L40S (1x g6e.2xlarge) | `private_code_assistant.md` lines 263-321 | Concurrent load test (2x GPU via llm-d) |
| Inferentia2 (inf2.24xlarge, TP=8) | `inferentia_vllm_test_results.md` Run 1 | GuideLLM sweep |
| Inferentia2 (inf2.48xlarge, TP=16) | `inferentia_vllm_test_results.md` Run 2 | GuideLLM sweep |

### Per-Accelerator Summary to Capture

| Metric | L40S (1x GPU) | inf2.24xlarge (8 cores) | inf2.48xlarge (16 cores) |
|--------|---------------|-------------------------|--------------------------|
| **Single-user TTFT** | 265-284 ms | 495-523 ms | 609-632 ms |
| **Single-user ITL** | 10.3-10.4 ms | 40.9-41.0 ms | 39.3-39.7 ms |
| **Single-user output tok/s** | 80.7-92.0 | 22.7-24.2 | 23.2-25.1 |
| **Max aggregate tok/s** | ~241 (8 concurrent, 1 GPU) | 154.2 (8.5 concurrent) | 278.1 (32 concurrent) |
| **Instance cost** | $1.12/hr | $6.49/hr | $12.98/hr |
| **Cost per 1M output tokens** | ~$1.29 (at 8 concurrent, 1 GPU) | ~$11.69 (at peak) | ~$12.97 (at peak) |
| **Quantization** | FP8 | BF16 | BF16 |
| **Tensor Parallelism** | 1 | 8 | 16 |
| **Prefix caching** | Enabled | Disabled (MoE) | Disabled (MoE) |
| **Max model length** | 32,768 | 8,192 | 16,384 |

> **Note on per-GPU throughput**: The NVIDIA benchmark used 2x L40S GPUs via llm-d. At 16 concurrent, aggregate was 482.2 tok/s across 2 GPUs. Per-GPU max is estimated at ~241 tok/s. At 8 concurrent (near-linear scaling range), aggregate was 294.8 tok/s, so per-GPU ~147 tok/s.

### Action

- [ ] Add this summary table to `private_code_assistant.md` after the existing comparison table
- [ ] Include developer capacity estimates (tokens per developer-hour at various concurrency levels)

---

## Phase B: Neuron DRA Driver Retest on Inferentia2

### Background

The Neuron DRA driver v1.0.0 was tested on April 6, 2026 and failed on `inf2.24xlarge` with two issues:
1. DaemonSet `nodeAffinity` excluded `inf2.*` instance types (`DESIRED=0`)
2. Driver binary rejected `inf2.24xlarge` (`unsupported instance type` in `mappings.go`)

New research shows the Helm chart `values.yaml` at `main` branch (v1.5.0) **does include** inf2 instance types in the affinity list. This may mean: (a) the chart was updated after our test, or (b) we tested with an older chart version.

### Test Steps

**Step B.1: Check for updated DRA driver image**

```bash
aws ecr describe-images \
  --repository-name neuron-dra-driver \
  --registry-id 790709498068 \
  --region us-east-1 \
  --query 'imageDetails[*].[imageTags,imagePushedAt]' \
  --output table
```

Look for image tags newer than `1.0.0` (our tested version).

**Step B.2: Pull latest Helm chart and inspect values**

```bash
helm repo add neuron-helm-charts https://aws-neuron.github.io/neuron-helm-charts
helm repo update
helm show values neuron-helm-charts/neuron-helm-chart --version 1.5.0 | grep -A 30 "draDriver"
```

Verify the `affinity.nodeAffinity` section includes `inf2.xlarge`, `inf2.8xlarge`, `inf2.24xlarge`, `inf2.48xlarge`.

**Step B.3: Scale up Inferentia pool**

```bash
rosa edit machinepool --cluster=rosa-pca inf2-24xl --replicas=1
oc get nodes -l node.kubernetes.io/instance-type=inf2.24xlarge -w
```

**Step B.4: Uninstall legacy Neuron Operator components (if running)**

The DRA driver replaces the legacy device plugin and neuron-scheduler:

```bash
# Remove existing DeviceConfig
oc delete deviceconfig neuron-device-config -n openshift-operators 2>/dev/null
```

**Step B.5: Install DRA driver via Helm**

```bash
helm install neuron-helm-chart neuron-helm-charts/neuron-helm-chart \
  --namespace neuron-dra-system --create-namespace \
  --set draDriver.enabled=true \
  --set devicePlugin.enabled=false \
  --set neuronScheduler.enabled=false \
  --set neuronMonitor.enabled=false
```

**Step B.6: Verify DaemonSet scheduling**

```bash
oc get daemonset -n neuron-dra-system
# Expected: DESIRED >= 1 on Inferentia node
```

If `DESIRED=0`, patch the DaemonSet nodeAffinity to add inf2 types:

```bash
oc get daemonset -n neuron-dra-system -o yaml | \
  grep -A 20 "nodeAffinity"
```

**Step B.7: Check driver pod logs**

```bash
oc logs -n neuron-dra-system -l app=neuron-dra-driver --tail=50
```

Look for: `unsupported instance type: inf2.24xlarge` (binary-level rejection).

### Decision Tree

```
DRA Driver Retest
├── DaemonSet DESIRED > 0?
│   ├── YES → Check driver pod logs
│   │   ├── "unsupported instance type" error?
│   │   │   ├── YES → Binary still blocks inf2. Document. Revert to legacy stack.
│   │   │   └── NO → Driver initialized! Continue to Step B.8
│   │   └── Other error? → Document and investigate
│   └── NO → Helm chart affinity still excludes inf2
│       └── Patch affinity manually, retry from Step B.6
└── Step B.8: Test ResourceClaim allocation
    ├── Create ResourceClaimTemplate for 8 NeuronCores
    ├── Create test pod with resourceClaims (default-scheduler, no neuron-scheduler)
    ├── Pod starts with network? → DRA eliminates the OVN annotation race
    └── Document results
```

**Step B.8: Test ResourceClaim (if driver initializes)**

```bash
oc apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: inferentia-8-cores
  namespace: llm-serving
spec:
  spec:
    devices:
      requests:
      - name: neurons
        exactly:
          deviceClassName: neuron.aws.com
          allocationMode: ExactCount
          count: 8
---
apiVersion: v1
kind: Pod
metadata:
  name: dra-test
  namespace: llm-serving
spec:
  containers:
  - name: test
    image: registry.access.redhat.com/ubi9/ubi-minimal:latest
    command: ["sleep", "300"]
    resources:
      claims:
      - name: neurons
  resourceClaims:
  - name: neurons
    resourceClaimTemplateName: inferentia-8-cores
EOF
```

**Verification:**

```bash
oc get pod dra-test -n llm-serving -o wide
# Expected: Running with pod IP (OVN annotation preserved, no neuron-scheduler needed)
```

### Rollback if DRA Fails

```bash
helm uninstall neuron-helm-chart -n neuron-dra-system
oc delete namespace neuron-dra-system
# Reinstall legacy Neuron Operator via OperatorHub
# Recreate DeviceConfig
```

### Where Changes Are Required in the DRA Driver

| Component | Location | What Needs to Change | User-Configurable? |
|-----------|----------|---------------------|-------------------|
| **DaemonSet nodeAffinity** | Helm chart `values.yaml` → `draDriver.affinity.nodeAffinity` | Add `inf2.*` instance types to the `matchExpressions` values list | **Yes** -- via Helm values override or post-install patch |
| **Driver binary instance mapping** | `mappings.go` inside `neuron-dra-driver` container image | Add inf2 instance types to the device/core count mapping | **No** -- compiled into binary. Requires AWS to rebuild the image. |
| **DeviceClassName** | ResourceClaimTemplate | Use `neuron.aws.com` (same for all Neuron device types) | Yes |

---

## Phase C: Heterogeneous llm-d Routing -- HTTPS Solution

### Problem

The llm-d EPP uses `--model-server-metrics-scheme https` globally. NVIDIA pods serve HTTPS (KServe auto-TLS). Inferentia pods serve HTTP. The EPP cannot scrape metrics from HTTP endpoints when configured for HTTPS.

### Solution: vLLM Native TLS

vLLM supports HTTPS natively via `--ssl-certfile` and `--ssl-keyfile` command-line flags. This eliminates the need for TLS proxy pods.

### Implementation Steps

**Step C.1: Generate TLS certificate using OpenShift Service CA**

Create a Service with the `serving-cert-secret-name` annotation. OpenShift will auto-generate a TLS secret:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: qwen3-coder-neuron-tls
  namespace: llm-serving
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: inferentia-serving-cert
spec:
  selector:
    serving.kserve.io/inferenceservice: qwen3-coder-neuron
  ports:
  - port: 8000
    targetPort: 8000
    protocol: TCP
EOF
```

Wait for the secret to be generated:

```bash
oc get secret inferentia-serving-cert -n llm-serving
```

**Step C.2: Update InferenceService to mount TLS cert and enable HTTPS**

Add the TLS secret volume and `--ssl-certfile`/`--ssl-keyfile` flags to the vLLM command:

```yaml
# Add to spec.predictor.volumes:
- name: tls-certs
  secret:
    secretName: inferentia-serving-cert

# Add to spec.predictor.model.volumeMounts:
- name: tls-certs
  mountPath: /tls
  readOnly: true

# Modify the vLLM command to add:
  --ssl-certfile /tls/tls.crt --ssl-keyfile /tls/tls.key
```

**Step C.3: Update probes to HTTPS**

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
    scheme: HTTPS     # Changed from implicit HTTP
livenessProbe:
  httpGet:
    path: /health
    port: 8000
    scheme: HTTPS     # Changed from implicit HTTP
```

**Step C.4: Verify HTTPS serving**

```bash
INF_POD=$(oc get pods -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron -o name | head -1)
oc exec -n llm-serving $INF_POD -- curl -sk https://localhost:8000/v1/models
```

**Step C.5: Verify EPP can scrape metrics**

```bash
oc exec -n llm-serving $INF_POD -- curl -sk https://localhost:8000/metrics | head -5
```

### Alternative Approaches (Documented for Reference)

| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| **vLLM native `--ssl-certfile`** | No proxy, simplest, vLLM auto-reloads certs | Requires cert generation | **Recommended** |
| **OpenShift Service CA** | Auto-provisioned, auto-rotated | Coupled to OpenShift | Use with vLLM native TLS |
| **Sidecar envoy proxy** | Decouples TLS from vLLM | Extra container, resource overhead | Only if vLLM TLS has issues |
| **EPP `--model-server-metrics-scheme http`** | No TLS needed at all | Weakens pod-to-pod security | Not recommended for production |

---

## Phase D: Same-Namespace Heterogeneous Deployment (VERIFIED — Default Method)

**Status: VERIFIED** (April 8, 2026) — Native same-namespace heterogeneous llm-d routing with 0 errors in GuideLLM sweep. This is the **default method** for heterogeneous GPU model deployments.

### Architecture (Verified)

```
Client → Gateway → EPP → ┬─ NVIDIA Pod 1 (g6e, FP8, HTTPS:8000)       ← llm-d-multi-gpu
                          ├─ NVIDIA Pod 2 (g6e, FP8, HTTPS:8000)       ← llm-d-multi-gpu
                          └─ Inferentia Pod (inf2, BF16, HTTPS:8000)    ← llm-d-multi-gpu
```

All pods in same namespace. EPP auto-discovers via InferencePool label selector. No proxy bridge required.

### Prerequisites

- Phase C (HTTPS on Inferentia) complete
- NVIDIA machine pool scaled to ≥2 nodes (`g6e.2xlarge`)
- Inferentia machine pool scaled to ≥1 node (`inf2.24xlarge`)
- Neuron-scheduler and OVN annotation webhook deployed

### Step D.1: Create target namespace

```bash
oc new-project llm-d-multi-gpu --display-name="Multi-GPU Heterogeneous LLM Serving"
oc label namespace llm-d-multi-gpu opendatahub.io/dashboard=true modelmesh-enabled=false
oc adm policy add-scc-to-user anyuid -z default -n llm-d-multi-gpu
oc adm policy add-scc-to-user privileged -z default -n llm-d-multi-gpu
oc create secret generic hf-token -n llm-d-multi-gpu \
  --from-literal=HF_TOKEN=$(oc get secret hf-token -n llm-d-gpu -o jsonpath='{.data.HF_TOKEN}' | base64 -d)
```

### Step D.2: Deploy NVIDIA model via LLMInferenceService

Deploy the NVIDIA model first — this creates the `InferencePool`, EPP router, and TLS secrets that the Inferentia deployment will reuse:

```bash
oc apply -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: qwen3-coder-fp8
  namespace: llm-d-multi-gpu
  annotations:
    security.opendatahub.io/enable-auth: "false"
spec:
  model:
    name: Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8
    uri: hf://Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8
  replicas: 2
  template:
    containers:
    - name: main
      env:
      - name: VLLM_ADDITIONAL_ARGS
        value: "--disable-uvicorn-access-log --max-model-len 32768 --gpu-memory-utilization 0.90 --enable-prefix-caching"
      resources:
        requests:
          cpu: "2"
          memory: "24Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "4"
          memory: "48Gi"
          nvidia.com/gpu: "1"
    nodeSelector:
      node.kubernetes.io/instance-type: g6e.2xlarge
EOF
```

Wait for NVIDIA pods to become `1/1 Running` and the router-scheduler to be ready.

### Step D.3: Create Inferentia EBS PVC

> **CRITICAL: EBS PVC is MANDATORY. See "NEFF Artifact Preservation" and "Container Memory Sizing" sections above.**

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: inferentia-model-cache
  namespace: llm-d-multi-gpu
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 200Gi
  storageClassName: gp3-csi
EOF
```

### Step D.4: Deploy Inferentia model as Deployment with InferencePool labels

The Inferentia model is deployed as a standard Kubernetes Deployment (not `LLMInferenceService` or `InferenceService`) with labels matching the NVIDIA `InferencePool` selector. Key requirements:

- Same `--served-model-name` as NVIDIA (`Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8`)
- Same TLS secret (reuse `qwen3-coder-fp8-kserve-self-signed-certs` from Step D.2)
- InferencePool labels: `app.kubernetes.io/name`, `app.kubernetes.io/part-of`, `kserve.io/component`, `llm-d.ai/role`
- `nodeSelector` for `inf2.24xlarge` + `schedulerName: neuron-scheduler`
- Memory limits ≥200Gi for Neuron compilation
- `NEURON_COMPILE_CACHE_URL` and `HF_HOME` on EBS PVC

```bash
oc apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen3-coder-inferentia
  namespace: llm-d-multi-gpu
  labels:
    app.kubernetes.io/name: qwen3-coder-fp8
    app.kubernetes.io/part-of: llminferenceservice
    app.kubernetes.io/component: llminferenceservice-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qwen3-coder-inferentia
  template:
    metadata:
      labels:
        app: qwen3-coder-inferentia
        app.kubernetes.io/name: qwen3-coder-fp8
        app.kubernetes.io/part-of: llminferenceservice
        app.kubernetes.io/component: llminferenceservice-workload
        kserve.io/component: workload
        llm-d.ai/role: both
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: inf2.24xlarge
      schedulerName: neuron-scheduler
      securityContext:
        fsGroup: 0
        runAsUser: 0
        seLinuxOptions:
          level: "s0:c0,c0"
      terminationGracePeriodSeconds: 60
      containers:
      - name: kserve-container
        image: public.ecr.aws/neuron/pytorch-inference-vllm-neuronx:0.13.0-neuronx-py312-sdk2.28.0-ubuntu24.04
        command:
        - /bin/bash
        - -c
        - |
          exec python3 -m vllm.entrypoints.openai.api_server \
            --model Qwen/Qwen3-Coder-30B-A3B-Instruct \
            --served-model-name Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8 \
            --tensor-parallel-size 8 \
            --max-model-len 8192 \
            --max-num-seqs 16 \
            --block-size 32 \
            --no-enable-prefix-caching \
            --num-gpu-blocks-override 32 \
            --ssl-certfile /etc/certs/tls.crt \
            --ssl-keyfile /etc/certs/tls.key \
            --additional-config '{"tp_degree":8,"moe_tp_degree":1,"moe_ep_degree":8,"batch_size":16,"seq_len":8192,"context_encoding_buckets":[[16,128],[16,512],[16,1024],[16,2048],[16,4096],[16,8192]],"token_generation_buckets":[[16,128],[16,512],[16,1024],[16,2048],[16,4096],[16,8192]],"on_device_generation":{"do_sample":true},"enable_fused_rmsnorm_quantization":true,"enable_fused_experts_quantization":true,"enable_nki_quantized_kernels":true}' \
            --port 8000 --host 0.0.0.0
        env:
        - name: NEURON_RT_VISIBLE_CORES
          value: "0-7"
        - name: NEURON_COMPILE_CACHE_URL
          value: "/cache/neuron-cache"
        - name: VLLM_ENGINE_ITERATION_TIMEOUT_S
          value: "7200"
        - name: VLLM_RPC_TIMEOUT
          value: "7200"
        - name: VLLM_NEURON_FRAMEWORK
          value: neuronx-distributed-inference
        - name: HF_HOME
          value: "/cache/hf-cache"
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: HF_TOKEN
        ports:
        - containerPort: 8000
          name: https
          protocol: TCP
        resources:
          requests:
            aws.amazon.com/neuroncore: "8"
            cpu: "8"
            memory: "128Gi"
          limits:
            aws.amazon.com/neuroncore: "8"
            cpu: "16"
            memory: "200Gi"
        securityContext:
          capabilities:
            add: [IPC_LOCK, SYS_ADMIN]
        volumeMounts:
        - name: cache-storage
          mountPath: /cache
        - name: dshm
          mountPath: /dev/shm
        - name: tls-certs
          mountPath: /etc/certs
          readOnly: true
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
            scheme: HTTPS
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 120
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
            scheme: HTTPS
          initialDelaySeconds: 3600
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 10
      volumes:
      - name: cache-storage
        persistentVolumeClaim:
          claimName: inferentia-model-cache
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 16Gi
      - name: tls-certs
        secret:
          secretName: qwen3-coder-fp8-kserve-self-signed-certs
EOF
```

### Step D.5: Update Dev Spaces extension ConfigMaps

Update the ConfigMaps in `openshift-devspaces` to point to the new namespace (see Step 12c above). Replace the model namespace in `apiBase`/`openAiCompatibleApiBaseUrl` with `llm-d-multi-gpu`.

### Step D.6: Verify heterogeneous routing

```bash
# Check EPP discovered all 3 pods
oc logs deployment/qwen3-coder-fp8-kserve-router-scheduler -n llm-d-multi-gpu | grep "Starting refresher"

# Send test requests through llm-d
for i in $(seq 1 10); do
  oc exec deployment/qwen3-coder-fp8-kserve-router-scheduler -n llm-d-multi-gpu -- \
    curl -sk https://qwen3-coder-fp8-kserve-workload-svc.llm-d-multi-gpu.svc:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8","messages":[{"role":"user","content":"Say hello"}],"max_tokens":5}' &
done
wait

# Verify Inferentia got some requests
INF_POD=$(oc get pods -n llm-d-multi-gpu -l app=qwen3-coder-inferentia -o name | head -1)
oc exec -n llm-d-multi-gpu $INF_POD -- curl -sk https://localhost:8000/metrics | grep request_success_total
```

**Expected:** Inferentia pod shows non-zero `request_success_total`, confirming EPP is routing to it.

### Step D.7: Run GuideLLM benchmark

See Phase E section for GuideLLM execution procedure. Update the `--target` to point to the new namespace's workload service.

### Node Affinity Summary

| Workload | nodeSelector | schedulerName | Required SCC |
|----------|-------------|---------------|--------------|
| NVIDIA vLLM pods | `node.kubernetes.io/instance-type: g6e.2xlarge` | (default) | (none — KServe managed) |
| Inferentia vLLM pods | `node.kubernetes.io/instance-type: inf2.24xlarge` | `neuron-scheduler` | `privileged` (IPC_LOCK, SYS_ADMIN) |

Both workloads coexist in the same namespace. Kubernetes scheduling ensures pods land on the correct machine pool via nodeSelector.

### GuideLLM Results — Native Heterogeneous (April 8, 2026)

**Configuration:** `llm-d-multi-gpu` namespace, 3 endpoints: 2x NVIDIA L40S (FP8) + 1x Inferentia2 (BF16). Synthetic data: 128/128 tokens.

| # | Strategy | Rate (req/s) | Requests | Errors | Output tok/s | TTFT (ms) | ITL (ms) | Latency (s) | Concurrency |
|---|----------|-------------|----------|--------|-------------|-----------|----------|-------------|-------------|
| 1 | synchronous | - | 3 | 0 | 5.1 | 17,374 | 95.8 | 29.5 | 1.0 |
| 2 | throughput | - | 1,565 | 0 | 3,342 | 1,940 | 86.2 | 12.9 | 336.3 |
| 3 | constant | 3.3 | 166 | 0 | 354 | 114 | 55.8 | 7.2 | 19.9 |
| 4 | constant | 6.5 | 316 | 0 | 675 | 138 | 69.7 | 9.0 | 47.2 |
| 5 | constant | 9.8 | 497 | 0 | 1,062 | 316 | 73.3 | 9.6 | 79.7 |
| 6 | constant | 13.0 | 725 | 0 | 1,547 | 544 | 34.3 | 4.9 | 59.2 |
| 7 | constant | 16.3 | 894 | 0 | 1,908 | 708 | 36.1 | 5.3 | 78.8 |
| 8 | constant | 19.6 | 1,049 | 0 | 2,239 | 851 | 39.4 | 5.9 | 102.3 |
| 9 | constant | 22.8 | 1,192 | 0 | 2,545 | 997 | 42.2 | 6.4 | 126.2 |
| 10 | constant | 26.1 | 1,374 | 0 | 2,934 | 747 | 45.7 | 6.6 | 149.9 |

**Total: 7,781 requests — 0 errors.** Inferentia served 1,125 (~14.5%), NVIDIA served 6,656 (~85.5%).

---

## Phase D (Legacy): Model Name Alignment Planning

> **Note:** The steps below were the original Phase D plan before same-namespace deployment was verified. They are retained for reference but superseded by the verified deployment procedure above.

### Original InferenceModel Configuration

```bash
oc apply -f - <<'EOF'
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferenceModel
metadata:
  name: qwen3-coder-unified
  namespace: llm-d-gpu
spec:
  modelName: qwen3-coder
  poolRef:
    name: qwen3-coder-fp8-inference-pool
EOF
```

**Step D.7: Verify heterogeneous routing**

```bash
# Check all pods discovered by InferencePool
oc get pods -n llm-d-gpu -l inference.networking.x-k8s.io/pool

# Send test requests and check which pod handles them
for i in $(seq 1 10); do
  curl -sk "https://${GW_URL}/llm-d-gpu/qwen3-coder-fp8/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}' &
done
wait

# Check per-pod request counts
for POD in $(oc get pods -n llm-d-gpu -l inference.networking.x-k8s.io/pool -o name); do
  echo "--- $POD ---"
  oc exec -n llm-d-gpu $POD -- curl -sk https://localhost:8000/metrics 2>/dev/null | \
    grep -E "num_requests_total|prefix_cache"
done
```

### Node Affinity Summary

| Workload | nodeSelector | schedulerName | Tolerations |
|----------|-------------|---------------|-------------|
| NVIDIA vLLM pods | `nvidia.com/gpu.present: "true"` | default | `nvidia.com/gpu: NoSchedule` |
| Inferentia vLLM pods | `node.kubernetes.io/instance-type: inf2.24xlarge` | `neuron-scheduler` | (none needed if no taint) |

Both workloads coexist in the same namespace. Kubernetes scheduling ensures pods land on the correct machine pool via nodeSelector/nodeAffinity.

---

## Phase E: GuideLLM Benchmark

### Objective

Run standardized GuideLLM benchmarks against the NVIDIA llm-d gateway to capture comparable metrics to the Inferentia benchmarks in `inferentia_vllm_test_results.md`.

### Prerequisites

- [ ] NVIDIA GPU pool scaled to 2 nodes
- [ ] NVIDIA model pods running and healthy
- [ ] GuideLLM 0.5.4+ installed (`pip install guidellm`)

### Test Configurations

| Test | Prompt Tokens | Output Tokens | Rate Type | Duration | Use Case |
|------|---------------|---------------|-----------|----------|----------|
| 1 | 128 | 128 | sweep | 30s | Quick completions |
| 2 | 128 | 256 | sweep | 30s | Short prompt, medium response |
| 3 | 256 | 256 | sweep | 30s | Balanced medium |
| 4 | 512 | 512 | sweep | 30s | Code generation |
| 5 | 1024 | 512 | sweep | 30s | Large context code review |
| 6 | 2048 | 1024 | sweep | 90s | Large document analysis |

### Commands

```bash
GW_URL=$(oc get gateway -n openshift-ingress maas-default-gateway \
  -o jsonpath='{.status.addresses[0].value}')
TARGET="https://${GW_URL}/llm-d-gpu/qwen3-coder-fp8"
MODEL="Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8"

# Test 1
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 30 \
  --data "prompt_tokens=128,output_tokens=128" \
  --output-path "./nvidia_bench_128in_128out.json"

# Test 2
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 30 \
  --data "prompt_tokens=128,output_tokens=256" \
  --output-path "./nvidia_bench_128in_256out.json"

# Test 3
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 30 \
  --data "prompt_tokens=256,output_tokens=256" \
  --output-path "./nvidia_bench_256in_256out.json"

# Test 4
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 30 \
  --data "prompt_tokens=512,output_tokens=512" \
  --output-path "./nvidia_bench_512in_512out.json"

# Test 5
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 30 \
  --data "prompt_tokens=1024,output_tokens=512" \
  --output-path "./nvidia_bench_1024in_512out.json"

# Test 6 (longer duration for large output)
guidellm benchmark run --target "$TARGET" --model "$MODEL" \
  --rate-type sweep --max-seconds 90 \
  --backend-args '{"timeout": 120.0}' \
  --data "prompt_tokens=2048,output_tokens=1024" \
  --output-path "./nvidia_bench_2048in_1024out.json"
```

### Results Template

Capture in `private_code_assistant.md` under "Performance Benchmark: llm-d on NVIDIA L40S (FP8)":

| Test | Prompt/Output | TTFT (sync, ms) | ITL (sync, ms) | Single-user tok/s | Peak tok/s (sweep) | Peak Concurrency |
|------|---------------|-----------------|----------------|-------------------|-------------------|-----------------|
| 1 | 128 / 128 | | | | | |
| 2 | 128 / 256 | | | | | |
| 3 | 256 / 256 | | | | | |
| 4 | 512 / 512 | | | | | |
| 5 | 1024 / 512 | | | | | |
| 6 | 2048 / 1024 | | | | | |

### Post-Benchmark: Update Comparison Table

After both NVIDIA and Inferentia benchmarks use the same test configurations, update the cross-accelerator comparison to use matched data points.

---

## Phase G: Dual Qwen3-Coder-30B on inf2.48xlarge

### Objective

Validate running two independent Qwen3-Coder-30B BF16 instances on a single `inf2.48xlarge` node using NeuronCore partitioning (`NEURON_RT_VISIBLE_CORES`), benchmark aggregate throughput with GuideLLM, and compare cost-efficiency against 2x `inf2.24xlarge` and 2x `g6e.2xlarge`.

### Background

| Attribute | inf2.48xlarge |
|-----------|---------------|
| Inferentia2 chips | 12 |
| NeuronCores | 24 |
| HBM total | 384 GB (16 GB per core) |
| System memory | 768 GB |
| vCPUs | 192 |
| On-demand cost | $12.98/hr |

**Core partitioning plan:**

| Instance | TP | `NEURON_RT_VISIBLE_CORES` | HBM used | Weights (BF16) | KV headroom |
|----------|-----|---------------------------|----------|----------------|-------------|
| **A** | 8 | `0-7` | 128 GB | ~60 GB | ~68 GB |
| **B** | 8 | `8-15` | 128 GB | ~60 GB | ~68 GB |
| *unused* | — | cores 16-23 | 128 GB | — | — |

16 of 24 cores used (8 wasted, 33% — same TP divisibility constraint as inf2.24xlarge).

**Known risk:** In earlier testing on inf2.24xlarge, a second vLLM instance (Llama-3.1-8B on cores 8-11 alongside Qwen on cores 0-7) failed with `RuntimeError: The PyTorch Neuron Runtime could not be initialized`. This phase determines whether the issue was specific to that configuration or a general multi-instance limitation.

### Prerequisites

- [ ] NEFF compilation cache PVC with warm cache from prior Inferentia testing
- [ ] MutatingAdmissionWebhook for OVN annotation preservation deployed
- [ ] `neuron-scheduler` extension running and healthy
- [ ] HuggingFace token secret `hf-token` in `llm-serving` namespace

### Steps

**G1. Create inf2.48xlarge machine pool**

```bash
rosa create machinepool \
  --cluster=rosa-pca \
  --name=inf2-48xl \
  --instance-type=inf2.48xlarge \
  --replicas=1 \
  --labels=node-role.kubernetes.io/inferentia=,accelerator=neuron \
  --taints=aws.amazon.com/neuron:NoSchedule

oc get nodes -l node.kubernetes.io/instance-type=inf2.48xlarge -w
```

**G2. Create PVC and download model**

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qwen3-coder-inf2-48xl-storage
  namespace: llm-serving
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-csi
  resources:
    requests:
      storage: 200Gi
EOF

oc run model-downloader --rm -it --restart=Never \
  --image=python:3.11-slim \
  --overrides='{
    "spec": {
      "nodeSelector": {"node.kubernetes.io/instance-type": "inf2.48xlarge"},
      "tolerations": [{"key": "aws.amazon.com/neuron", "operator": "Exists"}],
      "containers": [{
        "name": "model-downloader",
        "image": "python:3.11-slim",
        "command": ["bash", "-c",
          "pip install huggingface_hub && python -c \"from huggingface_hub import snapshot_download; snapshot_download(repo_id='\''Qwen/Qwen3-Coder-30B-A3B-Instruct'\'', local_dir='\''/models/Qwen3-Coder-30B-A3B-Instruct'\'')\""
        ],
        "env": [{"name": "HF_TOKEN", "valueFrom": {"secretKeyRef": {"name": "hf-token", "key": "token"}}}],
        "volumeMounts": [{"name": "storage", "mountPath": "/models"}],
        "resources": {"requests": {"memory": "8Gi"}, "limits": {"memory": "16Gi"}}
      }],
      "volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "qwen3-coder-inf2-48xl-storage"}}]
    }
  }' -- bash
```

**G3. Deploy two InferenceService instances**

Both share the PVC via matching `seLinuxOptions.level: "s0:c0,c0"` but target different NeuronCore ranges:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen3-coder-neuron-a
  namespace: llm-serving
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    storage.kserve.io/readonly: "false"
spec:
  predictor:
    model:
      runtime: qwen3-coder-neuron-runtime
      storageUri: pvc://qwen3-coder-inf2-48xl-storage/Qwen3-Coder-30B-A3B-Instruct
      resources:
        requests:
          cpu: "16"
          memory: 128Gi
          aws.amazon.com/neuroncore: "8"
        limits:
          cpu: "32"
          # Neuron compilation peaks at ~120 GB RSS. 200Gi tested minimum.
          memory: 200Gi
          aws.amazon.com/neuroncore: "8"
    nodeSelector:
      node.kubernetes.io/instance-type: inf2.48xlarge
    schedulerName: neuron-scheduler
    securityContext:
      seLinuxOptions:
        level: "s0:c0,c0"
    containers:
      - name: kserve-container
        env:
          - name: NEURON_RT_VISIBLE_CORES
            value: "0-7"
          - name: NEURON_COMPILE_CACHE_URL
            value: "/models/neuron-cache"
          - name: VLLM_NEURON_FRAMEWORK
            value: "neuronx-distributed-inference"
          - name: HF_HOME
            value: "/models/hf-cache"
          - name: VLLM_ENGINE_ITERATION_TIMEOUT_S
            value: "600"
          - name: VLLM_RPC_TIMEOUT
            value: "600000"
        command: ["bash", "-c"]
        args:
          - |
            while [ ! -d "/models/Qwen3-Coder-30B-A3B-Instruct" ]; do sleep 5; done
            python -m vllm.entrypoints.openai.api_server \
              --model /models/Qwen3-Coder-30B-A3B-Instruct \
              --served-model-name qwen3-coder \
              --tensor-parallel-size 8 \
              --max-model-len 8192 \
              --block-size 8 \
              --max-num-seqs 16 \
              --no-enable-prefix-caching \
              --port 8000
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen3-coder-neuron-b
  namespace: llm-serving
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    storage.kserve.io/readonly: "false"
spec:
  predictor:
    model:
      runtime: qwen3-coder-neuron-runtime
      storageUri: pvc://qwen3-coder-inf2-48xl-storage/Qwen3-Coder-30B-A3B-Instruct
      resources:
        requests:
          cpu: "16"
          memory: 128Gi
          aws.amazon.com/neuroncore: "8"
        limits:
          cpu: "32"
          # Neuron compilation peaks at ~120 GB RSS. 200Gi tested minimum.
          memory: 200Gi
          aws.amazon.com/neuroncore: "8"
    nodeSelector:
      node.kubernetes.io/instance-type: inf2.48xlarge
    schedulerName: neuron-scheduler
    securityContext:
      seLinuxOptions:
        level: "s0:c0,c0"
    containers:
      - name: kserve-container
        env:
          - name: NEURON_RT_VISIBLE_CORES
            value: "8-15"
          - name: NEURON_COMPILE_CACHE_URL
            value: "/models/neuron-cache"
          - name: VLLM_NEURON_FRAMEWORK
            value: "neuronx-distributed-inference"
          - name: HF_HOME
            value: "/models/hf-cache"
          - name: VLLM_ENGINE_ITERATION_TIMEOUT_S
            value: "600"
          - name: VLLM_RPC_TIMEOUT
            value: "600000"
        command: ["bash", "-c"]
        args:
          - |
            while [ ! -d "/models/Qwen3-Coder-30B-A3B-Instruct" ]; do sleep 5; done
            python -m vllm.entrypoints.openai.api_server \
              --model /models/Qwen3-Coder-30B-A3B-Instruct \
              --served-model-name qwen3-coder \
              --tensor-parallel-size 8 \
              --max-model-len 8192 \
              --block-size 8 \
              --max-num-seqs 16 \
              --no-enable-prefix-caching \
              --port 8000
```

**G4. Verify both instances**

```bash
oc get pods -n llm-serving -l serving.kserve.io/inferenceservice -o wide

oc logs -n llm-serving deploy/qwen3-coder-neuron-a-predictor | grep -i "neuron\|core\|loaded\|serving"
oc logs -n llm-serving deploy/qwen3-coder-neuron-b-predictor | grep -i "neuron\|core\|loaded\|serving"

# Smoke test each instance
for INST in a b; do
  SVC=$(oc get svc -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron-$INST \
    -o jsonpath='{.items[0].metadata.name}')
  oc run smoke-$INST --rm -it --restart=Never --image=curlimages/curl -- \
    curl -s http://$SVC.llm-serving.svc:8000/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'
done
```

**G5. GuideLLM benchmark — per-instance and combined**

Run the same 6-test GuideLLM sweep used for inf2.24xlarge (see `inferentia_vllm_test_results.md` Run 1):

```bash
pip install guidellm==0.5.4

# Per-instance benchmarks
for INST in a b; do
  SVC=$(oc get svc -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron-$INST \
    -o jsonpath='{.items[0].metadata.name}')
  for P_O in "128:128" "128:256" "256:256" "512:512" "1024:512" "2048:1024"; do
    P=$(echo $P_O | cut -d: -f1); O=$(echo $P_O | cut -d: -f2)
    TIMEOUT=120; [ "$O" = "1024" ] && TIMEOUT=180
    guidellm \
      --target "http://$SVC.llm-serving.svc:8000/v1" \
      --model qwen3-coder \
      --rate-type sweep \
      --data "prompt_tokens=$P,output_tokens=$O" \
      --max-seconds $TIMEOUT \
      --backend-args "{\"timeout\": $(( TIMEOUT + 60 )).0}" \
      --output-path "./inf2-48xl-inst-${INST}-${P}in-${O}out.json"
  done
done

# Combined load test via headless Service spanning both instances
oc apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: qwen3-coder-combined
  namespace: llm-serving
spec:
  clusterIP: None
  ports:
    - port: 8000
      targetPort: 8000
  selector:
    serving.kserve.io/inferenceservice-group: qwen3-coder-neuron
EOF

oc label pods -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron-a \
  serving.kserve.io/inferenceservice-group=qwen3-coder-neuron
oc label pods -n llm-serving -l serving.kserve.io/inferenceservice=qwen3-coder-neuron-b \
  serving.kserve.io/inferenceservice-group=qwen3-coder-neuron

guidellm \
  --target "http://qwen3-coder-combined.llm-serving.svc:8000/v1" \
  --model qwen3-coder \
  --rate-type sweep \
  --data "prompt_tokens=512,output_tokens=512" \
  --max-seconds 120 \
  --backend-args '{"timeout": 180.0}' \
  --output-path "./inf2-48xl-combined-512in-512out.json"
```

### Results Template

**Per-instance (should match inf2.24xlarge baseline):**

| Metric | Instance A (cores 0-7) | Instance B (cores 8-15) | inf2.24xlarge baseline |
|--------|------------------------|-------------------------|------------------------|
| Single-user TTFT (ms) | | | 495-523 |
| Single-user ITL (ms) | | | 40.9-41.0 |
| Single-user tok/s | | | 22.7-24.2 |
| Peak aggregate tok/s | | | 154.2 |
| Neuron runtime init | ✅ / ❌ | ✅ / ❌ | ✅ |

**Combined (512/512, both instances behind headless Service):**

| Metric | Combined (A + B) | 2x inf2.24xlarge (est.) | 2x g6e.2xlarge (tested) |
|--------|-------------------|-------------------------|-------------------------|
| Peak aggregate tok/s | | ~308 | 482 |
| Cost/hr | $12.98 | $12.98 | $4.48 |
| Cost per 1M output tokens | | ~$11.69 | ~$0.65 |

### Success Criteria

- [ ] Both instances start successfully (Neuron runtime initializes on separate core ranges)
- [ ] Per-instance throughput matches inf2.24xlarge baseline (~24 tok/s single-user, ~154 tok/s peak)
- [ ] Combined throughput ≈ 2× single-instance (~308 tok/s peak)
- [ ] No Neuron runtime conflicts, SIGBUS, or OOM during concurrent operation
- [ ] NEFF cache shared successfully between both instances via PVC

### Decision Tree

- **Both instances work**: Document as validated. inf2.48xlarge can serve 2 Qwen instances, 8-10 interactive devs, at $12.98/hr (compare to 2x g6e.2xlarge at $4.48/hr for 16-20 devs).
- **Instance B fails to init**: Neuron runtime does not support multi-instance on shared hardware. Document limitation. Recommend 2x inf2.24xlarge for 2-instance Inferentia deployments.
- **Performance degradation >20%**: HBM bandwidth contention between instances. Document per-instance numbers and note that inf2.48xlarge is better suited for a single TP=16 instance.

**G6. Scale down inf2.48xlarge pool**

```bash
rosa edit machinepool --cluster=rosa-pca --name=inf2-48xl --replicas=0
oc get nodes -l node.kubernetes.io/instance-type=inf2.48xlarge
```

Do **not** delete the PVC — NEFF cache artifacts persist for future testing.

**G7. Update documentation**

Record results in `private_code_assistant.md` under "Phase 4: Dual Qwen3-Coder-30B on inf2.48xlarge" with actual benchmark numbers and final verdict.

---

## Phase F: Scale Down

### Prerequisites

- [ ] All benchmarks captured and documented
- [ ] Heterogeneous routing test results documented
- [ ] DRA retest results documented
- [ ] Phase G (inf2.48xlarge dual-instance) results documented
- [ ] `private_code_assistant.md` updated with all findings

### Steps

```bash
# Scale Inferentia pools to 0
rosa edit machinepool --cluster=rosa-pca --name=inf2-24xl --replicas=0
rosa edit machinepool --cluster=rosa-pca --name=inf2-48xl --replicas=0

# Scale NVIDIA pool to 0
rosa edit machinepool --cluster=rosa-pca --name=gpu-l40s --replicas=0

# Verify
rosa list machinepools --cluster=rosa-pca
```

### Post-Scale-Down Verification

```bash
oc get nodes -l nvidia.com/gpu.present=true
# Expected: No nodes

oc get nodes -l node.kubernetes.io/instance-type=inf2.24xlarge
# Expected: No nodes

oc get nodes -l node.kubernetes.io/instance-type=inf2.48xlarge
# Expected: No nodes

# Worker nodes should still be running
oc get nodes
```

### Document Final State

Update `private_code_assistant.md` with:
- Final machine pool status (all accelerator pools at 0)
- Summary of all test results
- Updated document version

---

## Execution Order

| Order | Step / Phase | Dependencies | Estimated Duration |
|-------|-------------|-------------|-------------------|
| 0 | **Step 0**: Cluster availability check | None | 10 min |
| 1 | **Steps 1-9**: Cluster + operators + gateway (if new cluster) | Step 0 determines if needed | 1-2 hours |
| 2 | **Step 10**: NVIDIA model deployment | Operators installed, GPU pool ready | 30-60 min |
| 3 | **Step 11**: Inferentia model deployment + NEFF cache | Operators installed, inf2 pool ready | 30-60 min (cached) to 4 hours (first compile) |
| 4 | **Step 12**: Dev Spaces + 3 users + extensions | Model endpoints active | 30-60 min |
| 5 | **Step 13**: End-to-end verification | All above complete | 30 min |
| 6 | **Step 14**: Consolidated access report | Step 13 passed | 15 min |
| 7 | **Phase A**: Throughput consolidation | None -- data already exists | 30 min (documentation) |
| 8 | **Phase B**: DRA retest | Inferentia pool at 1 node | 1-2 hours |
| 9 | **Phase C**: HTTPS on Inferentia | Inferentia model serving | 1 hour |
| 10 | **Phase D**: Same-namespace + model name | Phase C complete | 1-2 hours |
| 11 | **Phase E**: GuideLLM benchmark (NVIDIA) | NVIDIA pods running | 2-3 hours |
| 12 | **Phase G**: Dual Qwen3-Coder on inf2.48xlarge | NEFF cache PVC, webhook deployed | 3-5 hours (incl. compilation if cache miss) |
| 13 | **Phase F**: Scale down all accelerator pools | All phases complete | 15 min |

**Total estimated time (new cluster)**: 12-20 hours
**Total estimated time (existing cluster, pools at 0)**: 8-14 hours
**Total estimated time (existing cluster, pools running)**: 6-10 hours

Phases B-E can partially overlap when different accelerator pools are involved. Phase G requires its own inf2.48xlarge pool and can run in parallel with Phase E (NVIDIA benchmarks).

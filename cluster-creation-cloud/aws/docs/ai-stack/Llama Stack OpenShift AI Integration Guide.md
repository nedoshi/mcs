# Llama Stack OpenShift AI Integration Guide

## 🎯 **Overview**

This guide provides step-by-step instructions to configure Llama Stack for seamless integration with OpenShift AI after installation. The integration enables advanced agentic AI capabilities, model serving, and enterprise-grade AI workloads.

## 📋 **Current Integration Status Analysis**

### ✅ **What's Already Configured**
- **Llama Stack Operator**: ✅ Enabled in DataScienceCluster (`managementState: Managed`)
- **Llama Stack K8s Operator**: ✅ Running in `redhat-ods-applications` namespace
- **Custom Resource Definitions**: ✅ `LlamaStackDistribution` CRD available
- **OpenShift AI Platform**: ✅ Fully deployed with all required components

### ❌ **What's Missing for Full Integration**
- **LlamaStackDistribution Instance**: No instances deployed
- **Model Serving Runtime**: No vLLM or model serving endpoints configured
- **Authentication Configuration**: OAuth/OIDC integration not set up
- **Service Integration**: No routes or services exposed for external access

## 🔧 **Step-by-Step Integration Configuration**

### **Step 1: Verify Llama Stack Operator Status**

```bash
# Check if Llama Stack Operator is enabled in DataScienceCluster
oc get datasciencecluster default-dsc -n redhat-ods-operator -o yaml | grep -A 2 llamastackoperator

# Verify operator pod is running
oc get pods -n redhat-ods-applications | grep llama-stack-k8s-operator

# Check available CRDs
oc get crd | grep llama
```

**Expected Output:**
```
llamastackoperator:
  managementState: Managed

llama-stack-k8s-operator-controller-manager-xxx   1/1     Running

llamastackdistributions.llamastack.io
llamastackoperators.components.platform.opendatahub.io
```

### **Step 2: Create LlamaStackDistribution Instance**

Create a `LlamaStackDistribution` custom resource to deploy Llama Stack components:

```yaml
# llama-stack-distribution.yaml
apiVersion: llamastack.io/v1alpha1
kind: LlamaStackDistribution
metadata:
  name: default-llama-stack
  namespace: redhat-ods-applications
  labels:
    app: llama-stack
    integration: openshift-ai
spec:
  # Distribution configuration - use starter-gpu for GPU-enabled deployments
  distribution: "starter-gpu"
  
  # Container image configuration
  image:
    repository: "quay.io/opendatahub/llama-stack"
    tag: "odh"
    pullPolicy: "IfNotPresent"
  
  # Resource requirements
  resources:
    requests:
      memory: "8Gi"
      cpu: "4"
      nvidia.com/gpu: "1"  # Requires GPU nodes
    limits:
      memory: "16Gi"
      cpu: "8"
      nvidia.com/gpu: "1"
  
  # Node selection for GPU nodes
  nodeSelector:
    node-type: gpu
  
  # Tolerations for GPU taints
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
  
  # Persistent storage configuration
  storage:
    size: "50Gi"
    mountPath: "/data"
  
  # Environment variables for integration
  env:
  - name: LLAMA_STACK_CONFIG
    value: "/config/stack-config.yaml"
  - name: PYTHONUNBUFFERED
    value: "1"
  - name: LOG_LEVEL
    value: "INFO"
  
  # Service configuration for external access
  service:
    type: ClusterIP
    ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: metrics
      port: 9090
      targetPort: 9090
```

Apply the configuration:
```bash
oc apply -f llama-stack-distribution.yaml
```

### **Step 3: Configure Authentication (OAuth/OIDC)**

Create authentication configuration for secure access:

```yaml
# llama-stack-auth-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llama-stack-auth-config
  namespace: redhat-ods-applications
data:
  auth-config.yaml: |
    server:
      auth:
        provider_config:
          type: "oauth2_token"
          jwks:
            uri: "https://kubernetes.default.svc:8443/openid/v1/jwks"
            token: "${env.TOKEN:+}"
            key_recheck_period: 3600
          validation:
            audience: "https://kubernetes.default.svc"
            issuer: "https://kubernetes.default.svc:8443"
```

```bash
oc apply -f llama-stack-auth-config.yaml
```

### **Step 4: Create Model Serving Runtime (vLLM Integration)**

Configure vLLM serving runtime for model inference:

```yaml
# vllm-serving-runtime.yaml
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-llama-runtime
  namespace: redhat-ods-applications
spec:
  supportedModelFormats:
  - name: pytorch
    version: "1"
    autoSelect: true
  containers:
  - name: kserve-container
    image: quay.io/opendatahub/vllm:stable
    args:
    - --model
    - /mnt/models
    - --port
    - "8080"
    - --served-model-name
    - llama-model
    - --trust-remote-code
    resources:
      requests:
        cpu: "4"
        memory: "8Gi"
        nvidia.com/gpu: "1"
      limits:
        cpu: "8"
        memory: "16Gi"
        nvidia.com/gpu: "1"
    ports:
    - containerPort: 8080
      name: http1
      protocol: TCP
  builtInAdapter:
    serverType: vllm
    runtimeManagementPort: 8080
    memBufferBytes: 134217728
    modelLoadingTimeoutMillis: 90000
```

```bash
oc apply -f vllm-serving-runtime.yaml
```

### **Step 5: Expose Services and Create Routes**

Create OpenShift routes for external access:

```yaml
# llama-stack-route.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: llama-stack-api
  namespace: redhat-ods-applications
  labels:
    app: llama-stack
spec:
  to:
    kind: Service
    name: default-llama-stack-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

```bash
oc apply -f llama-stack-route.yaml
```

### **Step 6: Integration with OpenShift AI Projects**

Create a Data Science Project and configure model deployment:

```bash
# Create a new Data Science Project for Llama Stack
oc new-project llama-stack-project

# Label the project for OpenShift AI integration
oc label namespace llama-stack-project opendatahub.io/dashboard=true

# Create InferenceService for model deployment
cat << EOF | oc apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama-model-service
  namespace: llama-stack-project
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      runtime: vllm-llama-runtime
      storage:
        key: default-bucket
        path: models/llama-3.2-8b
EOF
```

### **Step 7: Verification and Testing**

Verify the integration is working correctly:

```bash
# Check LlamaStackDistribution status
oc get llamastackdistributions -n redhat-ods-applications

# Verify pods are running
oc get pods -n redhat-ods-applications | grep llama

# Check services and routes
oc get svc,route -n redhat-ods-applications | grep llama

# Test API endpoint
LLAMA_STACK_URL=$(oc get route llama-stack-api -n redhat-ods-applications -o jsonpath='{.spec.host}')
curl -k https://$LLAMA_STACK_URL/health

# Check model serving
oc get inferenceservice -n llama-stack-project
```

## 🔍 **Integration Validation Checklist**

### **✅ Required Components Status**
- [ ] LlamaStackDistribution instance deployed and ready
- [ ] Llama Stack pods running without errors
- [ ] vLLM serving runtime configured
- [ ] Authentication provider configured
- [ ] Routes exposed for external access
- [ ] Model serving endpoints available
- [ ] Integration with OpenShift AI projects working

### **🧪 Testing Scenarios**
- [ ] API health check returns 200 OK
- [ ] Authentication validates tokens correctly
- [ ] Model inference requests succeed
- [ ] Metrics endpoints are accessible
- [ ] Integration with Jupyter notebooks works
- [ ] Data Science Project integration functional

## 🚨 **Common Issues and Troubleshooting**

### **Issue 1: LlamaStackDistribution Not Creating Pods**
```bash
# Check operator logs
oc logs -n redhat-ods-applications deployment/llama-stack-k8s-operator-controller-manager

# Describe the LlamaStackDistribution resource
oc describe llamastackdistribution default-llama-stack -n redhat-ods-applications
```

### **Issue 2: GPU Resources Not Available**
```bash
# Verify GPU nodes are available
oc get nodes -l feature.node.kubernetes.io/pci-0300_10de.present=true

# Check GPU resource allocation
oc describe node <gpu-node-name> | grep nvidia.com/gpu
```

### **Issue 3: Authentication Failures**
```bash
# Check service account tokens
oc get serviceaccount default -n redhat-ods-applications -o yaml

# Verify RBAC permissions
oc auth can-i create pods --as=system:serviceaccount:redhat-ods-applications:default
```

## 📚 **Additional Resources**

### **Red Hat Documentation**
- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [Deploying RAG Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.23/html/working_with_rag/deploying-a-rag-stack-in-a-data-science-project_rag)
- [Model Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.23/html/serving_models/)

### **Community Resources**
- [Llama Stack Documentation](https://llama-stack.readthedocs.io/)
- [OpenShift AI Examples](https://github.com/opendatahub-io/odh-manifests)
- [KServe Documentation](https://kserve.github.io/website/)

---

**Last Updated**: September 25, 2025
**Cluster**: airosa (ROSA HCP)
**OpenShift AI Version**: 2.23+
**Llama Stack Operator**: Enabled and Ready


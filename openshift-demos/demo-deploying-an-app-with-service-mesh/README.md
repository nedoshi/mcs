# Deploying an Application with Service Mesh

This demo shows how to deploy an application and integrate it with OpenShift Service Mesh (based on Istio).

## Overview

This demo demonstrates:
- Adding a namespace to the Service Mesh
- Configuring Service Mesh membership
- Deploying a sample application within the Service Mesh
- Verifying Service Mesh integration

## Prerequisites

Before you begin, ensure you have:

1. **OpenShift Cluster** with cluster-admin access
2. **Service Mesh Operator** installed
3. **Service Mesh Control Plane** deployed (typically named `basic` in `istio-system` namespace)
4. **OpenShift CLI (oc)** installed and configured
5. **kubectl** (optional, for additional operations)

## Service Mesh Setup

### 1. Verify Service Mesh Installation

Check that the Service Mesh operator and control plane are installed:

```bash
# Check Service Mesh operator
oc get csv -n openshift-operators | grep servicemesh

# Check Service Mesh control plane
oc get smcp -n istio-system

# Verify control plane pods are running
oc get pods -n istio-system
```

### 2. Create Application Namespace

Create the namespace for your application:

```bash
oc create namespace hello
```

Or if using the example application:

```bash
oc create namespace hello
oc label namespace hello istio-injection=enabled
```

## Deploying the Configuration

### Option 1: Add Namespace to Service Mesh (Recommended)

This method adds the namespace to the Service Mesh MemberRoll, which automatically includes all pods in that namespace:

```bash
oc apply -f servicemeshroll.yaml
```

This adds the `hello` namespace to the Service Mesh.

### Option 2: Individual Service Mesh Member

Alternatively, you can create a ServiceMeshMember resource in your application namespace:

```bash
oc apply -f servicemeshmember.yaml
```

This explicitly adds the namespace to the Service Mesh.

## Deploying the Example Application

### 1. Deploy the Sample Application

Deploy the example hello-world application:

```bash
oc apply -f app-deployment.yaml -n hello
```

### 2. Verify Deployment

Check that the application pods are running:

```bash
oc get pods -n hello
```

You should see pods with sidecar containers (Envoy proxy) injected by Service Mesh.

### 3. Verify Service Mesh Integration

Check that the pods have the Envoy sidecar:

```bash
oc get pods -n hello -o jsonpath='{.items[*].spec.containers[*].name}'
```

You should see both your application container and the `istio-proxy` sidecar.

### 4. Check Service Mesh Status

Verify the namespace is part of the Service Mesh:

```bash
# Check Service Mesh MemberRoll
oc get smmr -n istio-system

# Check Service Mesh Members
oc get smm -n hello
```

## Understanding the Files

### `servicemeshroll.yaml`

This file configures the Service Mesh MemberRoll, which defines which namespaces are part of the Service Mesh:

- **Namespace**: `istio-system` (where Service Mesh control plane runs)
- **Members**: List of namespaces to include in the Service Mesh
- In this example, the `hello` namespace is added

### `servicemeshmember.yaml`

This file creates a ServiceMeshMember resource in the application namespace:

- **Namespace**: `hello` (your application namespace)
- **Control Plane Reference**: Points to the `basic` control plane in `istio-system`
- This explicitly requests Service Mesh membership for the namespace

### `app-deployment.yaml`

This file contains a sample application deployment:

- **Deployment**: Simple hello-world application
- **Service**: ClusterIP service for the application
- **Route**: OpenShift route for external access

## Customization

### Change Namespace

To use a different namespace, update the files:

1. Replace `hello` with your namespace name in:
   - `servicemeshroll.yaml` (members list)
   - `servicemeshmember.yaml` (metadata.namespace)
   - `app-deployment.yaml` (namespace in resources)

2. Create your namespace:
   ```bash
   oc create namespace your-namespace
   ```

### Change Control Plane

If your Service Mesh control plane has a different name or is in a different namespace:

1. Update `servicemeshmember.yaml`:
   ```yaml
   spec:
     controlPlaneRef:
       namespace: your-istio-namespace
       name: your-control-plane-name
   ```

2. Update `servicemeshroll.yaml` namespace if needed

## Verification Steps

### 1. Check Pod Sidecars

```bash
oc describe pod <pod-name> -n hello | grep -A 5 "Containers:"
```

You should see the `istio-proxy` container listed.

### 2. Check Service Mesh Metrics

Access Service Mesh metrics (if Kiali is installed):

```bash
oc get route -n istio-system kiali
```

### 3. Test Application

Access the application:

```bash
# Get the route
oc get route -n hello

# Test the application
curl $(oc get route -n hello -o jsonpath='{.items[0].spec.host}')
```

## Advanced Configuration

### VirtualService and DestinationRule

To configure traffic management, you can create VirtualService and DestinationRule resources:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: hello
  namespace: hello
spec:
  hosts:
  - hello
  http:
  - route:
    - destination:
        host: hello
        subset: v1
      weight: 100
```

### mTLS Configuration

To enable mutual TLS between services:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: hello
spec:
  mtls:
    mode: STRICT
```

## Troubleshooting

### Pods Not Getting Sidecar Injection

1. Verify namespace is in Service Mesh:
   ```bash
   oc get smmr -n istio-system -o yaml
   ```

2. Check namespace labels:
   ```bash
   oc get namespace hello -o yaml | grep labels
   ```

3. Ensure pods are created after Service Mesh membership is established

### Service Mesh Member Not Working

1. Check Service Mesh control plane status:
   ```bash
   oc get smcp -n istio-system
   ```

2. Verify control plane pods are ready:
   ```bash
   oc get pods -n istio-system
   ```

3. Check for errors in control plane logs:
   ```bash
   oc logs -n istio-system -l app=istiod
   ```

### Application Not Accessible

1. Verify application pods are running:
   ```bash
   oc get pods -n hello
   ```

2. Check service configuration:
   ```bash
   oc get svc -n hello
   ```

3. Verify route exists:
   ```bash
   oc get route -n hello
   ```

## Cleanup

To remove the demo:

```bash
# Delete the application
oc delete -f app-deployment.yaml -n hello

# Remove from Service Mesh (choose one method)
oc delete -f servicemeshroll.yaml
# OR
oc delete -f servicemeshmember.yaml -n hello

# Delete namespace (optional)
oc delete namespace hello
```

## Additional Resources

- [OpenShift Service Mesh Documentation](https://docs.openshift.com/container-platform/latest/service_mesh/v2x/ossm-about.html)
- [Istio Documentation](https://istio.io/latest/docs/)
- [Service Mesh Tutorials](https://istio.io/latest/docs/tasks/)

## Notes

- The namespace `hello` and control plane name `basic` are examples. Adjust these to match your environment.
- Service Mesh sidecar injection happens automatically for pods created after namespace membership is established.
- Existing pods may need to be recreated to get the sidecar injected.


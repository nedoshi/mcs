# Comprehensive DNS Troubleshooting Guide for OpenShift Environments

## Overview

This guide covers DNS troubleshooting for all OpenShift variants:
- **OpenShift Container Platform (OCP)** - Self-managed on-premises or cloud
- **OpenShift Dedicated (OSD)** - Managed OpenShift on AWS/GCP
- **Red Hat OpenShift Service on AWS (ROSA)** - Managed OpenShift on AWS
- **Azure Red Hat OpenShift (ARO)** - Managed OpenShift on Azure

## Table of Contents

1. [DNS Architecture Overview](#dns-architecture-overview)
2. [Common DNS Issues](#common-dns-issues)
3. [Platform-Specific Considerations](#platform-specific-considerations)
4. [Diagnostic Commands and Tools](#diagnostic-commands-and-tools)
5. [Step-by-Step Troubleshooting](#step-by-step-troubleshooting)
6. [Verification and Testing](#verification-and-testing)
7. [Resolution Strategies](#resolution-strategies)
8. [Prevention and Best Practices](#prevention-and-best-practices)

## DNS Architecture Overview

### OpenShift DNS Components

OpenShift uses several DNS components working together:

- **CoreDNS** - Primary DNS server running as pods in `openshift-dns` namespace
- **DNS Operator** - Manages CoreDNS configuration and lifecycle
- **Node Resolver** - systemd-resolved or NetworkManager on RHCOS nodes
- **Service DNS** - Internal service discovery via cluster.local domain
- **Route DNS** - External access through ingress/routes

### DNS Flow in OpenShift

```
Client Request → Ingress Controller → Service → Pod
     ↓              ↓                 ↓        ↓
External DNS → Route DNS → Service DNS → Pod DNS
```

## Common DNS Issues

### 1. Pod-to-Service Resolution Failures
- Services not resolving within cluster
- Intermittent resolution failures
- Cross-namespace resolution issues

### 2. External DNS Resolution Problems
- Pods can't reach external services
- Slow external DNS queries
- DNS timeouts

### 3. Route/Ingress DNS Issues
- Applications not accessible externally
- Wildcard certificate problems
- Load balancer DNS configuration

### 4. Node DNS Configuration Problems
- Node-level DNS misconfiguration
- Upstream DNS server issues
- Search domain conflicts

## Platform-Specific Considerations

### OpenShift Container Platform (OCP)

**Self-Managed Infrastructure:**
- Full control over DNS configuration
- Need to configure external DNS zones
- Responsible for load balancer DNS setup

**Key Areas:**
- Cluster DNS operator configuration
- External DNS integration
- Load balancer endpoint management

### OpenShift Dedicated (OSD)

**Managed Service Characteristics:**
- Limited access to infrastructure layer
- Red Hat manages DNS operator
- Customer manages application DNS

**Troubleshooting Scope:**
- Application-level DNS issues
- Service discovery problems
- Route configuration issues

### ROSA (Red Hat OpenShift Service on AWS)

**AWS-Specific Considerations:**
- Route 53 integration
- VPC DNS settings
- Private vs public subnets
- AWS Load Balancer Controller

**Common Issues:**
- Route 53 hosted zone configuration
- VPC DNS resolution settings
- Security group DNS traffic rules

### ARO (Azure Red Hat OpenShift)

**Azure-Specific Considerations:**
- Azure DNS integration
- Virtual Network DNS settings
- Azure Load Balancer configuration
- Private DNS zones

**Common Issues:**
- Azure DNS zone delegation
- Virtual network DNS configuration
- NSG rules affecting DNS traffic

## Diagnostic Commands and Tools

### Basic Cluster Information

```bash
# Check cluster version and status
oc version
oc get clusterversion

# Check DNS operator status
oc get clusteroperator/dns
oc describe clusteroperator/dns

# Check DNS pods
oc get pods -n openshift-dns
oc get pods -n openshift-dns-operator
```

### DNS Configuration Analysis

```bash
# Check DNS operator configuration
oc get dns.operator/default -o yaml

# Check CoreDNS configuration
oc get configmap/dns-default -n openshift-dns -o yaml

# Check DNS services
oc get svc -n openshift-dns
oc describe svc/dns-default -n openshift-dns
```

### Node-Level DNS Diagnostics

```bash
# Check node DNS configuration
oc debug node/<node-name>
chroot /host
cat /etc/resolv.conf
systemctl status systemd-resolved

# Test DNS from node
nslookup kubernetes.default.svc.cluster.local
dig @<dns-service-ip> kubernetes.default.svc.cluster.local
```

### Pod-Level DNS Testing

```bash
# Create debug pod for testing
oc run dns-test --image=registry.redhat.io/ubi8/ubi:latest --rm -it -- bash

# Inside the pod, test DNS resolution
nslookup kubernetes.default.svc.cluster.local
nslookup <service-name>.<namespace>.svc.cluster.local
nslookup google.com

# Check pod's resolv.conf
cat /etc/resolv.conf
```

## Step-by-Step Troubleshooting

### Step 1: Verify DNS Operator Health

```bash
# Check DNS operator status
oc get clusteroperator/dns

# If degraded, check operator logs
oc logs -n openshift-dns-operator deployment/dns-operator

# Check DNS operator events
oc get events -n openshift-dns-operator --sort-by='.lastTimestamp'
```

### Step 2: Verify CoreDNS Pods

```bash
# Check all DNS pods are running
oc get pods -n openshift-dns

# Check for any failed pods
oc describe pod -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default

# Check CoreDNS logs
oc logs -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default
```

### Step 3: Test Internal DNS Resolution

```bash
# Test service discovery
oc run dns-debug --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Test cross-namespace resolution
oc run dns-debug --image=busybox:1.28 --rm -it --restart=Never -- nslookup <service>.<namespace>.svc.cluster.local
```

### Step 4: Test External DNS Resolution

```bash
# Test external DNS from pod
oc run dns-debug --image=busybox:1.28 --rm -it --restart=Never -- nslookup google.com

# Check DNS performance
oc run dns-debug --image=busybox:1.28 --rm -it --restart=Never -- time nslookup google.com
```

### Step 5: Verify Route/Ingress DNS

```bash
# Check routes
oc get routes --all-namespaces

# Test route resolution
nslookup <route-hostname>

# Check ingress controller
oc get pods -n openshift-ingress
oc logs -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default
```

## Verification and Testing

### Create Test Resources

```yaml
# test-dns-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dns-test-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dns-test
  template:
    metadata:
      labels:
        app: dns-test
    spec:
      containers:
      - name: dns-test
        image: registry.redhat.io/ubi8/ubi:latest
        command: ["/bin/bash", "-c", "while true; do sleep 3600; done"]
---
apiVersion: v1
kind: Service
metadata:
  name: dns-test-service
  namespace: default
spec:
  selector:
    app: dns-test
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: dns-test-route
  namespace: default
spec:
  to:
    kind: Service
    name: dns-test-service
```

### Comprehensive DNS Tests

```bash
# Apply test resources
oc apply -f test-dns-deployment.yaml

# Test 1: Pod-to-Pod resolution
oc exec deployment/dns-test-app -- nslookup dns-test-service.default.svc.cluster.local

# Test 2: Cross-namespace resolution
oc exec deployment/dns-test-app -- nslookup kubernetes.default.svc.cluster.local

# Test 3: External resolution
oc exec deployment/dns-test-app -- nslookup redhat.com

# Test 4: Route resolution (external)
ROUTE_HOST=$(oc get route dns-test-route -o jsonpath='{.spec.host}')
nslookup $ROUTE_HOST

# Test 5: Performance test
oc exec deployment/dns-test-app -- time nslookup dns-test-service.default.svc.cluster.local
```

### Automated DNS Verification Script

```bash
#!/bin/bash
# dns-health-check.sh

echo "=== OpenShift DNS Health Check ==="

# Check DNS operator
echo "1. Checking DNS Operator..."
oc get clusteroperator/dns --no-headers | awk '{print "Status: " $3 " " $4 " " $5}'

# Check DNS pods
echo "2. Checking DNS Pods..."
DNS_PODS=$(oc get pods -n openshift-dns --no-headers | grep -v Running | wc -l)
if [ $DNS_PODS -eq 0 ]; then
    echo "✓ All DNS pods are running"
else
    echo "✗ $DNS_PODS DNS pods are not running"
fi

# Test internal DNS
echo "3. Testing Internal DNS..."
if oc run dns-test-temp --image=busybox:1.28 --rm -it --restart=Never --timeout=30s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
    echo "✓ Internal DNS resolution working"
else
    echo "✗ Internal DNS resolution failed"
fi

# Test external DNS
echo "4. Testing External DNS..."
if oc run dns-test-temp --image=busybox:1.28 --rm -it --restart=Never --timeout=30s -- nslookup google.com >/dev/null 2>&1; then
    echo "✓ External DNS resolution working"
else
    echo "✗ External DNS resolution failed"
fi

echo "=== DNS Health Check Complete ==="
```

## Resolution Strategies

### For DNS Operator Issues

```bash
# Restart DNS operator
oc delete pod -n openshift-dns-operator -l name=dns-operator

# Check and update DNS operator configuration
oc edit dns.operator/default

# Force DNS operator reconciliation
oc patch dns.operator/default --type merge --patch='{"spec":{"managementState":"Unmanaged"}}'
oc patch dns.operator/default --type merge --patch='{"spec":{"managementState":"Managed"}}'
```

### For CoreDNS Pod Issues

```bash
# Restart all CoreDNS pods
oc delete pods -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default

# Check CoreDNS configuration
oc get configmap/dns-default -n openshift-dns -o yaml

# Update CoreDNS configuration if needed
oc edit configmap/dns-default -n openshift-dns
```

### For Service Resolution Issues

```bash
# Check service endpoints
oc get endpoints <service-name>

# Verify service selector matches pod labels
oc describe service <service-name>
oc get pods --show-labels

# Test service directly
oc port-forward service/<service-name> 8080:80
```

### For External DNS Issues

```bash
# Check upstream DNS configuration
oc debug node/<node-name>
chroot /host
cat /etc/resolv.conf

# Update DNS configuration if needed (OCP only)
oc edit dns.operator/default
```

### Platform-Specific Resolutions

#### ROSA-Specific

```bash
# Check VPC DNS settings
aws ec2 describe-vpcs --vpc-ids <vpc-id> --query 'Vpcs[0].{DnsHostnames:DnsHostnames,DnsResolution:DnsResolution}'

# Verify Route 53 configuration
aws route53 list-hosted-zones
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

#### ARO-Specific

```bash
# Check Azure DNS configuration
az network vnet show --resource-group <rg> --name <vnet> --query dnsServers

# Verify private DNS zones
az network private-dns zone list --resource-group <rg>
```

## Prevention and Best Practices

### Monitoring and Alerting

```yaml
# Example PrometheusRule for DNS monitoring
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dns-monitoring
  namespace: openshift-dns
spec:
  groups:
  - name: dns.rules
    rules:
    - alert: CoreDNSDown
      expr: up{job="dns-default"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: CoreDNS is down
    - alert: DNSQueryFailureRate
      expr: rate(coredns_dns_request_count_total{rcode!="NOERROR"}[5m]) > 0.1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: High DNS query failure rate
```

### Regular Health Checks

```bash
# Add to monitoring scripts
# Weekly DNS health verification
0 2 * * 1 /path/to/dns-health-check.sh >> /var/log/dns-health.log 2>&1
```

### Configuration Management

1. **Document DNS Dependencies**: Maintain inventory of external DNS dependencies
2. **Version Control**: Keep DNS configurations in version control
3. **Testing**: Include DNS tests in CI/CD pipelines
4. **Backup**: Regular backup of DNS configurations

### Capacity Planning

- Monitor DNS query rates and response times
- Plan for DNS pod scaling during high load
- Consider DNS caching strategies for external queries

## Troubleshooting Decision Tree

```
DNS Issue Reported
       ↓
Is DNS Operator Healthy?
   ↓         ↓
  No        Yes
   ↓         ↓
Fix Operator → Are CoreDNS Pods Running?
              ↓         ↓
             No        Yes
              ↓         ↓
         Restart Pods → Test Internal Resolution
                       ↓         ↓
                     Fails    Works
                       ↓         ↓
                Check Service → Test External Resolution
                Configuration   ↓         ↓
                              Fails    Works
                               ↓         ↓
                        Check Upstream → Check Routes/Ingress
                        DNS Config
```

## Additional Resources

- [OpenShift DNS Operator Documentation](https://docs.openshift.com/container-platform/latest/networking/dns-operator.html)
- [CoreDNS Documentation](https://coredns.io/manual/toc/)
- [OpenShift Networking Troubleshooting](https://docs.openshift.com/container-platform/latest/support/troubleshooting/investigating-pod-issues.html)
- [ROSA Networking Documentation](https://docs.openshift.com/rosa/networking/index.html)
- [ARO Networking Documentation](https://docs.microsoft.com/en-us/azure/openshift/)

## Conclusion

DNS issues in OpenShift environments require systematic troubleshooting across multiple layers. This guide provides the tools and procedures needed to identify, diagnose, and resolve DNS problems across all OpenShift variants. Regular monitoring and proactive maintenance are key to preventing DNS-related outages.

Remember to adapt the troubleshooting steps based on your specific OpenShift deployment model and underlying infrastructure provider.
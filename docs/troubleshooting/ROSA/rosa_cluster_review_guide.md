# Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane Cluster Review Guide

## Overview

This guide provides comprehensive steps to verify that your Red Hat OpenShift Service on AWS Hosted Control Plane cluster has all necessary components and configurations. The review focuses on four key areas:

- DNS lookup verification
- Security settings and access controls
- Network configurations
- Resource allocations

## DNS Lookup Verification

### External DNS Resolution

**Steps:**

1. **Test cluster API endpoint resolution:**
   ```bash
   nslookup <cluster-api-url>
   dig <cluster-api-url>
   ```
   - Verify the API server URL resolves to valid AWS load balancer IPs
   - Check that DNS propagation is complete across all regions

2. **Verify application route resolution:**
   ```bash
   oc get routes --all-namespaces
   nslookup <app-route-hostname>
   ```
   - Ensure custom application routes resolve correctly
   - Test wildcard subdomain resolution for the cluster

3. **Internal cluster DNS:**
   ```bash
   oc get pods -n openshift-dns
   oc logs -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default
   ```
   - Verify CoreDNS pods are running and healthy
   - Check DNS resolution from within pods using test containers

**Explanation:** DNS is critical for both external access to your cluster and internal service discovery. ROSA uses AWS Route 53 for external DNS management, while CoreDNS handles internal cluster resolution.

### Understanding Route 53 DNS Components in ROSA HCP

#### Hosted Zones
A hosted zone is a container for DNS records for a particular domain. In ROSA HCP context:

**Public Hosted Zone:**
- Contains DNS records that resolve from the internet
- Used for cluster API endpoints and application routes
- Example: `cluster-abc123.s1.devshift.org`

**Private Hosted Zone:**
- Contains DNS records that resolve only within specific VPCs
- Used for internal service communication
- Not directly accessible from the internet

**Verification Steps:**
```bash
# List hosted zones associated with your cluster
aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, `your-cluster-domain`)]'

# Get detailed information about a specific hosted zone
aws route53 get-hosted-zone --id /hostedzone/Z1234567890ABC
```

#### A Records (Address Records)
A records map domain names directly to IPv4 addresses.

**In ROSA HCP:**
- API server endpoints use A records pointing to Application Load Balancer (ALB) IP addresses
- Worker node endpoints may use A records for direct IP resolution

**Example:**
```
api.cluster-abc123.s1.devshift.org.  300  IN  A  54.123.45.67
```

**Verification Steps:**
```bash
# Check A records for cluster API
dig A api.<cluster-domain>

# Verify A record resolution
nslookup api.<cluster-domain>

# Check all A records in the hosted zone
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC --query 'ResourceRecordSets[?Type==`A`]'
```

#### CNAME Records (Canonical Name Records)
CNAME records map domain names to other domain names (aliases).

**In ROSA HCP:**
- Application routes often use CNAME records pointing to the ingress load balancer
- Wildcard domains for applications use CNAME records
- OAuth callback URLs may use CNAME records

**Example:**
```
*.apps.cluster-abc123.s1.devshift.org.  300  IN  CNAME  router-default.apps.cluster-abc123.s1.devshift.org.
myapp.apps.cluster-abc123.s1.devshift.org.  300  IN  CNAME  router-default.apps.cluster-abc123.s1.devshift.org.
```

**Verification Steps:**
```bash
# Check CNAME records for application routes
dig CNAME *.apps.<cluster-domain>

# Verify specific application route
dig CNAME myapp.apps.<cluster-domain>

# List all CNAME records in hosted zone
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC --query 'ResourceRecordSets[?Type==`CNAME`]'
```

#### DNS Record Flow in ROSA HCP

1. **Cluster Creation:**
   - ROSA creates a public hosted zone for your cluster domain
   - NS (Name Server) records are created pointing to Route 53 name servers
   - A records are created for the API server endpoint

2. **Application Deployment:**
   - When you create routes, CNAME records are automatically created
   - These CNAME records point to the ingress controller's load balancer
   - The ingress controller handles routing to specific applications

3. **Load Balancer Integration:**
   - Application Load Balancers (ALBs) are created for ingress traffic
   - A records point to ALB IP addresses
   - Health checks ensure traffic only goes to healthy targets

**Advanced Verification Commands:**
```bash
# Check NS records to verify name server delegation
dig NS <cluster-domain>

# Trace DNS resolution path
dig +trace api.<cluster-domain>

# Check TTL values for records
dig <cluster-domain> | grep -E "IN\s+(A|CNAME)"

# Verify load balancer health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## Security Settings and Access Controls

### Identity and Access Management

**Steps:**

1. **Review cluster authentication:**
   ```bash
   oc get oauth cluster -o yaml
   oc get users
   oc get identity
   ```
   - Verify identity provider configuration (AWS IAM, LDAP, etc.)
   - Check user mapping and group synchronization

2. **Audit RBAC configurations:**
   ```bash
   oc get clusterroles
   oc get clusterrolebindings
   oc get rolebindings --all-namespaces
   ```
   - Review cluster-admin assignments
   - Verify least-privilege access principles
   - Check service account permissions

3. **Security Context Constraints (SCCs):**
   ```bash
   oc get scc
   oc describe scc restricted
   ```
   - Ensure appropriate SCCs are applied
   - Verify no unnecessary privileged access

### Network Security

**Steps:**

1. **Review security groups:**
   - In AWS Console, check security groups associated with ROSA nodes
   - Verify only necessary ports are open (443, 6443, 22, etc.)
   - Confirm source restrictions are properly configured

2. **Check network policies:**
   ```bash
   oc get networkpolicies --all-namespaces
   oc describe networkpolicy <policy-name> -n <namespace>
   ```
   - Verify micro-segmentation rules
   - Test pod-to-pod communication restrictions

**Explanation:** ROSA integrates with AWS IAM for authentication while maintaining OpenShift's RBAC model. Security groups provide network-level protection, while network policies enable application-level traffic control.

## Network Configurations

### VPC and Subnet Configuration

**Steps:**

1. **Verify VPC settings:**
   ```bash
   rosa describe cluster <cluster-name>
   ```
   - Check VPC CIDR blocks don't conflict with corporate networks
   - Verify public/private subnet distribution across AZs
   - Confirm NAT gateway configuration for private subnets

2. **Validate load balancer configuration:**
   ```bash
   oc get services -n openshift-ingress
   aws elbv2 describe-load-balancers --region <region>
   ```
   - Verify ingress controller load balancer health
   - Check SSL certificate configuration
   - Confirm cross-zone load balancing

3. **Test network connectivity:**
   ```bash
   oc run network-test --image=busybox --rm -it -- /bin/sh
   # Inside the pod:
   nslookup kubernetes.default.svc.cluster.local
   wget -qO- https://www.google.com
   ```
   - Test internal service discovery
   - Verify external internet access
   - Check connectivity to AWS services

### Service Mesh and Ingress

**Steps:**

1. **Review ingress controllers:**
   ```bash
   oc get ingresscontroller -n openshift-ingress-operator
   oc get pods -n openshift-ingress
   ```
   - Verify router pods are distributed across zones
   - Check custom domain configurations

2. **Validate service mesh (if applicable):**
   ```bash
   oc get servicemeshcontrolplane --all-namespaces
   oc get servicemeshmemberroll --all-namespaces
   ```

**Explanation:** ROSA networking leverages AWS VPC native capabilities. The hosted control plane means AWS manages the master nodes' network configuration, but worker node networking remains your responsibility.

## Resource Allocations

### Compute Resources

**Steps:**

1. **Review node capacity and utilization:**
   ```bash
   oc get nodes
   oc describe nodes
   oc adm top nodes
   ```
   - Check CPU and memory utilization across nodes
   - Verify appropriate instance types for workload requirements
   - Confirm node distribution across availability zones

2. **Analyze machine sets and autoscaling:**
   ```bash
   oc get machinesets -n openshift-machine-api
   oc get clusterautoscaler
   oc get machineautoscaler -n openshift-machine-api
   ```
   - Verify autoscaling configuration and limits
   - Check machine set replica counts
   - Review scaling policies and thresholds

### Storage Resources

**Steps:**

1. **Review storage classes and persistent volumes:**
   ```bash
   oc get storageclass
   oc get pv
   oc get pvc --all-namespaces
   ```
   - Verify default storage class configuration
   - Check EBS volume types and performance settings
   - Confirm backup and snapshot policies

2. **Validate etcd storage:**
   ```bash
   rosa describe cluster <cluster-name> | grep -i storage
   ```
   - Confirm etcd encryption at rest
   - Verify backup retention policies

### Monitoring and Observability

**Steps:**

1. **Check cluster monitoring stack:**
   ```bash
   oc get pods -n openshift-monitoring
   oc get prometheusrules -n openshift-monitoring
   ```
   - Verify Prometheus, Grafana, and Alertmanager are running
   - Check resource allocation for monitoring components
   - Review alerting rules and notification channels

2. **Review logging configuration:**
   ```bash
   oc get clusterlogging -n openshift-logging
   oc get pods -n openshift-logging
   ```
   - Verify log forwarding configuration
   - Check storage allocation for log retention

**Explanation:** Resource allocation in ROSA involves both the AWS infrastructure layer (EC2 instances, EBS volumes) and the OpenShift application layer (pods, services). Proper sizing ensures optimal performance and cost efficiency.

## Final Verification Checklist

Before concluding the review:

- [ ] All DNS queries resolve correctly from inside and outside the cluster
- [ ] Authentication and authorization work as expected
- [ ] Network policies are enforced and tested
- [ ] Resource utilization is within acceptable ranges
- [ ] Monitoring and alerting are functional
- [ ] Backup and disaster recovery procedures are verified
- [ ] Security scanning shows no critical vulnerabilities
- [ ] Documentation is updated with any configuration changes

## Additional Considerations

### Route 53 DNS Troubleshooting for ROSA HCP

#### Common DNS Issues and Resolution

**Issue: API endpoint not resolving**
```bash
# Check if hosted zone exists
aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, `your-cluster-domain`)]'

# Verify A record exists for API
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --query 'ResourceRecordSets[?Name==`api.your-cluster-domain.`]'

# Test resolution from different locations
dig @8.8.8.8 api.<cluster-domain>
dig @1.1.1.1 api.<cluster-domain>
```

**Issue: Application routes not working**
```bash
# Check ingress controller status
oc get pods -n openshift-ingress
oc get services -n openshift-ingress

# Verify route creation
oc get routes --all-namespaces
oc describe route <route-name> -n <namespace>

# Check CNAME record creation
dig CNAME <app-route-hostname>
```

**Issue: SSL certificate problems**
```bash
# Check certificate status in Route 53
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --query 'ResourceRecordSets[?Type==`CNAME` && contains(Name, `acme-challenge`)]'

# Verify certificate in AWS Certificate Manager
aws acm list-certificates --region <region>
aws acm describe-certificate --certificate-arn <cert-arn>
```

### General Troubleshooting Commands

If issues are found during the review:

#### Common DNS Issues and Resolution

**Issue: API endpoint not resolving**
```bash
# Check if hosted zone exists
aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, `your-cluster-domain`)]'

# Verify A record exists for API
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --query 'ResourceRecordSets[?Name==`api.your-cluster-domain.`]'

# Test resolution from different locations
dig @8.8.8.8 api.<cluster-domain>
dig @1.1.1.1 api.<cluster-domain>
```

**Issue: Application routes not working**
```bash
# Check ingress controller status
oc get pods -n openshift-ingress
oc get services -n openshift-ingress

# Verify route creation
oc get routes --all-namespaces
oc describe route <route-name> -n <namespace>

# Check CNAME record creation
dig CNAME <app-route-hostname>
```

**Issue: SSL certificate problems**
```bash
# Check certificate status in Route 53
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --query 'ResourceRecordSets[?Type==`CNAME` && contains(Name, `acme-challenge`)]'

# Verify certificate in AWS Certificate Manager
aws acm list-certificates --region <region>
aws acm describe-certificate --certificate-arn <cert-arn>
```

```bash
# Check cluster operators status
oc get clusteroperators

# View cluster events
oc get events --all-namespaces --sort-by='.lastTimestamp'

# Check node conditions
oc get nodes -o wide

# Review pod status across all namespaces
oc get pods --all-namespaces | grep -v Running
```

### Best Practices

1. **Regular Reviews:** Conduct this review quarterly or after major changes
2. **Documentation:** Keep configuration documentation updated
3. **Monitoring:** Set up alerts for critical metrics
4. **Security:** Regularly update and patch cluster components
5. **Backup:** Test backup and restore procedures regularly

---

This comprehensive review ensures your ROSA cluster is secure, properly configured, and ready for production workloads.
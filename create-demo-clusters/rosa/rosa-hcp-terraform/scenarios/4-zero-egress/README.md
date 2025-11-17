# Scenario 4: Zero Egress Configuration

## Overview

This scenario creates a ROSA HCP cluster with NO internet egress:
- All AWS service access via VPC endpoints (PrivateLink)
- Private ECR for container images
- Optional HTTP proxy for approved external access
- Maximum security for regulated environments

## Architecture

Private Cluster (No Internet)
↓
VPC Endpoints (PrivateLink)
├── EC2
├── ECR (API & Docker)
├── S3
├── ELB
├── STS
├── CloudWatch Logs
├── Secrets Manager
└── KMS
## Prerequisites

1. AWS account with VPC endpoint quotas
2. Red Hat ROSA subscription
3. Understanding of air-gapped deployments

## Deployment
```bash
cd scenarios/4-zero-egress

# Copy example
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
vim terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply
```

## Using Private ECR

### Push Images to ECR
```bash
# From your local machine (with internet)
AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Tag and push
docker tag myapp:latest $ECR_URL/rosa-zero-egress-images/myapp:latest
docker push $ECR_URL/rosa-zero-egress-images/myapp:latest
```

### Pull Images in OpenShift
```bash
# Create pull secret
oc create secret docker-registry ecr-pull-secret \
  --docker-server=$ECR_URL \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n default

# Link to service account
oc secrets link default ecr-pull-secret --for=pull
```

### Deploy from Private ECR
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: <account-id>.dkr.ecr.us-east-1.amazonaws.com/rosa-zero-egress-images/myapp:latest
        ports:
        - containerPort: 8080
```

## Testing Zero Egress

### Verify No Internet Access
```bash
# Deploy test pod
oc run test-pod --image=busybox --command -- sleep 3600

# Try to reach internet (should fail)
oc exec test-pod -- wget -O- https://google.com --timeout=5
# Expected: Connection timeout or DNS resolution failure

# Try to reach S3 via VPC endpoint (should work)
oc exec test-pod -- wget -O- https://s3.us-east-1.amazonaws.com --timeout=5
# Expected: XML response from S3
```

### Verify VPC Endpoints
```bash
# List VPC endpoints
aws ec2 describe-vpc-endpoints \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'VpcEndpoints[*].[ServiceName,State]' \
  --output table

# Check DNS resolution
oc run test-dns --image=busybox --command -- sleep 3600
oc exec test-dns -- nslookup ecr.us-east-1.amazonaws.com
# Should resolve to private IP in your VPC CIDR
```

## HTTP Proxy (Optional)

If you need controlled internet access:

### Enable Proxy
```hcl
enable_http_proxy = true
no_proxy = ".cluster.local,.svc,10.0.0.0/16,169.254.169.254,.amazonaws.com"
```

### Configure Pods to Use Proxy
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: app
    image: myapp:latest
    env:
    - name: HTTP_PROXY
      value: "http://<proxy-ip>:3128"
    - name: HTTPS_PROXY
      value: "http://<proxy-ip>:3128"
    - name: NO_PROXY
      value: ".cluster.local,.svc,10.0.0.0/16"
```

## Monitoring and Logging

### CloudWatch Logs via VPC Endpoint
```bash
# Logs are sent to CloudWatch via VPC endpoint
aws logs describe-log-groups --region us-east-1

# View cluster logs
aws logs tail /aws/rosa/<cluster-name> --follow
```

### Container Insights
```bash
# Enable Container Insights
oc apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
```

## Backup and Recovery

### Using S3 for Backups (via VPC Endpoint)
```bash
# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket rosa-zero-egress-data-<account-id> \
  --backup-location-config region=us-east-1 \
  --use-node-agent \
  --use-volume-snapshots=false

# Create backup
velero backup create my-backup --include-namespaces default

# Restore
velero restore create --from-backup my-backup
```

## Security Considerations

1. **No Internet Access**: Worker nodes cannot reach internet
2. **All traffic via PrivateLink**: AWS services accessed privately
3. **Private ECR**: Container images stored in private registry
4. **Encrypted Storage**: EBS, S3, ECR all encrypted
5. **VPC Flow Logs**: Enable for audit trail

## Troubleshooting

### Issue: Images Won't Pull
```bash
# Check ECR credentials
oc get secret ecr-pull-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Verify ECR VPC endpoint
aws ec2 describe-vpc-endpoints --region us-east-1 --filters "Name=service-name,Values=com.amazonaws.us-east-1.ecr.api"

# Test ECR connectivity from pod
oc run test-ecr --image=amazon/aws-cli --command -- sleep 3600
oc exec test-ecr -- aws ecr describe-repositories --region us-east-1
```

### Issue: DNS Resolution Fails
```bash
# Check CoreDNS
oc get pods -n openshift-dns

# Verify VPC DNS settings
aws ec2 describe-vpcs --vpc-ids <vpc-id> --query 'Vpcs[0].EnableDnsHostnames'
aws ec2 describe-vpcs --vpc-ids <vpc-id> --query 'Vpcs[0].EnableDnsSupport'

# Both should be true
```

### Issue: S3 Access Fails
```bash
# Verify S3 gateway endpoint
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.s3" \
  --query 'VpcEndpoints[*].VpcEndpointId'

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"
```

## Cost Optimization

- VPC Endpoints: ~$7/endpoint/month
- Data processing: $0.01/GB
- Minimize number of endpoints to only what's needed
- Use S3 gateway endpoint (free) instead of interface endpoint

## Cleanup
```bash
# Delete cluster and all resources
terraform destroy

# Verify ECR images are deleted
aws ecr list-images --repository-name rosa-zero-egress-images --region us-east-1
```

## Additional Resources

- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [ROSA Private Clusters](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa-sts-creating-a-cluster-with-customizations.html)
- [ECR Private Registry](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
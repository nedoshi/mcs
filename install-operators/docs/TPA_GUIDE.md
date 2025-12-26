# Trusted Profile Analyzer (TPA) - Installation Guide

This guide explains how to install and access Trusted Profile Analyzer (TPA) for SBOM and VEX analysis.

## Overview

Trusted Profile Analyzer (TPA) is a service that provides:
- **SBOM Analysis**: Analyze Software Bill of Materials for vulnerabilities and licenses
- **VEX Analysis**: Process Vulnerability Exploitability eXchange documents
- **Risk Scoring**: Calculate risk scores for software components
- **API Access**: RESTful API for integration with CI/CD pipelines

TPA works in conjunction with Red Hat Trusted Artifact Signer (RHTAS) to provide comprehensive software supply chain security.

## Prerequisites

1. Access to the OpenShift cluster
2. Appropriate permissions to create resources in `trustification` namespace
3. Storage class available for PVCs (10Gi for SBOM, 5Gi for VEX)

## Step 1: Install TPA

```bash
# Install TPA service (includes PVCs, deployment, service, and route)
make install-tpa
```

This will:
- Create the `trustification` namespace
- Create PVCs for SBOM (10Gi) and VEX (5Gi) storage
- Deploy TPA service
- Create service and route
- Wait for deployment to be ready

## Step 2: Get TPA Information

```bash
# Get all TPA info (route, status, API endpoints)
make tpa-info

# Or get just the route
make tpa-route
```

## Step 3: Access TPA Dashboard

### Option A: Via Route URL

```bash
# Get the route
ROUTE=$(make tpa-route)

# Access in browser
echo "TPA Dashboard: https://$ROUTE"
```

### Option B: Direct Route Access

```bash
# Get route directly
oc get route tpa-service -n trustification

# Access the URL shown in the output
```

## Step 4: Using TPA API

TPA provides a RESTful API for programmatic access:

### Health Check

```bash
TPA_URL=$(make tpa-route)
curl -k https://$TPA_URL/health
```

### Upload SBOM

```bash
TPA_URL=$(make tpa-route)

# Upload SBOM
curl -X POST https://$TPA_URL/api/v1/sbom \
  -H 'Content-Type: application/json' \
  -d @sbom.json

# Response will include SBOM ID
```

### Get Vulnerabilities

```bash
TPA_URL=$(make tpa-route)
SBOM_ID="<sbom-id-from-upload>"

# Get vulnerabilities
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/vulnerabilities | jq .

# Get vulnerabilities summary
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/vulnerabilities | \
  jq '.vulnerabilities | group_by(.severity) | map({severity: .[0].severity, count: length})'
```

### Get Licenses

```bash
TPA_URL=$(make tpa-route)
SBOM_ID="<sbom-id-from-upload>"

# Get licenses
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/licenses | jq .

# Get license summary
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/licenses | \
  jq '.licenses | group_by(.name) | map({license: .[0].name, count: length})'
```

### Get Risk Score

```bash
TPA_URL=$(make tpa-route)
SBOM_ID="<sbom-id-from-upload>"

# Get risk score
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/risk-score | jq .
```

## Integration with CI/CD

### Tekton Pipeline Example

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: analyze-sbom
spec:
  steps:
    - name: upload-sbom
      image: curlimages/curl:latest
      script: |
        TPA_URL=$(oc get route tpa-service -n trustification -o jsonpath='{.spec.host}')
        SBOM_ID=$(curl -X POST https://$TPA_URL/api/v1/sbom \
          -H 'Content-Type: application/json' \
          -d @$(workspaces.sbom.path)/sbom.json | jq -r '.id')
        echo "SBOM_ID=$SBOM_ID" > $(workspaces.results.path)/sbom-id.txt
    
    - name: check-vulnerabilities
      image: curlimages/curl:latest
      script: |
        TPA_URL=$(oc get route tpa-service -n trustification -o jsonpath='{.spec.host}')
        SBOM_ID=$(cat $(workspaces.results.path)/sbom-id.txt)
        VULNS=$(curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/vulnerabilities)
        CRITICAL=$(echo $VULNS | jq '[.vulnerabilities[] | select(.severity == "CRITICAL")] | length')
        if [ $CRITICAL -gt 0 ]; then
          echo "❌ Found $CRITICAL critical vulnerabilities"
          exit 1
        fi
```

## Troubleshooting

### PVCs Not Binding

```bash
# Check PVC status
oc get pvc -n trustification

# Check storage class
oc get storageclass

# Check PVC events
oc describe pvc tpa-sbom-pvc -n trustification
oc describe pvc tpa-vex-pvc -n trustification
```

### TPA Pod Not Starting

```bash
# Check pod status
oc get pods -n trustification -l app=tpa-service

# Check pod logs
oc logs -n trustification -l app=tpa-service --tail=100

# Check pod events
oc describe pod -n trustification -l app=tpa-service
```

### Route Not Available

```bash
# Check route
oc get route tpa-service -n trustification

# Check service
oc get svc tpa-service -n trustification

# Check endpoints
oc get endpoints tpa-service -n trustification
```

### API Not Responding

```bash
# Check health endpoint
TPA_URL=$(make tpa-route)
curl -k https://$TPA_URL/health

# Check ready endpoint
curl -k https://$TPA_URL/ready

# Check pod logs for errors
oc logs -n trustification -l app=tpa-service --tail=50
```

## Storage Management

### Check Storage Usage

```bash
# Check PVC usage
oc get pvc -n trustification

# Check actual usage (if metrics available)
oc adm top pvc -n trustification
```

### Expand Storage

If you need more storage:

1. **Edit PVC:**
   ```bash
   oc edit pvc tpa-sbom-pvc -n trustification
   # Change storage: 10Gi to desired size
   ```

2. **Or recreate with larger size:**
   ```bash
   # Delete deployment (data will be preserved in PVC)
   oc delete deployment tpa-service -n trustification
   
   # Edit PVC size
   oc edit pvc tpa-sbom-pvc -n trustification
   
   # Redeploy
   make install-tpa
   ```

## Common Commands

```bash
# Check TPA status
oc get all -n trustification

# Check TPA pods
oc get pods -n trustification -l app=tpa-service

# Check TPA route
oc get route tpa-service -n trustification

# Check PVCs
oc get pvc -n trustification

# View TPA logs
oc logs -n trustification -l app=tpa-service --tail=100 -f

# Restart TPA
oc rollout restart deployment/tpa-service -n trustification

# Get TPA URL
make tpa-route
```

## Integration with RHTAS

TPA works alongside Red Hat Trusted Artifact Signer:

1. **Sign artifacts** with RHTAS
2. **Generate SBOMs** during build
3. **Upload SBOMs** to TPA for analysis
4. **Get vulnerability reports** from TPA
5. **Use results** in policy decisions

Example workflow:

```bash
# 1. Build and sign image with RHTAS
# 2. Generate SBOM
syft image:quay.io/example/app:latest -o spdx-json > sbom.json

# 3. Upload to TPA
TPA_URL=$(make tpa-route)
SBOM_ID=$(curl -X POST https://$TPA_URL/api/v1/sbom \
  -H 'Content-Type: application/json' \
  -d @sbom.json | jq -r '.id')

# 4. Check vulnerabilities
curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/vulnerabilities | jq .

# 5. Use in policy decision
CRITICAL_VULNS=$(curl https://$TPA_URL/api/v1/sbom/$SBOM_ID/vulnerabilities | \
  jq '[.vulnerabilities[] | select(.severity == "CRITICAL")] | length')

if [ $CRITICAL_VULNS -gt 0 ]; then
  echo "Blocking deployment due to critical vulnerabilities"
  exit 1
fi
```

## Additional Resources

- [Trustification Documentation](https://github.com/trustification/trustification)
- [SBOM Standards](https://cyclonedx.org/)
- [VEX Format](https://www.cisa.gov/sites/default/files/2023-04/vex_use_cases_april_2023.pdf)

## Quick Reference

```bash
# Install TPA
make install-tpa

# Get TPA info
make tpa-info

# Get TPA route
make tpa-route

# Check TPA status
oc get deployment tpa-service -n trustification

# Get TPA URL
oc get route tpa-service -n trustification -o jsonpath='https://{.spec.host}'
```


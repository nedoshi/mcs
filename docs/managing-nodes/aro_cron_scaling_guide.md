# ARO Worker Node Scaling with Cron Job - Step-by-Step Guide

## Prerequisites
- Access to ARO cluster with cluster-admin privileges
- `oc` CLI tool installed and configured
- Basic understanding of Kubernetes RBAC and CronJobs

## Step 1: Create a Service Account

First, create a dedicated service account for the scaling operations:

```bash
# Create a new project (optional)
oc new-project worker-scaling

# Create the service account
oc create serviceaccount worker-scaler -n worker-scaling
```

## Step 2: Create RBAC Resources

Create the necessary ClusterRole and ClusterRoleBinding to grant permissions:

```yaml
# cluster-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: worker-scaler
rules:
- apiGroups: ["machine.openshift.io"]
  resources: ["machinesets"]
  verbs: ["get", "list", "patch", "update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
```

```yaml
# cluster-role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: worker-scaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: worker-scaler
subjects:
- kind: ServiceAccount
  name: worker-scaler
  namespace: worker-scaling
```

Apply the RBAC resources:

```bash
oc apply -f cluster-role.yaml
oc apply -f cluster-role-binding.yaml
```

## Step 3: Create the Scaling Script

Create a ConfigMap containing the scaling script:

```yaml
# scaling-script-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: scaling-script
  namespace: worker-scaling
data:
  scale-workers.sh: |
    #!/bin/bash
    set -e
    
    # Configuration
    DESIRED_REPLICAS=${DESIRED_REPLICAS:-3}
    MACHINESET_LABEL=${MACHINESET_LABEL:-"machine.openshift.io/cluster-api-machine-role=worker"}
    
    echo "Starting worker node scaling operation..."
    echo "Target replicas: $DESIRED_REPLICAS"
    
    # Get all worker machinesets
    MACHINESETS=$(oc get machinesets -n openshift-machine-api -l "$MACHINESET_LABEL" -o name)
    
    if [ -z "$MACHINESETS" ]; then
        echo "No worker machinesets found with label: $MACHINESET_LABEL"
        exit 1
    fi
    
    # Scale each machineset
    for MACHINESET in $MACHINESETS; do
        MACHINESET_NAME=$(echo $MACHINESET | cut -d'/' -f2)
        echo "Scaling $MACHINESET_NAME to $DESIRED_REPLICAS replicas"
        
        # Get current replicas
        CURRENT_REPLICAS=$(oc get $MACHINESET -n openshift-machine-api -o jsonpath='{.spec.replicas}')
        echo "Current replicas for $MACHINESET_NAME: $CURRENT_REPLICAS"
        
        if [ "$CURRENT_REPLICAS" != "$DESIRED_REPLICAS" ]; then
            # Scale the machineset
            oc patch $MACHINESET -n openshift-machine-api -p '{"spec":{"replicas":'$DESIRED_REPLICAS'}}' --type=merge
            echo "Scaled $MACHINESET_NAME from $CURRENT_REPLICAS to $DESIRED_REPLICAS replicas"
        else
            echo "$MACHINESET_NAME already has $DESIRED_REPLICAS replicas"
        fi
    done
    
    echo "Scaling operation completed successfully"
    
    # Wait and report status
    echo "Waiting 30 seconds before checking status..."
    sleep 30
    
    echo "Current machineset status:"
    oc get machinesets -n openshift-machine-api -l "$MACHINESET_LABEL"
    
    echo "Current node count:"
    oc get nodes --no-headers | wc -l
```

Apply the ConfigMap:

```bash
oc apply -f scaling-script-configmap.yaml
```

## Step 4: Create the CronJob

Create a CronJob that will execute the scaling script:

```yaml
# worker-scaling-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: worker-scaler
  namespace: worker-scaling
spec:
  # Schedule: Run every day at 8:00 AM (adjust as needed)
  schedule: "0 8 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: worker-scaler
          restartPolicy: OnFailure
          containers:
          - name: worker-scaler
            image: quay.io/openshift/origin-cli:latest
            command: ["/bin/bash"]
            args: ["/scripts/scale-workers.sh"]
            env:
            # Set desired number of replicas per machineset
            - name: DESIRED_REPLICAS
              value: "3"
            # Optional: Specify machineset label selector
            - name: MACHINESET_LABEL
              value: "machine.openshift.io/cluster-api-machine-role=worker"
            volumeMounts:
            - name: scaling-script
              mountPath: /scripts
            resources:
              requests:
                memory: "64Mi"
                cpu: "50m"
              limits:
                memory: "128Mi"
                cpu: "100m"
          volumes:
          - name: scaling-script
            configMap:
              name: scaling-script
              defaultMode: 0755
  # Keep last 3 successful jobs and 1 failed job
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
```

Apply the CronJob:

```bash
oc apply -f worker-scaling-cronjob.yaml
```

## Step 5: Verify the Setup

Check that all resources are created correctly:

```bash
# Verify service account
oc get serviceaccount worker-scaler -n worker-scaling

# Verify RBAC
oc get clusterrole worker-scaler
oc get clusterrolebinding worker-scaler

# Verify ConfigMap
oc get configmap scaling-script -n worker-scaling

# Verify CronJob
oc get cronjob worker-scaler -n worker-scaling
```

## Step 6: Test the CronJob

You can manually trigger the CronJob to test it:

```bash
# Create a manual job from the CronJob
oc create job --from=cronjob/worker-scaler manual-test-1 -n worker-scaling

# Check the job status
oc get jobs -n worker-scaling

# Check the pod logs
oc logs -f job/manual-test-1 -n worker-scaling
```

## Step 7: Monitor and Manage

Monitor the CronJob execution:

```bash
# Check CronJob status
oc get cronjob worker-scaler -n worker-scaling

# View recent jobs
oc get jobs -n worker-scaling

# Check logs of latest job
oc logs -l job-name=worker-scaler-$(date +%s) -n worker-scaling
```

## Configuration Options

### Schedule Examples
- `"0 8 * * *"` - Daily at 8:00 AM
- `"0 8 * * 1-5"` - Weekdays at 8:00 AM
- `"0 8,20 * * *"` - Daily at 8:00 AM and 8:00 PM
- `"*/30 * * * *"` - Every 30 minutes

### Environment Variables
- `DESIRED_REPLICAS`: Number of replicas per machineset (default: 3)
- `MACHINESET_LABEL`: Label selector for machinesets (default: worker role)

## Important Considerations

1. **Cost Management**: Scaling up increases costs. Consider scaling down during off-hours.

2. **Resource Limits**: Ensure your ARO cluster has sufficient quota for additional nodes.

3. **Gradual Scaling**: For large scale-ups, consider implementing gradual scaling to avoid resource contention.

4. **Monitoring**: Set up monitoring and alerting for scaling operations.

5. **Backup Strategy**: Consider creating a companion CronJob to scale down during off-hours.

## Creating a Scale-Down CronJob

To create a complementary scale-down job:

```yaml
# worker-scaling-down-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: worker-scaler-down
  namespace: worker-scaling
spec:
  # Schedule: Run every day at 6:00 PM
  schedule: "0 18 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: worker-scaler
          restartPolicy: OnFailure
          containers:
          - name: worker-scaler
            image: quay.io/openshift/origin-cli:latest
            command: ["/bin/bash"]
            args: ["/scripts/scale-workers.sh"]
            env:
            - name: DESIRED_REPLICAS
              value: "1"  # Scale down to 1 replica
            volumeMounts:
            - name: scaling-script
              mountPath: /scripts
          volumes:
          - name: scaling-script
            configMap:
              name: scaling-script
              defaultMode: 0755
```

## Troubleshooting

### Common Issues
1. **Permission Denied**: Verify RBAC configuration
2. **No Machinesets Found**: Check machineset labels and selectors
3. **Scaling Failures**: Check Azure quota and resource limits
4. **Job Failures**: Review pod logs for detailed error messages

### Debugging Commands
```bash
# Check machinesets
oc get machinesets -n openshift-machine-api

# Check machines
oc get machines -n openshift-machine-api

# Check nodes
oc get nodes

# Check events
oc get events -n worker-scaling --sort-by='.lastTimestamp'
```
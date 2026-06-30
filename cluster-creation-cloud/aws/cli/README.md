# ROSA CLI path

Guide: [`../docs/ai-assistant/ROSA Cluster creation agent instructions.md`](../docs/ai-assistant/ROSA%20Cluster%20creation%20agent%20instructions.md)

```bash
export RHCS_TOKEN="<https://console.redhat.com/openshift/token>"
aws sts get-caller-identity
rosa verify quota --region <region>
```

Example runner for `tf-rosa/examples/*`: [`run-example.sh`](run-example.sh)

Production IaC: [`../tf-rosa/`](../tf-rosa/).

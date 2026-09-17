# UC-02 — Pod authentication with IRSA (STS AssumeRoleWithWebIdentity)

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 2.

## Summary

Configure a workload to access AWS APIs (example: **S3**) using **IAM Roles for Service Accounts (IRSA)** and short-lived **STS** credentials—no static access keys in the pod.

## Why this matters

- Security/compliance mandates forbid long-lived keys in Kubernetes Secrets.
- Same pattern as EKS IRSA; ROSA mounts projected tokens and sets `AWS_ROLE_ARN` / `AWS_WEB_IDENTITY_TOKEN_FILE`.
- Typical for backup agents, data pipelines, and app-tier S3 access.

## Architecture

```
 [Pod] --(1) projected token--> [/var/run/secrets/.../token]
    |
    +--(2) AssumeRoleWithWebIdentity--> [AWS STS]
                ^
                | (3) JWT validated against
            [ROSA cluster OIDC issuer]
    |
    +--(4) temp creds--> S3 API
```

## Prerequisites

- Cluster OIDC provider enabled (default on STS ROSA/HCP).
- S3 bucket in cluster account for smoke test.
- IAM permissions to create role + policy.

```bash
export NAMESPACE=my-app
export SA_NAME=s3-writer-sa
export BUCKET=my-app-data-bucket
export ROLE_NAME=app-s3-role
OIDC_ID="$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.aws.sts.oidc_endpoint // .aws.sts.oidc_issuer_url' | sed 's|https://||')"
```

## Steps

1. Create IAM role trust policy (PDF example — adjust OIDC host and SA):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/OIDC_HOST" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "OIDC_HOST:sub": "system:serviceaccount:my-app:s3-writer-sa"
         }
       }
     }]
   }
   ```

2. Attach S3 policy (scoped to `${BUCKET}`).

3. Create namespace, ServiceAccount, Deployment (from PDF):

   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: s3-writer-sa
     namespace: my-app
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/app-s3-role
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: s3-uploader
     namespace: my-app
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: s3-uploader
     template:
       metadata:
         labels:
           app: s3-uploader
       spec:
         serviceAccountName: s3-writer-sa
         containers:
           - name: uploader
             image: amazon/aws-cli:latest
             command:
               - sh
               - -c
               - aws s3 cp /etc/hostname s3://${BUCKET}/test.txt && sleep 3600
   ```

4. Verify upload:

   ```bash
   oc logs -n my-app deploy/s3-uploader
   aws s3 ls "s3://${BUCKET}/" | grep test.txt
   ```

## Expected output

- Pod logs show successful `upload:` or no AccessDenied.
- Object `test.txt` visible in bucket.

## Success criteria

```bash
aws s3 ls "s3://${BUCKET}/test.txt"
oc logs -n my-app deploy/s3-uploader 2>&1 | grep -vi denied
```

## Failure signals

- `AccessDenied` on `aws s3 cp` → trust policy `sub` mismatch, wrong role ARN on SA, or bucket policy.
- No token env in pod → `oc exec` and check `AWS_ROLE_ARN`, projected volume mount.

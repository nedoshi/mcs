# IRSA Workload Identity on ROSA HCP

How customers who already use **IRSA** and/or **EKS Pod Identity** map that model onto **ROSA HCP** — plus a runnable S3 demo.

---

## TL;DR

| What you know from EKS | On ROSA HCP |
|------------------------|-------------|
| **IRSA** (OIDC + `eks.amazonaws.com/role-arn`) | **Same pattern.** Built-in. This is what you demo. |
| **EKS Pod Identity** (`pods.eks.amazonaws.com` + association API + node agent) | **Does not exist.** No port. Stay on IRSA. |
| “Pod Identity” wording on ROSA docs | Means the **aws-pod-identity-webhook** that *implements IRSA* — **not** EKS Pod Identity. |

Cluster Operators also use STS/OIDC (account + Operator roles). That is **cluster management**. App pods use the **same OIDC issuer** with **your** IAM roles — that is **workload management**.

```
┌──────────────────────────────────────────────────────────────────┐
│  EKS IRSA                         ROSA HCP (workload IRSA)       │
│  ────────                         ────────────────────────       │
│  OIDC provider (per cluster)  ≈   OIDC from rosa create          │
│  SA annotation role-arn       ≈   same annotation                │
│  Mutating webhook             ≈   pod-identity-webhook (shipped) │
│  AssumeRoleWithWebIdentity    ≈   same STS call                  │
│                                                                  │
│  EKS Pod Identity             ✗   no equivalent on ROSA          │
│  CreatePodIdentityAssociation ✗   use IAM trust + SA annotation  │
│  AWS_CONTAINER_CREDENTIALS_*  ✗   AWS_WEB_IDENTITY_TOKEN_FILE    │
└──────────────────────────────────────────────────────────────────┘
```

---

## Comparison deep-dive

### 1. EKS IRSA ≈ ROSA IRSA (what to recommend)

Both:

1. Project a bound SA JWT into the pod  
2. Trust the cluster OIDC issuer in an IAM role  
3. SDK calls `sts:AssumeRoleWithWebIdentity`  
4. Get short-lived keys — no long-lived access keys in Secrets  

| Detail | EKS IRSA | ROSA HCP IRSA |
|--------|----------|---------------|
| OIDC | Created with cluster / `eksctl` | Created with `rosa create` (required on HCP) |
| SA annotation | `eks.amazonaws.com/role-arn` | **Same** |
| Webhook | amazon/aws-pod-identity-webhook (addon or built-in) | **Included by default** on STS/HCP |
| Injected env | `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` | Same (`AWS_ARN_ROLE` also seen in some docs) |
| Token path | `/var/run/secrets/eks.amazonaws.com/serviceaccount/token` | **Same path** (webhook) |
| Trust condition | `oidc:sub` = `system:serviceaccount:ns:sa` | **Same** |
| Cross-account | Manual trust / role chaining | Same |

### 2. EKS Pod Identity (2023+) — EKS only

| Detail | EKS Pod Identity | ROSA |
|--------|------------------|------|
| Trust principal | `pods.eks.amazonaws.com` | N/A |
| Binding | `aws eks create-pod-identity-association` | N/A — use IAM trust JSON |
| Agent | Node-local EKS Pod Identity Agent | N/A |
| Cred delivery | `AWS_CONTAINER_CREDENTIALS_FULL_URI` | N/A |
| Role reuse across clusters | One trust, many associations | One trust statement per OIDC issuer (or multi-`sub`) |
| Session tags / ABAC | Native | DIY via IAM conditions |

**Customer translation:** If they standardized on Pod Identity on EKS, on ROSA they **fall back to IRSA**. Same security outcome (short-lived, SA-scoped). Different day-2 wiring (IAM trust + annotation instead of association API).

### 3. Naming trap

ROSA docs say **“pod identity webhook”**. That is the OpenShift-shipped fork of **aws-pod-identity-webhook** — the IRSA mutator. It is **not** the EKS Pod Identity service.

```bash
# Present on every ROSA STS/HCP cluster
oc get deploy -A | grep -i pod-identity
# often: openshift-cloud-credential-operator / pod-identity-webhook
```

### 4. Cluster STS vs workload IRSA

| Layer | Who | How |
|-------|-----|-----|
| Cluster / Operators | Ingress, CSI, image-registry, … | Operator IAM roles + CCO Secrets (`web_identity_token_file`) |
| Your apps | Deployments you own | Annotate SA → webhook → STS |

Same OIDC issuer; different roles and `sub` conditions.

---

## Demo: IRSA → S3 (no static keys)

```
Pod (identity-demo / awscli)
  └── ServiceAccount  annotated eks.amazonaws.com/role-arn=...
        └── webhook injects AWS_WEB_IDENTITY_TOKEN_FILE + AWS_ROLE_ARN
              └── STS AssumeRoleWithWebIdentity
                    └── IAM role → scoped S3 bucket
```

### Prerequisites

- ROSA HCP (or classic STS) cluster  
- `oc` logged in  
- `aws` CLI with IAM + S3 permissions  
- Webhook running (default)

```bash
oc get deploy -n openshift-cloud-credential-operator pod-identity-webhook
# or: oc get pods -A | grep pod-identity
```

### Deploy

```bash
cd identity/irsa-workload-identity
chmod +x deploy.sh cleanup.sh scripts/*.sh

./scripts/setup-iam.sh   # IAM role + trust + S3 bucket + SA annotation
./deploy.sh              # build app + awscli helper pod
```

### Prove it

```bash
# HTTP demo (Route)
URL=$(oc get route identity-demo -n irsa-demo -o jsonpath='{.spec.host}')
curl -s "https://${URL}/whoami" | jq .
curl -s "https://${URL}/s3" | jq .

# Interactive awscli pod
oc rsh -n irsa-demo deploy/awscli
aws sts get-caller-identity
aws s3 ls "s3://${BUCKET}/"
```

Expect `Arn` to be the IRSA role, not an IAM user / node instance profile.

### Cleanup

```bash
./cleanup.sh            # cluster resources
./scripts/teardown-iam.sh   # IAM role + optional bucket delete
```

---

## Layout

```
irsa-workload-identity/
├── README.md
├── deploy.sh
├── cleanup.sh
├── scripts/
│   ├── setup-iam.sh
│   └── teardown-iam.sh
├── apps/identity-demo/     # Node.js STS+S3 whoami API
└── manifests/
    ├── 00-namespace.yaml
    ├── 10-serviceaccount.yaml
    ├── 20-identity-demo.yaml
    └── 30-awscli.yaml
```

## References

- [ROSA — Assume IAM role for a service account](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/authentication_and_authorization/assuming-an-aws-iam-role-for-a-service-account)
- [AWS blog — Fine-grained IAM for ROSA with STS](https://aws.amazon.com/blogs/containers/fine-grained-iam-roles-for-red-hat-openshift-service-on-aws-rosa-workloads-with-sts/)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EKS IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

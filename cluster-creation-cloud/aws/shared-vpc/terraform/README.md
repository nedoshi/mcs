# ROSA HCP Cluster Automation

Terraform automation for Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Plane (HCP).
Deploys a private ROSA HCP cluster with shared VPC, customer-managed KMS encryption,
KMS-encrypted StorageClasses, and Microsoft Entra ID OIDC authentication with kubeadmin disabled.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Shared VPC Account (aws.shared_vpc_account provider)                │
│                                                                      │
│  VPC ─── Public Subnet ─── NAT Gateway ─── Internet Gateway          │
│   │                                                                  │
│   ├── Private Subnet (AZ-a) ──┐                                      │
│   ├── Private Subnet (AZ-b) ──┼── ROSA Worker Nodes                  │
│   └── Private Subnet (AZ-c) ──┘                                      │
│                                                                      │
│  Route53 Private Hosted Zones:                                       │
│   ├── <cluster>.hypershift.local              (HCP internal)         │
│   └── rosa.<cluster>.<base_dns_domain>        (ingress)              │
│                                                                      │
│  IAM Roles (Terraform):                                              │
│   ├── route53-role       → ROSASharedVPCRoute53Policy                │
│   └── vpc-endpoint-role  → ROSASharedVPCEndpointPolicy               │
│  VPC Endpoint: PrivateLink to HCP control plane                      │
├──────────────────────────────────────────────────────────────────────┤
│  Cluster Account (default aws provider)                              │
│                                                                      │
│  IAM Roles (rosa CLI):  account-roles, operator-roles, OIDC          │
│  Inline policies (Terraform):                                        │
│   ├── control-plane-operator  → sts:AssumeRole shared VPC roles      │
│   └── ingress-operator        → sts:AssumeRole shared VPC roles      │
│  KMS Key (Terraform):   etcd + node volume encryption                │
│  ROSA HCP Cluster:      private, 3 worker nodes (m5.xlarge)          │
├──────────────────────────────────────────────────────────────────────┤
│  Microsoft Entra ID (azuread provider)                               │
│                                                                      │
│  App Registration:  OIDC relying party + client secret               │
│  Service Principal: allows user sign-in                              │
│  Security Group:    admin group → cluster-admin RBAC binding         │
│  ROSA OAuth Server: OpenID Connect IdP (built-in, not external)      │
│  kubeadmin:         removed — cluster relies entirely on Entra IdP   │
└──────────────────────────────────────────────────────────────────────┘
```
This architecture defines a ROSA (Red Hat OpenShift on AWS) HCP (Hosted Control Plane) deployment using a Shared VPC model and Microsoft Entra ID for identity.
1. Shared VPC Account

* Networking:
* One VPC containing a Public Subnet, NAT Gateway, and Internet Gateway.
   * Three Private Subnets across distinct Availability Zones (AZ-a, b, c) hosting the ROSA Worker Nodes.
   * VPC Endpoint: PrivateLink connectivity to the HCP control plane.
* DNS (Route53 Private Hosted Zones):
* Internal cluster communication: <cluster>.hypershift.local.
   * Application ingress: rosa.<cluster>.<base_dns_domain>.
* IAM Roles (Terraform-managed):
* route53-role: Attached to ROSASharedVPCRoute53Policy.
   * vpc-endpoint-role: Attached to ROSASharedVPCEndpointPolicy.

2. Cluster Account

* IAM & Security:
* Managed via ROSA CLI: Account roles, operator roles, and OIDC provider.
   * Inline Policies: Grants control-plane-operator and ingress-operator permission to assume roles in the Shared VPC account.
   * Encryption: Dedicated KMS Key for etcd and worker node volumes.
* Compute:
* ROSA HCP Cluster configured as private.
   * Default footprint of 3 m5.xlarge worker nodes.

3. Identity Management (Microsoft Entra ID)

* Authentication:
* App Registration configured as an OIDC relying party with a client secret.
   * Service Principal enabled for user sign-in.
   * ROSA built-in OAuth server configured as the OpenID Connect IdP.
* Authorization (RBAC):
* Entra ID Security Group mapped to the cluster-admin role.
* Hardening:


For testing, both accounts can be the same AWS account.
See [SHARED-VPC-IAM.md](SHARED-VPC-IAM.md) for a detailed IAM roles and trust policies reference.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.4.6 | Infrastructure provisioning |
| AWS CLI | v2 | AWS resource management |
| Azure CLI (`az`) | >= 2.50 | Entra ID app registration, groups |
| rosa CLI | >= 1.2.0 | ROSA role/OIDC creation |
| oc CLI | latest | Cluster access (post-install) |
| jq | latest | JWT token inspection (testing) |
| RHCS token | — | [Get token here](https://console.redhat.com/openshift/token) |
| Azure tenant | — | `az login` or `ARM_TENANT_ID` env var |

## Module Structure

```
terraform/
├── backend.tf              # Local backend (S3 commented out for prod)
├── providers.tf            # AWS, RHCS, kubernetes, helm, azuread, null
├── variables.tf            # Root-level input variables
├── outputs.tf              # Cluster URLs, KMS ARN, cluster ID, Entra ID outputs
├── main.tf                 # Module orchestration + operator IAM policies
├── docs/
│   └── entra-id-oidc-testing-guide.md  # Post-install OIDC validation commands
├── modules/
│   ├── shared-vpc/         # VPC, subnets, NAT, hosted zones, IAM roles
│   ├── rosa-account-roles/ # Data source lookups (rosa CLI creates the actual roles)
│   ├── rosa-operator-roles/# Data source lookups for 8 operator roles
│   ├── rosa-kms/           # Customer-managed KMS key with ROSA operator policy
│   ├── rosa-cluster/       # rhcs_cluster_rosa_hcp resource
│   ├── rosa-entra-idp/     # Entra ID OIDC IdP, admin group, RBAC, kubeadmin removal
│   └── rosa-post-install/  # Demotes default gp3-csi (StorageClasses managed by GitOps)
└── environments/
    ├── us-east-1/demo1.tfvars   # Shared VPC (same-account testing)
    ├── us-east-2/demo2.tfvars   # Shared VPC (cross-account)
    └── us-west-2/demo3.tfvars   # Shared VPC (cross-account)
```

## Dependency Chain

```
Step 0:  rosa CLI   ──→ account-roles, OIDC config, operator-roles, DNS domain
                           │
Step 1a: terraform  ──→ shared_vpc + operator IAM policies
                           │  (wait 15s for IAM propagation)
Step 1b: terraform  ──→ KMS ──→ cluster
                           │
Step 2:  oc login   ──→ bastion SSH tunnel (private cluster)
                           │
Step 3:  terraform  ──→ post-install (StorageClasses)
                           │
Step 4:  az login   ──→ authenticate to Azure / Entra ID tenant
                           │
Step 5:  terraform  ──→ rosa-entra-idp (app registration, admin group,
                           │               OIDC IdP, RBAC, kubeadmin removal)
                           │
Step 6:  validation ──→ OIDC login test + RBAC verification
```

---

## Step-by-Step Testing Guide (demo1, us-east-1)

### Step 0: Create ROSA roles and OIDC config

These resources have Red Hat-managed policies that cannot be replicated in Terraform.
Terraform uses `data` sources to look them up.

```bash
# Login to ROSA
export RHCS_TOKEN="your-ocm-token"
rosa login --token=$RHCS_TOKEN

# Create account roles
rosa create account-roles --prefix demo1 --hosted-cp --mode auto -y

# Create OIDC config — save the ID from the output!
rosa create oidc-config --mode auto --managed=false -y
# Output example: "OIDC Configuration ID: 2pXXXXXXXXXXXXXXX"

# Get the installer role ARN
INSTALLER_ROLE_ARN=$(aws iam get-role \
  --role-name demo1-HCP-ROSA-Installer-Role \
  --query 'Role.Arn' --output text)

OIDC_CONFIG_ID="2pxxxxxxxxxxxxxxxx" # Output from above

# Create operator roles
rosa create operator-roles --prefix demo1 --hosted-cp \
  --oidc-config-id $OIDC_CONFIG_ID \
  --installer-role-arn $INSTALLER_ROLE_ARN \
  --mode auto -y

# Verify
rosa list account-roles | grep demo1
rosa list operator-roles | grep demo1
```

Update `oidc_config_id` in `environments/us-east-1/demo1.tfvars` with the ID from above.

### Step 0a: Reserve a DNS domain for HCP

Shared VPC HCP clusters **require** a `base_dns_domain`. The domain must be
registered with OCM under the `p3.openshiftapps.com` parent (the HCP architecture
parent for AWS). A classic ROSA domain (e.g. `p1.openshiftapps.com`) or an
unrelated custom domain will be rejected.

```bash
# Create an HCP-compatible DNS domain
rosa create dns-domain --hosted-cp

# List domains — copy the one under p3.openshiftapps.com
rosa list dns-domains
# Example output: xxxx.p3.openshiftapps.com
```

Update `base_dns_domain` in your tfvars:
```
base_dns_domain = "xxxx.p3.openshiftapps.com"
```

### Step 0b: Create IAM role for shared VPC (same-account testing)

When testing with a single AWS account, create a role that Terraform assumes
to simulate the cross-account shared VPC pattern:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam create-role --role-name ROSA-SharedVPC-TerraformRole \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": { \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\" },
      \"Action\": \"sts:AssumeRole\"
    }]
  }"

aws iam attach-role-policy --role-name ROSA-SharedVPC-TerraformRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Update `shared_vpc_role_arn` in `demo1.tfvars`:
```
shared_vpc_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/ROSA-SharedVPC-TerraformRole"
```

### Step 1: Deploy infrastructure + cluster

Deployment is split into two stages to allow IAM policy propagation before
the cluster creation validates role access.

```bash
cd terraform
export TF_VAR_rhcs_token=$(rosa token)

# Initialize
terraform init

# --- Stage 1a: VPC, hosted zones, IAM roles, operator policies ---
terraform apply -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.shared_vpc \
  -target=aws_iam_role_policy.operator_assume_shared_vpc

# Wait for IAM propagation (trust policies + inline policies)
sleep 15

# --- Stage 1b: Cluster ---
terraform apply -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_account_roles \
  -target=module.rosa_operator_roles \
  -target=module.rosa_kms \
  -target=module.rosa_cluster
```

Stage 1b takes ~20-30 minutes (cluster creation is the bottleneck).

**Why two stages?** ROSA validates that all shared VPC IAM roles are
assumable before starting cluster creation. If the trust policy or operator
inline policy was just created in the same Terraform run, AWS IAM eventual
consistency may cause the validation to fail. The 15-second pause ensures
propagation.

### Step 2: Access the private cluster via bastion (unchanged)

The cluster API is private (not reachable from the internet). Set up an SSH
tunnel through a bastion host in the VPC.

```bash
# Find the VPC and public subnet
VPC_ID=$(terraform output -raw -state=terraform.tfstate 2>/dev/null || \
  aws ec2 describe-vpcs --filters "Name=tag:Name,Values=demo1-shared-vpc" \
  --query "Vpcs[0].VpcId" --output text)

PUBLIC_SUBNET=$(aws ec2 describe-subnets --filters \
  "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[0].SubnetId" --output text)

# Create key pair (skip if already exists)
aws ec2 create-key-pair --key-name demo1-bastion \
  --query "KeyMaterial" --output text > ~/.ssh/demo1-bastion.pem
chmod 600 ~/.ssh/demo1-bastion.pem

# Create security group
MY_IP=$(curl -s https://checkip.amazonaws.com)
SG_ID=$(aws ec2 create-security-group --group-name demo1-bastion-sg \
  --description "Bastion SSH" --vpc-id $VPC_ID --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr "${MY_IP}/32"

# Launch bastion (Amazon Linux 2023, t3.micro)
AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)

INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t3.micro \
  --key-name demo1-bastion --subnet-id $PUBLIC_SUBNET \
  --security-group-ids $SG_ID --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=demo1-bastion}]" \
  --query "Instances[0].InstanceId" --output text)

# Wait for it to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
BASTION_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "Bastion IP: $BASTION_IP"

# Start SOCKS proxy (runs in background)
ssh -o StrictHostKeyChecking=no -i ~/.ssh/demo1-bastion.pem \
  -D 1080 -f -N ec2-user@$BASTION_IP
```

#### Option B: sshuttle (recommended for browser + CLI access)

`sshuttle` creates a transparent VPN over SSH — no per-command `HTTPS_PROXY` needed
and browser access works out of the box.

```bash
# Install (macOS)
brew install sshuttle

# Start sshuttle (uses sudo for firewall rules — enter your local password)
# Replace VPC_CIDR with the VPC CIDR from your tfvars (e.g. 10.220.228.0/24)
# --dns forwards DNS through the bastion so private Route 53 hosted zone names resolve
sudo sshuttle -r ec2-user@$BASTION_IP \
  --ssh-cmd 'ssh -i /Users/$USER/.ssh/demo1-bastion.pem -o StrictHostKeyChecking=no' \
  10.220.228.0/24 --dns
```

> **Note:** Use the absolute path to the SSH key (not `~/.ssh/`) because `sudo`
> runs as root and `~` would expand to `/var/root`.

When sshuttle is running, all traffic to the VPC CIDR is routed through the
bastion. You can use `oc`, `curl`, and the browser directly — no proxy
environment variables required.

### Step 3: Log in to the cluster

```bash
# Create cluster admin
rosa create admin --cluster demo1
# Save the password from the output!

# Wait ~1-2 minutes for the admin to propagate, then:

# --- If using SOCKS proxy (Option A): ---
HTTPS_PROXY=socks5://localhost:1080 oc login \
  https://api.demo1.<domain>.openshiftapps.com:443 \
  --username cluster-admin --password <PASSWORD> \
  --insecure-skip-tls-verify

# --- If using sshuttle (Option B): ---
oc login https://api.demo1.<domain>.openshiftapps.com:443 \
  --username cluster-admin --password <PASSWORD> \
  --insecure-skip-tls-verify

# Verify
oc get nodes
oc get clusterversion
```

### Step 4: Apply post-install — Demote default StorageClass

```bash
cd terraform
export TF_VAR_rhcs_token=$(rosa token)
export HTTPS_PROXY=socks5://localhost:1080  # skip if using sshuttle

terraform apply -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_post_install

# Verify gp3-csi is no longer default
oc get storageclass
```

> **Note:** KMS-encrypted StorageClasses (`gp3-csi-kms`, `gp3-csi-kms-retain`) are
> managed by the GitOps `rosa-platform-config` Helm chart in `gitops/charts/rosa-platform-config`.
> They will be deployed automatically once the cluster is imported into ACM and the
> Argo CD ApplicationSets are applied. See `gitops/README.md` for the full Day 2 setup.

### Step 5: Authenticate to Microsoft Entra ID

The Entra ID OIDC module uses the `azuread` Terraform provider, which requires
Azure authentication. Choose one of the following methods:

```bash
# Option A: Azure CLI (recommended for interactive use)
az login
az account show   # confirm correct tenant

# Option B: Service principal (recommended for CI/CD)
export ARM_TENANT_ID="your-tenant-id"
export ARM_CLIENT_ID="your-sp-client-id"
export ARM_CLIENT_SECRET="your-sp-secret"
```

Identify the Entra ID Object IDs of users who should receive `cluster-admin`
access. These go into `entra_admin_group_member_object_ids` in your tfvars.

```bash
# Look up a user's Object ID
az ad user show --id user@example.com --query id -o tsv
```

### Step 6: Deploy Entra ID OIDC Identity Provider

The module supports two modes controlled by `manage_entra_resources` in your
tfvars:

| Mode | `manage_entra_resources` | Graph API Permissions Needed | What Terraform Creates |
|------|--------------------------|------------------------------|------------------------|
| **A — Fully managed** | `true` (default) | `Application.ReadWrite.All`, `Group.ReadWrite.All` | App registration, service principal, secret, group, IdP, RBAC |
| **B — Pre-created** | `false` | None | IdP + RBAC only (app & group created manually) |

> **WARNING:** Once `kubeadmin` is deleted, the **only** way to administer the
> cluster is through the Entra ID IdP. Ensure at least one user Object ID is in
> `entra_admin_group_member_object_ids` before applying.

#### Mode A: Fully managed (Terraform creates Entra ID resources)

Requires the Terraform service principal to have `Application.ReadWrite.All` and
`Group.ReadWrite.All` Microsoft Graph API permissions with admin consent.

```bash
cd terraform
export TF_VAR_rhcs_token=$(rosa token)
export HTTPS_PROXY=socks5://localhost:1080  # skip if using sshuttle

terraform plan -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_entra_idp

# Expected resources:
#   azuread_application, azuread_service_principal, azuread_application_password
#   azuread_group, azuread_group_member
#   rhcs_identity_provider, kubernetes_cluster_role_binding

terraform apply -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_entra_idp
```

#### Mode B: Pre-created Entra ID resources (no Graph permissions required)

Use this when the Terraform service principal lacks Graph API permissions.
Create the app registration and security group manually, then let Terraform
configure the ROSA IdP and RBAC binding.

**Step B.1 — Create app registration in Azure Portal:**

1. **Entra ID** > **App registrations** > **New registration**
   - Name: `<cluster_name>-rosa-oidc`
   - Supported account types: **Single tenant**
   - Redirect URI (Web): `https://oauth.<apps_domain>/oauth2callback/Entra-ID`
2. **Authentication** > **Implicit grant** > enable **ID tokens**
3. **Token configuration** > **Add optional claim** > ID token: `email`, `preferred_username`
4. **API permissions** > Add: `openid`, `email`, `profile`, `User.Read` (Delegated)
5. **Certificates & secrets** > **New client secret** (1 year) — copy the **Value**

**Step B.2 — Create security group:**

1. **Entra ID** > **Groups** > **New group**
   - Type: Security
   - Name: `demo1-ROSA-Cluster-Admins`
2. Add members to the group

**Step B.3 — Fill in tfvars:**

```hcl
manage_entra_resources               = false
entra_existing_tenant_id             = "<your-tenant-id>"
entra_existing_client_id             = "<app-client-id>"
entra_existing_client_secret         = "<client-secret-value>"
entra_existing_admin_group_object_id = "<group-object-id>"
```

**Step B.4 — Apply:**

```bash
cd terraform
export TF_VAR_rhcs_token=$(rosa token)
export HTTPS_PROXY=socks5://localhost:1080  # skip if using sshuttle

terraform plan -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_entra_idp

# Expected resources (no azuread_* resources):
#   rhcs_identity_provider, kubernetes_cluster_role_binding

terraform apply -var-file=environments/us-east-1/demo1.tfvars \
  -target=module.rosa_entra_idp
```

### Step 7: Validate OIDC Login and Admin Permissions

See [docs/entra-id-oidc-testing-guide.md](docs/entra-id-oidc-testing-guide.md)
for the full validation checklist. Quick smoke test:

```bash
# If using SOCKS proxy, prefix each oc command with: HTTPS_PROXY=socks5://localhost:1080
# If using sshuttle, no prefix needed — commands below assume sshuttle.

# 1. Confirm the IdP is registered
rosa list idps -c demo1
# Expected: "Entra-ID" with Type = OpenID

# 2. Confirm kubeadmin is gone
oc get secret kubeadmin -n kube-system
# Expected: NotFound

# 3. Log in via OIDC (opens browser — sshuttle recommended for this step)
oc login https://api.demo1.<domain>.openshiftapps.com:443 --web
# Select "Entra-ID", authenticate with an admin-group member account

# 4. Verify identity and permissions
oc whoami
oc auth can-i '*' '*' --all-namespaces
# Expected: yes

# 5. Verify the ClusterRoleBinding
oc get clusterrolebinding entra-id-cluster-admins
```

---

## Cleanup

> **Note:** If `kubeadmin` has been deleted and the Entra ID IdP is your only
> authentication method, you must be logged in as an Entra admin-group member
> (via `oc login --web`) before running destroy, so that Terraform's Kubernetes
> provider can delete the ClusterRoleBinding.

```bash
cd terraform
export TF_VAR_rhcs_token=$(rosa token)
export HTTPS_PROXY=socks5://localhost:1080  # skip if using sshuttle

# Destroy in reverse order
terraform destroy -var-file=environments/us-east-1/demo1.tfvars

# Terminate bastion
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 delete-security-group --group-id $SG_ID
aws ec2 delete-key-pair --key-name demo1-bastion
rm -f ~/.ssh/demo1-bastion.pem

# Clean up rosa CLI resources
rosa delete operator-roles --prefix demo1 --mode auto -y
rosa delete oidc-config --oidc-config-id <OIDC_CONFIG_ID> --mode auto -y
rosa delete account-roles --prefix demo1 --mode auto -y

# Clean up the testing IAM role
aws iam detach-role-policy --role-name ROSA-SharedVPC-TerraformRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name ROSA-SharedVPC-TerraformRole
```

`terraform destroy` automatically handles the Entra ID resources (app
registration, service principal, client secret, admin group). If destroy
fails partway, you can manually clean up:

```bash
# List and delete the Entra ID app registration
az ad app list --display-name "demo1-rosa-oidc" --query "[].appId" -o tsv
az ad app delete --id <app_id>

# Delete the admin group
az ad group delete --group "demo1-ROSA-Cluster-Admins"
```

## Outputs

| Output | Description |
|--------|-------------|
| cluster_id | ROSA cluster ID |
| cluster_api_url | Cluster API endpoint |
| cluster_console_url | Web console URL |
| kms_key_arn | Customer-managed KMS key ARN |
| oidc_config_id | OIDC configuration ID |
| entra_app_client_id | Entra ID application (client) ID for OIDC |
| entra_admin_group_object_id | Object ID of the Entra admin group |
| entra_tenant_id | Entra ID tenant ID used in the OIDC issuer |
| entra_idp_name | Name of the IdP on the ROSA login page |

## DNS Wildcard Record

With the correct hosted zone naming (`rosa.<cluster>.<base_domain>` for ingress),
ROSA HCP automatically creates the `*.apps` wildcard CNAME record in the ingress
zone during cluster creation. No manual DNS fix is required.

> **Note:** Earlier iterations of this automation used `apps.<cluster>.hypershift.local`
> as the ingress zone, which caused a DNS zone shadowing problem requiring a manual
> wildcard fix. This is no longer needed with the correct zone naming convention.

## Important: Always Plan Before Apply

**Never run `terraform apply -auto-approve` without reviewing the plan first.**
Terraform may mark resources as "tainted" from previous failed operations, which
causes them to be destroyed and recreated — including the cluster itself. Always:

1. Run `terraform plan` and review the output
2. Verify **0 resources to destroy** (unless you intend destruction)
3. Check that no resources show "tainted, so must be replaced"
4. Only then run `terraform apply`

If you see a tainted resource, untaint it first:
```bash
terraform untaint <resource_address>
```

## Entra ID OIDC — Security Considerations

| Topic | Detail |
|-------|--------|
| **Authentication model** | The cluster's **built-in OAuth server** is used (`external_auth_providers_enabled = false`). Entra ID is registered as an OpenID Connect identity provider on that server. This avoids external auth bypass and keeps the ROSA-managed OAuth in the loop. |
| **kubeadmin removal** | Once the Entra IdP and `cluster-admin` RBAC binding are confirmed, the `kubeadmin` secret in `kube-system` is deleted. The cluster can then **only** be administered by Entra ID group members. |
| **Break-glass recovery** | If all Entra admin-group members are locked out, use `rosa create admin -c <cluster>` via the ROSA CLI (requires the OCM token, not cluster credentials) to create a temporary admin and regain access. |
| **Client secret rotation** | The Entra app's client secret has a 1-year expiry (`end_date_relative = "8760h"`). Set a calendar reminder to run `terraform apply` to rotate it before expiry, or shorten the TTL in the module. |
| **Group overage** | Entra ID includes a maximum of 200 group Object IDs in the `groups` token claim. If a user belongs to more than 200 groups, the claim is replaced with an overage indicator and OIDC group mapping will fail for that user. Mitigate by configuring group filtering on the app registration in the Azure portal. |
| **Sensitive state** | The Entra client secret (`azuread_application_password`) is stored in Terraform state. Use an encrypted backend (S3 + KMS, Terraform Cloud, etc.) in production. |

## Notes

- Backend is **local** for testing. Uncomment S3 backend in `backend.tf` for production.
- Account roles, OIDC, and operator roles are created by `rosa` CLI. Terraform only looks them up via data sources.
- Post-install (Step 4) requires cluster API access via the SOCKS tunnel or sshuttle. It must be a separate apply stage.
- Entra ID IdP (Step 6) also requires the SOCKS tunnel or sshuttle for the Kubernetes provider to create the ClusterRoleBinding and for the `null_resource` to run `oc delete secret kubeadmin`.
- Provider versions are pinned to `~> major.minor` for compatibility with Terraform v1.5.x.
- The `azuread` provider authenticates via Azure CLI, service principal, or managed identity. See [azuread provider docs](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs#authenticating-to-azure-active-directory) for details.

## Shared VPC IAM Reference

See [SHARED-VPC-IAM.md](SHARED-VPC-IAM.md) for a complete reference of all
IAM roles, trust policies, permissions policies, and hosted zone naming
conventions required for ROSA HCP shared VPC deployments.

## DNS Domain Compatibility

ROSA HCP clusters on AWS use `p3.openshiftapps.com` as their architecture parent
domain. The `base_dns_domain` (mandatory for shared VPC clusters) must be a
subdomain reserved under this parent via `rosa create dns-domain --hosted-cp`.

| Domain type | Example | HCP compatible? |
|-------------|---------|-----------------|
| HCP domain (p3) | `xxxx.p3.openshiftapps.com` | Yes |
| Classic ROSA (p1) | `xxxx.p1.openshiftapps.com` | No |
| Custom domain | `example.com` | No |

### Hosted Zone Naming

ROSA HCP validates that the private hosted zone names match the cluster's domain
structure. The required pattern is:

| Zone | Name pattern | Example |
|------|-------------|---------|
| HCP internal | `<cluster_name>.hypershift.local` | `demo1.hypershift.local` |
| Ingress | `rosa.<cluster_name>.<base_dns_domain>` | `rosa.demo1.xxxx.p3.openshiftapps.com` |

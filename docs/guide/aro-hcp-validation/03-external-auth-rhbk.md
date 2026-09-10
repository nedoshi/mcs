# ARO HCP Validation — External Authentication (RHBK)

Port of [RHAC ARO HCP external auth](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html) with MCS script paths.

> Unlike classic ARO, external auth is **mandatory** — there is no cluster OAuth server to configure via `OAuth` CR.

## Prerequisites

- Cluster provisioned ([02-provision-azure-cli.md](02-provision-azure-cli.md))
- Admin kubeconfig active ([04-admin-credential.md](04-admin-credential.md))
- RHBK realm `openshift` with clients `openshift-console` and `openshift-cli`
- RHBK network-accessible from ARO HCP cluster

## Step 1 — Environment variables

```bash
source docs/guide/aro-hcp-validation/scripts/env.sh

export FRONTEND_HOST=$(az cloud show --query endpoints.resourceManager --output tsv)

export OPENSHIFT_API_URL=$(az rest --method GET \
  --uri "/subscriptions/${ARO_SUBSCRIPTION_ID}/resourceGroups/${ARO_RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${ARO_CLUSTER_NAME}?api-version=${FRONTEND_API_VERSION}" \
  | jq -r '.properties.apiServer.url')
```

## Step 2 — Update RHBK redirect URIs

Get console host (requires admin kubeconfig):

```bash
export KUBECONFIG=docs/guide/aro-hcp-validation/scripts/aro-cluster.kubeconfig

CONSOLE_HOST=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}')
echo "https://${CONSOLE_HOST}/auth/callback"
```

Add this redirect URI to the RHBK `openshift-console` client.

## Step 3 — Deploy external auth Bicep template

Template: [scripts/externalauth.bicep](scripts/externalauth.bicep)

```bash
cd docs/guide/aro-hcp-validation/scripts

az deployment group create \
  --name aro-hcp-auth \
  --subscription "${ARO_SUBSCRIPTION_ID}" \
  --resource-group "${ARO_RESOURCE_GROUP}" \
  --template-file externalauth.bicep \
  --parameters \
    externalAuthName="${EXTERNAL_AUTH_NAME}" \
    issuerURL="${RHBK_HOST}/realms/openshift" \
    issuerAudiences='("openshift-console", "openshift-cli")' \
    usernameClaim="preferred_username" \
    cliClientID="openshift-cli" \
    consoleClientID="openshift-console" \
    clusterName="${ARO_CLUSTER_NAME}" \
    extraScopes='("profile")'
```

> **Note:** First value in `issuerAudiences` must be the OpenShift Web Console OAuth client ID (`openshift-console`).

External auth may take **several minutes** to become active. Mark **PA-06** after deployment succeeds.

## Step 4 — Console client secret

Secret naming convention: `{externalAuthName}-console-openshift-console`

1. In RHBK realm `openshift` → Clients → `openshift-console` → Credentials tab
2. Copy client secret
3. Create cluster secret:

```bash
oc create secret generic "${EXTERNAL_AUTH_NAME}-console-openshift-console" \
  --namespace openshift-config \
  --from-literal=clientSecret="<openshift_console_client_secret>"
```

Mark **PA-07** when secret exists.

## Step 5 — RBAC for external identities

Grant cluster-admin to RHBK group `openshift_admins` (adjust to your realm):

```bash
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: openshift_admins
EOF
```

Ensure test users in RHBK belong to `openshift_admins`. Mark **PA-08**.

## Step 6 — Validate user access

### Web console (PA-09)

Open `https://${CONSOLE_HOST}` and authenticate via RHBK. Confirm dashboard loads for non-admin test user with expected RBAC.

### CLI (PA-10)

Follow [RHAC — Accessing OpenShift with External Credentials](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/06-access.html):

- Method 1: `oc login` with OIDC token from RHBK
- Verify: `oc whoami` returns RHBK username (not `system:admin`)

## RHBK parameter reference

| Bicep parameter | RHBK source |
|-----------------|-------------|
| `issuerURL` | Realm settings → OpenID Endpoint Configuration → `issuer` |
| `usernameClaim` | Use `preferred_username` for RHBK |
| `consoleClientID` | Client `openshift-console` |
| `cliClientID` | Client `openshift-cli` |
| `issuerAudiences` | Console client ID first, then CLI client ID |

## Troubleshooting

See [ARO-HCP-External-auth.md](../../troubleshooting/ARO/ARO-HCP-External-auth.md).

## Next step

[05-smoke-tests.md](05-smoke-tests.md)

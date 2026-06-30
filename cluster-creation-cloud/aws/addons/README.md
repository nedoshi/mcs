# Post-install addons

Standalone — none create a cluster or VPC.

## Platform

| Directory | Purpose |
|-----------|---------|
| `dns-private-hosted-zone/` | Private Route53 zone → ingress NLB |
| `idp-azure-ad/` | Azure AD via `rhcs_identity_provider` |
| `keycloak/` | Keycloak operator (YAML + scripts) |
| `operators/helm-values/` | Helm values (OperatorHub / Loki) |
| `operators/gitops-manifests/` | GitOps operator subscriptions |

## AI stack

| Directory | Purpose |
|-----------|---------|
| `openshift-ai/` | → [`../docs/ai-stack/OpenShift AI setup.md`](../docs/ai-stack/OpenShift%20AI%20setup.md) |
| `llama-stack/` | → [`../docs/ai-stack/Llama Stack OpenShift AI Integration Guide.md`](../docs/ai-stack/Llama%20Stack%20OpenShift%20AI%20Integration%20Guide.md) |
| `agentic-ai-demo/` | Upstream `rhai-agentic-demo` not published — see README |
| `devspaces/` | Devfile / DevWorkspace samples |
| `code-server-workbench/` | Code-server + vLLM manifests |

Upstream: [rosa-llm-driven-deployment](https://github.com/manu-joy/rosa-llm-driven-deployment). Optional UI: `rosa_agent/` in that repo.

```bash
terraform -chdir=../tf-rosa output cluster_id
```

Install order: cluster → operators (if needed) → OpenShift AI → Llama Stack.

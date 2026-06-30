# AWS ROSA HCP

Aligned with [rosa-llm-driven-deployment](https://github.com/manu-joy/rosa-llm-driven-deployment). Index: [`docs/README.md`](docs/README.md).

## Installation patterns (independent)

| Pattern | Path |
|---------|------|
| **ROSA HCP** | [`tf-rosa/`](tf-rosa/) |
| **Zero egress** | [`cluster-zero-egress/`](cluster-zero-egress/) |
| **Classic** | [`legacy/rosa-classic-private-public-dns/`](legacy/rosa-classic-private-public-dns/) |

```bash
cd tf-rosa
make init
make plan TFVARS=examples/external-auth.tfvars.example
```

AI-assisted: [`docs/ai-assistant/`](docs/ai-assistant/).

### ROSA terraform tfvars

| File | Scenario |
|------|----------|
| `examples/standard.tfvars.example` | Public HCP |
| `examples/external-auth.tfvars.example` | External auth + [`docs/ENTRA-ID-SETUP.md`](tf-rosa/docs/ENTRA-ID-SETUP.md) |

Standalone example roots: `tf-rosa/examples/rosa-hcp-{public,private,...}/`.

## Post-install addons

[`addons/README.md`](addons/README.md) — DNS, IdP, Keycloak, operators, AI guides (in `docs/ai-stack/`), devspaces, code-server.

**GitOps:** `tf-rosa` `deploy_openshift_gitops` **or** `addons/operators/gitops-manifests/` — one per cluster.

## Rules

1. No Terraform `source =` between pattern folders or addons.
2. One pattern per cluster name.
3. Other cloud submodules: `git submodule update --init --recursive`

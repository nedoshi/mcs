# Examples

Sample Kubernetes/OpenShift manifests and configs for reference and reuse.

## yaml/

Example YAML files covering:

- **GitOps / Argo CD** — `argocd.yaml`, `configmap-argocd-cm.yaml`, `secret-argocd-secret.yaml`
- **Auth** — `auth_gateway.yaml`, `auth-virtualservice.yaml`, `authz_policy.yaml`, `request_auth.yaml`
- **Backup (OADP/Velero)** — `dpa-azure-rbac.yaml`, `cloud-credentials-azure.yaml`, `credentials-velero`
- **Service mesh** — `smcp.yaml`, `smp.yaml`, `kiali-openid-auth.yaml`
- **Networking** — `privatelink-with-network-firewall.yaml`, `nodenetworkstate-worker01.yaml`
- **Other** — `deploy-rhoai.yaml`, `install-nvidia.yaml`, `pod.yaml`, `daemonset.yaml`, `virtualmachine-rosa2003-vm.yaml`, etc.

Use as reference only; adjust namespaces, names, and secrets for your environment.

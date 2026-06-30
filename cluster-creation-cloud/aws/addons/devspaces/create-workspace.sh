#!/bin/bash
set -euo pipefail

VLLM_ENDPOINT="https://qwen3-coder-neuron-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com"
MODEL_ID="qwen3-coder"

for USER_NUM in 1 2 3; do
  USERNAME="dev-user${USER_NUM}"
  NS="${USERNAME}-devspaces"
  
  echo "=== Creating workspace for ${USERNAME} in ${NS} ==="

  cat <<HEREDOC | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: llm-extension-config
  namespace: ${NS}
data:
  configure-extensions.sh: |
    #!/bin/bash
    echo "Configuring LLM extensions for ${VLLM_ENDPOINT}..."
    
    CONTINUE_DIR="\${HOME}/.continue"
    mkdir -p "\${CONTINUE_DIR}"
    
    cat > "\${CONTINUE_DIR}/config.yaml" <<'INNEREOF'
    models:
      - name: Qwen3-Coder (Inferentia2)
        provider: openai
        model: ${MODEL_ID}
        apiBase: ${VLLM_ENDPOINT}/v1
        apiKey: EMPTY
    tabAutocompleteModel:
      title: Qwen3-Coder Autocomplete
      provider: openai
      model: ${MODEL_ID}
      apiBase: ${VLLM_ENDPOINT}/v1
      apiKey: EMPTY
      debounceDelay: 500
    INNEREOF
    
    echo "Continue configured"
  vllm-endpoint: "${VLLM_ENDPOINT}"
  model-id: "${MODEL_ID}"
HEREDOC

  cat <<HEREDOC | oc apply -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: llm-coding-workspace
  namespace: ${NS}
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: false
  routingClass: che
  template:
    components:
      - name: dev-tools
        container:
          image: registry.redhat.io/devspaces/udi-rhel8:latest
          memoryLimit: 4Gi
          memoryRequest: 512Mi
          cpuLimit: "2"
          cpuRequest: 250m
          mountSources: true
          env:
            - name: VLLM_ENDPOINT
              value: "${VLLM_ENDPOINT}"
            - name: VLLM_MODEL_ID
              value: "${MODEL_ID}"
    commands:
      - id: test-model
        exec:
          component: dev-tools
          commandLine: 'curl -sk "\${VLLM_ENDPOINT}/v1/models" | python3 -m json.tool'
          label: Test Model Endpoint
  contributions:
    - name: editor
      uri: "https://eclipse-che.github.io/che-plugin-registry/main/v3/plugins/che-incubator/che-code/latest/devfile.yaml"
HEREDOC

  echo "  Done for ${USERNAME}"
done

echo ""
echo "All workspaces created. Users can access Dev Spaces at:"
echo "  https://devspaces.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com"

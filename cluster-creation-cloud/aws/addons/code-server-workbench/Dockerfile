FROM codercom/code-server:latest

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    git curl jq wget unzip \
    nodejs npm \
    && curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz" \
       -o /tmp/oc.tar.gz \
    && tar xzf /tmp/oc.tar.gz -C /usr/local/bin oc kubectl \
    && rm /tmp/oc.tar.gz \
    && curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
       -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER 1000

RUN code-server --install-extension saoudrizwan.claude-dev \
    && code-server --install-extension continue.continue \
    && code-server --install-extension ms-python.python \
    && code-server --install-extension eamodio.gitlens

COPY --chown=1000:1000 settings.json /home/coder/.local/share/code-server/User/settings.json
COPY --chown=1000:1000 continue-config.json /home/coder/.continue/config.json

ENV VLLM_ENDPOINT="https://vllm-dual-pvc-test-llm-serving.apps.rosa.CLUSTER_DOMAIN"
ENV MODEL_NAME="qwen3-coder"

EXPOSE 8080

#!/bin/bash
# Helper script to generate Argo CD Application manifests

ENV=$1
OUTPUT_FILE=$2

if [ "$ENV" = "prod" ]; then
    PRUNE="false"
else
    PRUNE="true"
fi

cat > "$OUTPUT_FILE" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: operators-${ENV}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: \$(ARGOCD_REPO_URL)
    targetRevision: \$(ARGOCD_REVISION)
    path: install-operators/overlays/${ENV}
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-operators
  syncPolicy:
    automated:
      prune: ${PRUNE}
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  healthChecks:
    - apiVersion: operators.coreos.com/v1alpha1
      kind: ClusterServiceVersion
      namespace: openshift-operators
      name: openshift-pipelines-operator.*
    - apiVersion: operators.coreos.com/v1alpha1
      kind: ClusterServiceVersion
      namespace: openshift-operators
      name: trusted-artifact-signer-operator.*
    - apiVersion: operators.coreos.com/v1alpha1
      kind: ClusterServiceVersion
      namespace: rhacs-operator
      name: rhacs-operator.*
    - apiVersion: operators.coreos.com/v1alpha1
      kind: ClusterServiceVersion
      namespace: redhat-ods-operator
      name: rhods-operator.*
    - apiVersion: operators.coreos.com/v1alpha1
      kind: ClusterServiceVersion
      namespace: openshift-cnv
      name: kubevirt-hyperconverged-operator.*
EOF


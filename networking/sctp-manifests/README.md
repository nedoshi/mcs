# Manifests and scripts for ROSA HCP SCTP enablement testing (nddemo).
#
# Layout:
#   01-tuning/           Approach 1 — TuningConfig / Tuned
#   02-daemonset/        Approach 2 — privileged module loader
#   03-kmm/              Approach 3 — KMM (optional; not needed for in-tree SCTP)
#   04-connectivity-tests/
#   05-machineconfig/    NodePool spec.config (needs management cluster)
#   TEST_RESULTS.md      What was tested on nddemo and recommended changes
#
# Quick start (Variant A blacklist — preferred on ROSA HCP 4.19):
#   ./01-tuning/apply-tuning-config.sh
#   oc apply -f 04-connectivity-tests/
#
# DaemonSet (blacklist clear + modules-load.d persistence):
#   oc apply -f 02-daemonset/01-namespace.yaml
#   oc apply -f 02-daemonset/01-serviceaccount.yaml
#   oc apply -f 02-daemonset/02-scc-rbac.yaml
#   oc apply -f 02-daemonset/03-daemonset.yaml

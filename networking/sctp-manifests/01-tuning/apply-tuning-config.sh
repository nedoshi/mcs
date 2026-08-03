#!/usr/bin/env bash
# Helper: apply Approach 1 TuningConfig on ROSA HCP via rosa CLI
set -euo pipefail

CLUSTER="${CLUSTER:-nddemo}"
NAME="${NAME:-sctp-module}"
SPEC="${SPEC:-$(dirname "$0")/sctp-tuning-spec.json}"
POOL="${POOL:-workers}"

echo "Creating TuningConfig ${NAME} on cluster ${CLUSTER} from ${SPEC}"
rosa create tuning-config --cluster="${CLUSTER}" --name="${NAME}" --spec-path="${SPEC}" -y

echo "Associating TuningConfig with machine pool ${POOL}"
rosa edit machinepool "${POOL}" --cluster="${CLUSTER}" --tuning-configs="${NAME}" -y

echo "Current machine pool:"
rosa describe machinepool "${POOL}" --cluster="${CLUSTER}"

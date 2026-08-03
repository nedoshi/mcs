#!/usr/bin/env bash
# Save as: run-sctp-tests.sh
set -euo pipefail

NAMESPACE="${NAMESPACE:-sctp-test}"
PASS=0
FAIL=0

test_result() {
  if [ "$1" -eq 0 ]; then
    echo "  PASS: $2"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $2"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== SCTP Validation Test Suite ==="
echo ""

echo "[1/6] Checking SCTP kernel module..."
NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
if oc debug "node/${NODE}" --quiet -- chroot /host lsmod 2>/dev/null | grep -q '^sctp'; then
  test_result 0 "SCTP kernel module loaded"
else
  test_result 1 "SCTP kernel module loaded"
fi

echo "[2/6] Testing SCTP socket creation..."
oc delete pod sctp-sock-test -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
if oc run sctp-sock-test --rm -i --restart=Never -n "${NAMESPACE}" \
  --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"sctp-sock-test","image":"registry.access.redhat.com/ubi9/ubi-minimal:latest","command":["python3","-c","import socket; socket.socket(socket.AF_INET, socket.SOCK_STREAM, 132).close(); print(\"OK\")"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
  --quiet --command -- true 2>/dev/null | grep -q OK; then
  test_result 0 "SCTP socket creation"
else
  # Fallback without overrides parsing issues
  OUT=$(oc run sctp-sock-test2 --rm -i --restart=Never -n "${NAMESPACE}" \
    --image=registry.access.redhat.com/ubi9/ubi:latest \
    -- bash -c 'python3 -c "import socket; socket.socket(socket.AF_INET, socket.SOCK_STREAM, 132).close(); print(\"OK\")"' 2>&1 || true)
  echo "$OUT" | grep -q OK
  test_result $? "SCTP socket creation"
fi

echo "[3/6] Testing pod-to-pod SCTP connectivity..."
SERVER_IP=$(oc get pod sctp-server -n "${NAMESPACE}" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [ -n "${SERVER_IP}" ] && oc exec -n "${NAMESPACE}" sctp-client -- \
  sh -c "echo 'test' | timeout 5 ncat --sctp ${SERVER_IP} 38412" >/dev/null 2>&1; then
  test_result 0 "Pod-to-pod SCTP (port 38412)"
else
  test_result 1 "Pod-to-pod SCTP (port 38412)"
fi

echo "[4/6] Testing SCTP via Kubernetes Service..."
if oc exec -n "${NAMESPACE}" sctp-client -- \
  sh -c "echo 'test' | timeout 5 ncat --sctp sctp-server.${NAMESPACE}.svc.cluster.local 38412" >/dev/null 2>&1; then
  test_result 0 "SCTP via Service DNS"
else
  test_result 1 "SCTP via Service DNS"
fi

echo "[5/6] Testing S1AP port (36412)..."
if oc exec -n "${NAMESPACE}" sctp-client -- \
  sh -c "echo 'test' | timeout 5 ncat --sctp mme-sim.${NAMESPACE}.svc.cluster.local 36412" >/dev/null 2>&1; then
  test_result 0 "S1AP SCTP (port 36412)"
else
  test_result 1 "S1AP SCTP (port 36412)"
fi

echo "[6/6] Verifying SCTP on all worker nodes..."
ALL_NODES_OK=0
for N in $(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'); do
  if ! oc debug "node/${N}" --quiet -- chroot /host lsmod 2>/dev/null | grep -q '^sctp'; then
    echo "  WARNING: SCTP not loaded on ${N}"
    ALL_NODES_OK=1
  fi
done
test_result "${ALL_NODES_OK}" "SCTP on all worker nodes"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "${FAIL}" -eq 0 ]

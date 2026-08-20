#!/usr/bin/env bash
# Run full cross-cloud DR validation suite (monthly backup/restore test).
#
# Usage:
#   cp config.env.example config.env   # edit contexts and mappings
#   ./run-dr-validation.sh             # all steps
#   ./run-dr-validation.sh --step 4      # single step
#   ./run-dr-validation.sh --skip-gitops # skip GitOps check
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

STEP=""
SKIP_GITOPS=0
SKIP_CLEANUP=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --step N         Run only step N (1-9)
  --skip-gitops    Skip step 7 (GitOps verification)
  --cleanup        Run cleanup (step 9) after validation
  -h, --help       Show this help

Steps:
  1  Preflight (clusters, OADP, versions)
  2  Deploy test app on primary
  3  Verify OADP configuration
  4  Run backup on primary
  5  Restore on DR cluster
  6  Verify restored data
  7  Verify GitOps on DR
  8  Smoke tests on DR
  9  Cleanup test resources

Configure PRIMARY_CONTEXT and DR_CONTEXT in config.env before running.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step) STEP="$2"; shift 2 ;;
    --skip-gitops) SKIP_GITOPS=1; shift ;;
    --cleanup) SKIP_CLEANUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -f "${SCRIPT_DIR}/config.env" ]] || fail "Missing config.env — copy config.env.example to config.env and edit"

run_step() {
  local n="$1"
  local path=""
  case "${n}" in
    1) path="${SCRIPT_DIR}/01-preflight.sh" ;;
    2) path="${SCRIPT_DIR}/02-deploy-test-app.sh" ;;
    3) path="${SCRIPT_DIR}/03-verify-oadp.sh" ;;
    4) path="${SCRIPT_DIR}/04-run-backup.sh" ;;
    5) path="${SCRIPT_DIR}/05-run-restore.sh" ;;
    6) path="${SCRIPT_DIR}/06-verify-data.sh" ;;
    7) path="${SCRIPT_DIR}/07-verify-gitops.sh" ;;
    8) path="${SCRIPT_DIR}/08-smoke-test.sh" ;;
    9) path="${SCRIPT_DIR}/09-cleanup.sh" ;;
    *) fail "Invalid step: ${n}" ;;
  esac
  log "========== Step ${n}: $(basename "${path}") =========="
  bash "${path}"
}

if [[ -n "${STEP}" ]]; then
  run_step "${STEP}"
  exit 0
fi

TOTAL_START="$(date +%s)"
log "Starting cross-cloud DR validation"
log "Results: ${RESULTS_FILE}"

run_step 1
run_step 2
run_step 3
run_step 4
run_step 5
run_step 6
[[ "${SKIP_GITOPS}" -eq 0 ]] && run_step 7 || log "Skipping GitOps verification"
run_step 8

TOTAL_END="$(date +%s)"
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

log "========== Summary =========="
ok "Full validation completed in ${TOTAL_DURATION}s (~$(( (TOTAL_DURATION + 59) / 60 )) min)"
record_result "full-validation" "PASS" "duration=${TOTAL_DURATION}s"

if [[ -f "${SCRIPTS_ROOT}/results/.last-backup-duration-sec" ]]; then
  log "Backup duration: $(cat "${SCRIPTS_ROOT}/results/.last-backup-duration-sec")s"
fi
if [[ -f "${SCRIPTS_ROOT}/results/.last-restore-duration-sec" ]]; then
  log "Restore duration: $(cat "${SCRIPTS_ROOT}/results/.last-restore-duration-sec")s (partial RTO measure)"
fi

log "Copy results to dr-test-results-template.md:"
log "  ${RESULTS_FILE}"

[[ "${SKIP_CLEANUP}" -eq 0 ]] && run_step 9 || log "Test resources left in place. Run ./09-cleanup.sh --both when done."

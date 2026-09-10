#!/bin/bash
# Request a 24-hour cluster-admin kubeconfig for an ARO HCP cluster.
# Source: https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html
#
# Required environment variables:
#   ARO_RESOURCE_GROUP
#   ARO_CLUSTER_NAME
# Optional:
#   ARO_SUBSCRIPTION_ID (defaults to current az account)
#   FRONTEND_HOST, FRONTEND_API_VERSION, ARM_X_MS_IDENTITY_URL

set -euo pipefail

FRONTEND_HOST="${FRONTEND_HOST:-$(az cloud show --query endpoints.resourceManager --output tsv)}"
FRONTEND_API_VERSION="${FRONTEND_API_VERSION:-2024-06-10-preview}"
SUBSCRIPTION_ID="${ARO_SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
RESOURCE_GROUP="${ARO_RESOURCE_GROUP:?Set ARO_RESOURCE_GROUP}"
CLUSTER_NAME="${ARO_CLUSTER_NAME:?Set ARO_CLUSTER_NAME}"
OUTPUT_FILE="${OUTPUT_FILE:-aro-cluster.kubeconfig}"

header() {
  echo "${1}: ${2}"
}

authorization_header() {
  if [ -z "${ACCESS_TOKEN:-}" ]; then
    ACCESS_TOKEN=$(az account get-access-token --query accessToken --output tsv)
  fi
  header Authorization "Bearer ${ACCESS_TOKEN}"
}

arm_system_data_header() {
  header X-Ms-Arm-Resource-System-Data "{\"createdBy\": \"${USER}\", \"createdByType\": \"User\", \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")\"}"
}

arm_x_ms_identity_url_header() {
  : "${ARM_X_MS_IDENTITY_URL:=https://dummyhost.identity.azure.net}"
  header X-Ms-Identity-Url "${ARM_X_MS_IDENTITY_URL}"
}

correlation_headers() {
  if command -v uuidgen >/dev/null 2>&1; then
    header X-Ms-Correlation-Request-Id "$(uuidgen)"
    header X-Ms-Client-Request-Id "$(uuidgen)"
    header X-Ms-Return-Client-Request-Id "true"
  fi
}

async_operation_status() {
  local url=$1
  local headers=$2
  local output
  output=$(echo "${headers}" | curl --silent --header @- "${url}")
  local status
  status=$(echo "${output}" | jq -r '.status')
  echo "${output}"
  case ${status} in
    Succeeded | Failed | Canceled) return 1 ;;
    *) return 0 ;;
  esac
}

export -f async_operation_status

rp_request() {
  local method=$1
  local url=$2
  local headers=$3
  local body=${4:-}
  local cmd output async_status_endpoint async_result_endpoint

  case ${method} in
    GET)
      cmd="curl --silent --show-error --header @- ${url}"
      ;;
    POST)
      cmd="curl --silent --show-error --include --header @- --request ${method} ${url} --json ''"
      ;;
    *)
      cmd="curl --silent --show-error --include --header @- --request ${method} ${url}"
      if [ -n "${body}" ]; then
        cmd+=" --json '${body}'"
      fi
      ;;
  esac

  output=$(echo "${headers}" | eval "${cmd}" | tr -d '\r')
  async_status_endpoint=$(echo "${output}" | awk 'tolower($1) ~ /^azure-asyncoperation:/ {print $2}')
  async_result_endpoint=$(echo "${output}" | awk 'tolower($1) ~ /^location:/ {print $2}')

  if [ -n "${async_status_endpoint}" ]; then
    watch --errexit --exec bash -c "async_operation_status \"${async_status_endpoint}\" \"${headers}\" 2>/dev/null" || true
    if [ -n "${async_result_endpoint}" ]; then
      local full_result json_result kubeconfig_content
      full_result=$(echo "${headers}" | curl --silent --show-error --include --header @- "${async_result_endpoint}")
      json_result=$(echo "${full_result}" | tr -d '\r' | jq -Rs 'split("\n\n")[1] | fromjson?')
      kubeconfig_content=$(echo "${json_result}" | jq -r '.kubeconfig')
      if [ -n "${kubeconfig_content}" ] && [ "${kubeconfig_content}" != "null" ]; then
        echo "${kubeconfig_content}" > "${OUTPUT_FILE}"
        echo "Wrote ${OUTPUT_FILE}"
      else
        echo "${full_result}"
      fi
    else
      echo "${output}"
    fi
  else
    echo "${output}"
  fi
}

rp_post_request() {
  local path=$1
  local api_version=${2:-${FRONTEND_API_VERSION}}
  local url="${FRONTEND_HOST}${path}?api-version=${api_version}"
  local headers

  case "${FRONTEND_HOST}" in
    *localhost*)
      headers=$(correlation_headers)
      ;;
    *)
      headers=$(authorization_header)
      ;;
  esac

  rp_request POST "${url}" "${headers}"
}

rp_post_request "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/requestAdminCredential"

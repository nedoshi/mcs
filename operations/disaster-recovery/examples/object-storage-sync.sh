#!/usr/bin/env bash
# Sync Azure Blob container to AWS S3 for cross-cloud DR (Cold / Pilot tiers).
# Run via CronJob or external scheduler aligned to RPO.
#
# Required env:
#   RCLONE_CONFIG_AZURE_ACCOUNT
#   RCLONE_CONFIG_AZURE_KEY
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (or IRSA)
#   AZURE_CONTAINER
#   S3_BUCKET
#   S3_PREFIX (optional)
set -euo pipefail

AZURE_CONTAINER="${AZURE_CONTAINER:?}"
S3_BUCKET="${S3_BUCKET:?}"
S3_PREFIX="${S3_PREFIX:-dr-sync}"

echo "Syncing azblob:${AZURE_CONTAINER} -> s3:${S3_BUCKET}/${S3_PREFIX}"
rclone sync "azblob:${AZURE_CONTAINER}" "s3:${S3_BUCKET}/${S3_PREFIX}" \
  --transfers 8 \
  --checkers 16 \
  --log-level INFO

echo "Sync complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

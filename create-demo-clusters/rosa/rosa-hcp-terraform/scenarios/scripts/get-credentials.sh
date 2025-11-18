#!/bin/bash
# Get cluster credentials

CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)

if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Cannot find cluster
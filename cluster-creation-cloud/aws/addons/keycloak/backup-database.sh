#!/bin/bash

# Script to backup Keycloak PostgreSQL database

set -e

NAMESPACE="keycloak"
DB_NAME="keycloak"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/keycloak_backup_$TIMESTAMP.sql"

echo "Creating backup of Keycloak database..."

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Get PostgreSQL pod name
POSTGRES_POD=$(oc get pod -l app=postgresql -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: PostgreSQL pod not found."
    exit 1
fi

# Get database password
DB_PASSWORD=$(oc get secret keycloak-db-secret -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)
DB_USER=$(oc get secret keycloak-db-secret -n $NAMESPACE -o jsonpath='{.data.username}' | base64 -d)

# Create backup
echo "Backing up database to $BACKUP_FILE..."
oc exec -it $POSTGRES_POD -n $NAMESPACE -- \
    PGPASSWORD=$DB_PASSWORD pg_dump -U $DB_USER $DB_NAME > $BACKUP_FILE

if [ $? -eq 0 ]; then
    echo "✅ Backup created successfully: $BACKUP_FILE"
    ls -lh $BACKUP_FILE
else
    echo "❌ Backup failed"
    exit 1
fi


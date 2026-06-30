#!/bin/bash

# Script to restore Keycloak PostgreSQL database from backup

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <backup-file.sql>"
    echo "Example: $0 ./backups/keycloak_backup_20240101_120000.sql"
    exit 1
fi

BACKUP_FILE=$1
NAMESPACE="keycloak"
DB_NAME="keycloak"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  WARNING: This will restore the database from backup."
echo "This will overwrite existing data in the database."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Get PostgreSQL pod name
POSTGRES_POD=$(oc get pod -l app=postgresql -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: PostgreSQL pod not found."
    exit 1
fi

# Get database credentials
DB_PASSWORD=$(oc get secret keycloak-db-secret -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)
DB_USER=$(oc get secret keycloak-db-secret -n $NAMESPACE -o jsonpath='{.data.username}' | base64 -d)

# Scale down Keycloak to prevent connections during restore
echo "Scaling down Keycloak..."
oc scale deployment/keycloak --replicas=0 -n $NAMESPACE
echo "Waiting for pods to terminate..."
oc wait --for=delete pod -l app=keycloak -n $NAMESPACE --timeout=60s || true

# Restore database
echo "Restoring database from $BACKUP_FILE..."
oc exec -i $POSTGRES_POD -n $NAMESPACE -- \
    PGPASSWORD=$DB_PASSWORD psql -U $DB_USER $DB_NAME < $BACKUP_FILE

if [ $? -eq 0 ]; then
    echo "✅ Database restored successfully"
    
    # Scale up Keycloak
    echo "Scaling up Keycloak..."
    oc scale deployment/keycloak --replicas=2 -n $NAMESPACE
    
    echo "✅ Restore complete. Keycloak is starting up."
else
    echo "❌ Restore failed"
    # Scale up Keycloak anyway
    oc scale deployment/keycloak --replicas=2 -n $NAMESPACE
    exit 1
fi


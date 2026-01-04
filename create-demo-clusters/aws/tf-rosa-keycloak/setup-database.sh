#!/bin/bash

# Script to set up PostgreSQL database for Keycloak
# This script creates the database and user required by Keycloak

set -e

NAMESPACE="keycloak"
DB_NAME="keycloak"
DB_USER="keycloak"

echo "Setting up PostgreSQL database for Keycloak..."

# Get PostgreSQL pod name
echo "Finding PostgreSQL pod..."
POSTGRES_POD=$(oc get pod -l app=postgresql -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: PostgreSQL pod not found. Please ensure PostgreSQL is deployed first."
    echo "Run: oc apply -f 02-postgresql.yaml"
    exit 1
fi

echo "Found PostgreSQL pod: $POSTGRES_POD"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
oc wait --for=condition=ready pod/$POSTGRES_POD -n $NAMESPACE --timeout=300s

# Get password from secret
echo "Retrieving database password from secret..."
DB_PASSWORD=$(oc get secret keycloak-db-secret -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$DB_PASSWORD" ]; then
    echo "Warning: Could not retrieve password from secret. Using default."
    echo "Please ensure the secret 'keycloak-db-secret' exists with the correct password."
    read -sp "Enter database password: " DB_PASSWORD
    echo
fi

# Create database
echo "Creating database '$DB_NAME'..."
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "CREATE DATABASE $DB_NAME;"

# Create user
echo "Creating user '$DB_USER'..."
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "SELECT 1 FROM pg_user WHERE usename = '$DB_USER'" | grep -q 1 || \
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"

# Grant privileges
echo "Granting privileges..."
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
oc exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;"

echo ""
echo "✅ Database setup complete!"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""
echo "You can now deploy Keycloak with: oc apply -f 03-keycloak.yaml"


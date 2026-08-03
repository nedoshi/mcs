# Template applied by scripts/run-phase.sh after ConfigMap + phase substitution.
# Do not apply directly — use ./scripts/run-phase.sh expand|backfill|contract
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate-PHASE
  namespace: db-migration
  labels:
    app.kubernetes.io/name: db-migrate
    app.kubernetes.io/component: PHASE
    migration.phase: PHASE
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: db-migrate
        migration.phase: PHASE
    spec:
      serviceAccountName: db-migrator
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16-alpine
          env:
            - name: PGOPTIONS
              value: "-c search_path=app,public"
          envFrom:
            - secretRef:
                name: SECRET_NAME
          volumeMounts:
            - name: sql
              mountPath: /migrations
              readOnly: true
          command:
            - /bin/sh
            - -ec
            - |
              echo "Phase=PHASE user=${PGUSER} host=${PGHOST}"
              for f in $(ls /migrations/*.sql | sort); do
                echo "==> $(basename "$f")"
                psql -v ON_ERROR_STOP=1 -f "$f"
              done
              echo "Phase PHASE complete"
              psql -c "SELECT version, phase, applied_at, applied_by FROM app.schema_migrations ORDER BY applied_at;"
      volumes:
        - name: sql
          configMap:
            name: migration-sql-PHASE

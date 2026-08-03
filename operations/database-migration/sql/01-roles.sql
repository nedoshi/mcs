-- Role split: DDL migrator / DML migrator / application.
-- Passwords must match openshift/secrets/fallback-secret.yaml (lab).
-- In real envs these come from Secrets Manager / Key Vault via ESO.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'db_ddl') THEN
    CREATE ROLE db_ddl LOGIN PASSWORD 'ddl-lab-pass-change-me';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'db_dml') THEN
    CREATE ROLE db_dml LOGIN PASSWORD 'dml-lab-pass-change-me';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'db_app') THEN
    CREATE ROLE db_app LOGIN PASSWORD 'app-lab-pass-change-me';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE orders TO db_ddl, db_dml, db_app;
GRANT USAGE ON SCHEMA app TO db_ddl, db_dml, db_app;

-- DDL: schema owner powers for expand/contract
GRANT CREATE ON SCHEMA app TO db_ddl;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO db_ddl;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app TO db_ddl;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON TABLES TO db_ddl;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON SEQUENCES TO db_ddl;

-- Make db_ddl able to ALTER tables owned by postgres (lab bootstrap)
ALTER TABLE app.orders OWNER TO db_ddl;
ALTER TABLE app.schema_migrations OWNER TO db_ddl;

-- DML: data only — explicitly NO DDL
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO db_dml;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO db_dml;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO db_dml;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO db_dml;

-- App: CRUD, no DDL
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO db_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO db_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO db_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO db_app;

-- Revoke dangerous defaults from PUBLIC
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

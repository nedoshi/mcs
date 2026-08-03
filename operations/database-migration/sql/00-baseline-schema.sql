-- Legacy schema (pre-migration). Applied once by deploy.sh as superuser/postgres.
CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app, public;

CREATE TABLE IF NOT EXISTS orders (
    id              BIGSERIAL PRIMARY KEY,
    order_number    VARCHAR(32) UNIQUE NOT NULL,
    customer_name   VARCHAR(256) NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'CONFIRMED',
    total_cents     INTEGER NOT NULL CHECK (total_cents >= 0),
    items           JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(64) PRIMARY KEY,
    phase       VARCHAR(32) NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    applied_by  VARCHAR(64) NOT NULL DEFAULT CURRENT_USER
);

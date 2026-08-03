-- EXPAND / DDL — add nullable name columns. Safe under traffic.
SET search_path TO app, public;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS customer_first_name VARCHAR(128),
  ADD COLUMN IF NOT EXISTS customer_last_name  VARCHAR(128);

INSERT INTO schema_migrations (version, phase)
VALUES ('V001', 'expand')
ON CONFLICT (version) DO NOTHING;

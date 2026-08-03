-- CONTRACT / DDL — drop legacy columns after apps no longer read them.
SET search_path TO app, public;

ALTER TABLE orders DROP COLUMN IF EXISTS customer_name;
ALTER TABLE orders DROP COLUMN IF EXISTS items;

-- Harden new columns once legacy is gone
ALTER TABLE orders
  ALTER COLUMN customer_first_name SET NOT NULL,
  ALTER COLUMN customer_last_name  SET NOT NULL;

INSERT INTO schema_migrations (version, phase)
VALUES ('V005', 'contract')
ON CONFLICT (version) DO NOTHING;

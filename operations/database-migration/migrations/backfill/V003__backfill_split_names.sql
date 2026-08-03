-- BACKFILL / DML — split customer_name into first/last.
-- Intentionally no ALTER/DROP. Run as db_dml.
SET search_path TO app, public;

UPDATE orders
SET
  customer_first_name = COALESCE(
    customer_first_name,
    NULLIF(split_part(trim(customer_name), ' ', 1), '')
  ),
  customer_last_name = COALESCE(
    customer_last_name,
    NULLIF(
      CASE
        WHEN position(' ' IN trim(customer_name)) = 0 THEN ''
        ELSE substring(trim(customer_name) FROM position(' ' IN trim(customer_name)) + 1)
      END,
      ''
    )
  )
WHERE customer_first_name IS NULL OR customer_last_name IS NULL;

INSERT INTO schema_migrations (version, phase)
VALUES ('V003', 'backfill')
ON CONFLICT (version) DO NOTHING;

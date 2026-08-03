-- BACKFILL / DML — explode JSONB items into order_items.
SET search_path TO app, public;

INSERT INTO order_items (order_id, sku, quantity, price_cents)
SELECT
  o.id,
  elem->>'sku',
  (elem->>'qty')::integer,
  (elem->>'price_cents')::integer
FROM orders o
CROSS JOIN LATERAL jsonb_array_elements(o.items) AS elem
ON CONFLICT (order_id, sku) DO UPDATE
SET
  quantity    = EXCLUDED.quantity,
  price_cents = EXCLUDED.price_cents;

INSERT INTO schema_migrations (version, phase)
VALUES ('V004', 'backfill')
ON CONFLICT (version) DO NOTHING;

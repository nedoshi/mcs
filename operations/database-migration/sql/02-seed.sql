SET search_path TO app, public;

INSERT INTO orders (order_number, customer_name, status, total_cents, items) VALUES
  (
    'ORD-1001',
    'Ada Lovelace',
    'CONFIRMED',
    189999,
    '[{"sku":"LAP-001","qty":1,"price_cents":189999}]'::jsonb
  ),
  (
    'ORD-1002',
    'Grace Hopper',
    'CONFIRMED',
    52998,
    '[{"sku":"MON-002","qty":1,"price_cents":44999},{"sku":"SEC-006","qty":1,"price_cents":7999}]'::jsonb
  ),
  (
    'ORD-1003',
    'Katherine Johnson',
    'SHIPPED',
    27999,
    '[{"sku":"NET-005","qty":1,"price_cents":27999}]'::jsonb
  )
ON CONFLICT (order_number) DO NOTHING;

-- EXPAND / DDL — normalized line items table (empty until backfill + dual-write).
SET search_path TO app, public;

CREATE TABLE IF NOT EXISTS order_items (
    id           BIGSERIAL PRIMARY KEY,
    order_id     BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    sku          VARCHAR(32) NOT NULL,
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    price_cents  INTEGER NOT NULL CHECK (price_cents >= 0),
    UNIQUE (order_id, sku)
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);

-- Ensure DML/app can touch the new table (owner is db_ddl)
GRANT SELECT, INSERT, UPDATE, DELETE ON order_items TO db_dml, db_app;
GRANT USAGE, SELECT ON SEQUENCE order_items_id_seq TO db_dml, db_app;

INSERT INTO schema_migrations (version, phase)
VALUES ('V002', 'expand')
ON CONFLICT (version) DO NOTHING;

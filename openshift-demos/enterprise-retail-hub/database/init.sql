-- Enterprise Retail Hub — PostgreSQL schema
-- Inspired by e-commerce microservices patterns (Online Boutique, Spring Cloud retail demos)

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    sku         VARCHAR(32) UNIQUE NOT NULL,
    name        VARCHAR(128) NOT NULL,
    description TEXT,
    category    VARCHAR(64) NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    stock       INTEGER NOT NULL CHECK (stock >= 0),
    image_url   VARCHAR(256)
);

CREATE TABLE IF NOT EXISTS carts (
    session_id  VARCHAR(64) PRIMARY KEY,
    items       JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id              SERIAL PRIMARY KEY,
    order_number    VARCHAR(32) UNIQUE NOT NULL,
    session_id      VARCHAR(64) NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'CONFIRMED',
    total_cents     INTEGER NOT NULL,
    items           JSONB NOT NULL,
    customer_email  VARCHAR(256) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed catalog: enterprise IT procurement theme
INSERT INTO products (sku, name, description, category, price_cents, stock, image_url) VALUES
  ('LAP-001', 'ThinkPad X1 Carbon', '14" ultrabook for enterprise developers', 'Hardware', 189999, 42, '/images/laptop.svg'),
  ('MON-002', '27" 4K Monitor', 'USB-C docking monitor for hybrid workspaces', 'Hardware', 44999, 85, '/images/monitor.svg'),
  ('CHR-003', 'Ergonomic Task Chair', 'Adjustable lumbar support, 8hr comfort rating', 'Furniture', 32999, 30, '/images/chair.svg'),
  ('LIC-004', 'OpenShift Dev Subscription', 'Annual developer platform license (demo)', 'Software', 99900, 500, '/images/license.svg'),
  ('NET-005', 'Wi-Fi 6 Access Point', 'Enterprise-grade wireless for branch offices', 'Networking', 27999, 60, '/images/network.svg'),
  ('SEC-006', 'Hardware Security Key', 'FIDO2 key for zero-trust authentication', 'Security', 4999, 200, '/images/security-key.svg')
ON CONFLICT (sku) DO NOTHING;

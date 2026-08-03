/**
 * Catalog Service — product catalog backed by PostgreSQL.
 * Pattern inspired by productcatalogservice in Google Online Boutique.
 */
const express = require('express');
const path = require('path');
const { getPool, checkDbHealth } = require(path.join(__dirname, 'shared', 'db'));

const app = express();
const PORT = process.env.PORT || 8081;
const SERVICE_NAME = 'catalog-service';

app.disable('x-powered-by');
app.use(express.json());

app.get('/health/live', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

app.get('/health/ready', async (_req, res) => {
  try {
    await checkDbHealth();
    res.json({ status: 'ok', service: SERVICE_NAME });
  } catch (err) {
    res.status(503).json({ status: 'degraded', service: SERVICE_NAME, error: err.message });
  }
});

// Backward-compatible alias for readiness checks
app.get('/health', async (_req, res) => {
  try {
    await checkDbHealth();
    res.json({ status: 'ok', service: SERVICE_NAME });
  } catch (err) {
    res.status(503).json({ status: 'degraded', service: SERVICE_NAME, error: err.message });
  }
});

// List all in-stock products (enterprise procurement catalog)
app.get('/api/products', async (_req, res) => {
  const pool = getPool();
  const { rows } = await pool.query(
    `SELECT id, sku, name, description, category, price_cents, stock, image_url
     FROM products
     WHERE stock > 0
     ORDER BY category, name`
  );
  res.json(rows);
});

// Single product lookup for cart validation
app.get('/api/products/:id', async (req, res) => {
  const pool = getPool();
  const { rows } = await pool.query(
    `SELECT id, sku, name, description, category, price_cents, stock, image_url
     FROM products WHERE id = $1`,
    [req.params.id]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Product not found' });
    return;
  }

  res.json(rows[0]);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE_NAME} listening on ${PORT}`);
});

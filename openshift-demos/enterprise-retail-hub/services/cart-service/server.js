/**
 * Cart Service — session-based shopping cart stored in PostgreSQL.
 * Persists across pod restarts and scales horizontally (unlike in-memory carts).
 */
const express = require('express');
const path = require('path');
const { getPool, checkDbHealth } = require(path.join(__dirname, 'shared', 'db'));

const app = express();
const PORT = process.env.PORT || 8082;
const SERVICE_NAME = 'cart-service';

app.disable('x-powered-by');
app.use(express.json());

async function getCart(sessionId) {
  const pool = getPool();
  const { rows } = await pool.query(
    'SELECT items FROM carts WHERE session_id = $1',
    [sessionId]
  );

  if (rows.length === 0) {
    return [];
  }

  return rows[0].items;
}

async function saveCart(sessionId, items) {
  const pool = getPool();
  await pool.query(
    `INSERT INTO carts (session_id, items, updated_at)
     VALUES ($1, $2::jsonb, NOW())
     ON CONFLICT (session_id)
     DO UPDATE SET items = EXCLUDED.items, updated_at = NOW()`,
    [sessionId, JSON.stringify(items)]
  );
}

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

app.get('/health', async (_req, res) => {
  try {
    await checkDbHealth();
    res.json({ status: 'ok', service: SERVICE_NAME });
  } catch (err) {
    res.status(503).json({ status: 'degraded', service: SERVICE_NAME, error: err.message });
  }
});

app.get('/api/cart/:sessionId', async (req, res) => {
  const items = await getCart(req.params.sessionId);
  res.json({ sessionId: req.params.sessionId, items });
});

// Add or increment a line item; validates stock via catalog data passed in body
app.post('/api/cart/:sessionId/items', async (req, res) => {
  const { productId, name, priceCents, quantity = 1, maxStock } = req.body;

  if (!productId || !name || priceCents == null) {
    res.status(400).json({ error: 'productId, name, and priceCents are required' });
    return;
  }

  const items = await getCart(req.params.sessionId);
  const existing = items.find((item) => item.productId === productId);
  const nextQty = (existing?.quantity || 0) + quantity;

  if (maxStock != null && nextQty > maxStock) {
    res.status(409).json({ error: 'Insufficient stock', available: maxStock });
    return;
  }

  if (existing) {
    existing.quantity = nextQty;
  } else {
    items.push({ productId, name, priceCents, quantity });
  }

  await saveCart(req.params.sessionId, items);
  res.json({ sessionId: req.params.sessionId, items });
});

app.delete('/api/cart/:sessionId', async (req, res) => {
  const pool = getPool();
  await pool.query('DELETE FROM carts WHERE session_id = $1', [req.params.sessionId]);
  res.json({ sessionId: req.params.sessionId, items: [] });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE_NAME} listening on ${PORT}`);
});

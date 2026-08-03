/**
 * Order Service — checkout orchestration (simplified checkoutservice pattern).
 * Creates orders, decrements inventory, and clears the cart atomically.
 */
const express = require('express');
const path = require('path');
const crypto = require('crypto');
const { getPool, checkDbHealth } = require(path.join(__dirname, 'shared', 'db'));

const app = express();
const PORT = process.env.PORT || 8083;
const SERVICE_NAME = 'order-service';

app.disable('x-powered-by');
app.use(express.json());

function generateOrderNumber() {
  return `ORD-${Date.now().toString(36).toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
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

app.get('/api/orders/:orderNumber', async (req, res) => {
  const pool = getPool();
  const { rows } = await pool.query(
    'SELECT order_number, status, total_cents, items, customer_email, created_at FROM orders WHERE order_number = $1',
    [req.params.orderNumber]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Order not found' });
    return;
  }

  res.json(rows[0]);
});

app.post('/api/orders', async (req, res) => {
  const { sessionId, customerEmail, items } = req.body;

  if (!sessionId || !customerEmail || !Array.isArray(items) || items.length === 0) {
    res.status(400).json({ error: 'sessionId, customerEmail, and items are required' });
    return;
  }

  const pool = getPool();
  const client = await pool.connect();
  const orderNumber = generateOrderNumber();

  try {
    await client.query('BEGIN');

    let totalCents = 0;

    for (const item of items) {
      const { rows } = await client.query(
        'SELECT stock, price_cents, name FROM products WHERE id = $1 FOR UPDATE',
        [item.productId]
      );

      if (rows.length === 0) {
        throw new Error(`Product ${item.productId} not found`);
      }

      const product = rows[0];

      if (product.stock < item.quantity) {
        throw new Error(`Insufficient stock for ${product.name}`);
      }

      totalCents += product.price_cents * item.quantity;

      await client.query(
        'UPDATE products SET stock = stock - $1 WHERE id = $2',
        [item.quantity, item.productId]
      );
    }

    await client.query(
      `INSERT INTO orders (order_number, session_id, status, total_cents, items, customer_email)
       VALUES ($1, $2, 'CONFIRMED', $3, $4::jsonb, $5)`,
      [orderNumber, sessionId, totalCents, JSON.stringify(items), customerEmail]
    );

    await client.query('DELETE FROM carts WHERE session_id = $1', [sessionId]);

    await client.query('COMMIT');

    res.status(201).json({
      orderNumber,
      status: 'CONFIRMED',
      totalCents,
      message: 'Order confirmed — inventory updated',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(409).json({ error: err.message });
  } finally {
    client.release();
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE_NAME} listening on ${PORT}`);
});

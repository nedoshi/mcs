/**
 * order-api — proves Expand/Contract dual-read / dual-write.
 *
 * READ_MODE:  legacy | new | dual (prefer new, fall back legacy)
 * WRITE_MODE: legacy | new | dual
 */
const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 8080;
const READ_MODE = process.env.READ_MODE || 'legacy';
const WRITE_MODE = process.env.WRITE_MODE || 'legacy';

app.disable('x-powered-by');
app.use(express.json());

const pool = new Pool({
  host: process.env.PGHOST,
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  options: process.env.PGOPTIONS,
});

function splitName(full) {
  const t = (full || '').trim();
  const i = t.indexOf(' ');
  if (i < 0) return { first: t, last: '' };
  return { first: t.slice(0, i), last: t.slice(i + 1) };
}

function displayName(row) {
  if (READ_MODE === 'new' || READ_MODE === 'dual') {
    if (row.customer_first_name || row.customer_last_name) {
      return `${row.customer_first_name || ''} ${row.customer_last_name || ''}`.trim();
    }
    if (READ_MODE === 'dual') return row.customer_name;
    return null;
  }
  return row.customer_name;
}

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', readMode: READ_MODE, writeMode: WRITE_MODE });
  } catch (err) {
    res.status(503).json({ status: 'degraded', error: err.message });
  }
});

app.get('/api/orders', async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT id, order_number, status, total_cents, created_at,
            customer_name, customer_first_name, customer_last_name
     FROM app.orders
     ORDER BY id`
  ).catch(async (err) => {
    // Pre-expand or post-contract column differences
    if (!/customer_first_name|customer_name/.test(err.message)) throw err;
    return pool.query(
      `SELECT id, order_number, status, total_cents, created_at, *
       FROM app.orders ORDER BY id`
    );
  });

  res.json(
    rows.map((r) => ({
      orderNumber: r.order_number,
      status: r.status,
      totalCents: r.total_cents,
      customer: displayName(r),
      firstName: r.customer_first_name ?? null,
      lastName: r.customer_last_name ?? null,
      createdAt: r.created_at,
    }))
  );
});

app.post('/api/orders', async (req, res) => {
  const { orderNumber, customerName, totalCents, items } = req.body;
  if (!orderNumber || !customerName || totalCents == null) {
    res.status(400).json({ error: 'orderNumber, customerName, totalCents required' });
    return;
  }

  const { first, last } = splitName(customerName);
  const itemsJson = JSON.stringify(items || []);
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    if (WRITE_MODE === 'legacy') {
      await client.query(
        `INSERT INTO app.orders (order_number, customer_name, total_cents, items)
         VALUES ($1, $2, $3, $4::jsonb)`,
        [orderNumber, customerName, totalCents, itemsJson]
      );
    } else if (WRITE_MODE === 'new') {
      const { rows } = await client.query(
        `INSERT INTO app.orders (order_number, customer_first_name, customer_last_name, total_cents)
         VALUES ($1, $2, $3, $4) RETURNING id`,
        [orderNumber, first, last, totalCents]
      );
      for (const it of items || []) {
        await client.query(
          `INSERT INTO app.order_items (order_id, sku, quantity, price_cents)
           VALUES ($1, $2, $3, $4)`,
          [rows[0].id, it.sku, it.qty, it.price_cents]
        );
      }
    } else {
      // dual
      const { rows } = await client.query(
        `INSERT INTO app.orders
           (order_number, customer_name, customer_first_name, customer_last_name, total_cents, items)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb) RETURNING id`,
        [orderNumber, customerName, first, last, totalCents, itemsJson]
      );
      for (const it of items || []) {
        await client.query(
          `INSERT INTO app.order_items (order_id, sku, quantity, price_cents)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (order_id, sku) DO UPDATE
             SET quantity = EXCLUDED.quantity, price_cents = EXCLUDED.price_cents`,
          [rows[0].id, it.sku, it.qty, it.price_cents]
        );
      }
    }

    await client.query('COMMIT');
    res.status(201).json({ orderNumber, writeMode: WRITE_MODE });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(409).json({ error: err.message });
  } finally {
    client.release();
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`order-api on ${PORT} READ=${READ_MODE} WRITE=${WRITE_MODE}`);
});

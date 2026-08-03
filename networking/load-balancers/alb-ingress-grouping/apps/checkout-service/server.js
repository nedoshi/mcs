/**
 * checkout-service — lightweight order / checkout API for the shared-ALB demo.
 * Exposed externally at /checkout/* via a second Ingress that joins the same
 * IngressGroup (single ALB) as catalog-service.
 */
const express = require('express');
const crypto = require('crypto');

const app = express();
const PORT = Number(process.env.PORT || 8080);
const SERVICE = 'checkout-service';
const POD = process.env.HOSTNAME || 'local';

app.disable('x-powered-by');
app.use(express.json());

/** @type {Map<string, object>} */
const ORDERS = new Map();

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE, pod: POD });
});

app.get('/health/live', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE });
});

app.get('/health/ready', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE });
});

app.get(['/', '/checkout', '/checkout/'], (_req, res) => {
  res.json({
    service: SERVICE,
    pod: POD,
    message: 'Checkout API — shares one ALB with catalog via IngressClassParams',
    endpoints: ['POST /checkout/orders', 'GET /checkout/orders/:id', '/health'],
  });
});

app.get(['/orders', '/checkout/orders'], (_req, res) => {
  res.json({
    service: SERVICE,
    pod: POD,
    count: ORDERS.size,
    orders: Array.from(ORDERS.values()),
  });
});

app.get(['/orders/:id', '/checkout/orders/:id'], (req, res) => {
  const order = ORDERS.get(req.params.id);
  if (!order) {
    res.status(404).json({ error: 'Order not found', service: SERVICE });
    return;
  }
  res.json({ service: SERVICE, pod: POD, order });
});

app.post(['/orders', '/checkout/orders'], (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if (items.length === 0) {
    res.status(400).json({
      error: 'Body must include non-empty items[]',
      example: { items: [{ sku: 'sku-1001', qty: 1 }] },
      service: SERVICE,
    });
    return;
  }

  const id = `ord-${crypto.randomBytes(4).toString('hex')}`;
  const order = {
    id,
    status: 'confirmed',
    items,
    created_at: new Date().toISOString(),
    handled_by: POD,
  };
  ORDERS.set(id, order);

  res.status(201).json({ service: SERVICE, pod: POD, order });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE} listening on ${PORT} (pod=${POD})`);
});

/**
 * catalog-service — in-memory product catalog for the shared-ALB demo.
 * Exposed externally at /catalog/* via a dedicated Ingress that shares one ALB
 * with checkout-service (IngressClassParams group).
 */
const express = require('express');

const app = express();
const PORT = Number(process.env.PORT || 8080);
const SERVICE = 'catalog-service';
const POD = process.env.HOSTNAME || 'local';

app.disable('x-powered-by');
app.use(express.json());

const PRODUCTS = [
  {
    id: 'sku-1001',
    name: 'Enterprise Laptop 14"',
    category: 'hardware',
    price_cents: 129900,
    stock: 42,
  },
  {
    id: 'sku-2002',
    name: '27" 4K Monitor',
    category: 'hardware',
    price_cents: 44900,
    stock: 87,
  },
  {
    id: 'sku-3003',
    name: 'Zero-Trust VPN License (1yr)',
    category: 'software',
    price_cents: 9900,
    stock: 500,
  },
];

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE, pod: POD });
});

app.get('/health/live', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE });
});

app.get('/health/ready', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE });
});

// Path-stripped handlers: Ingress routes /catalog/* → this service.
// Keep both /catalog/... and /... so the app works with or without rewrite.
app.get(['/products', '/catalog/products'], (_req, res) => {
  res.json({
    service: SERVICE,
    pod: POD,
    count: PRODUCTS.length,
    products: PRODUCTS,
  });
});

app.get(['/products/:id', '/catalog/products/:id'], (req, res) => {
  const product = PRODUCTS.find((p) => p.id === req.params.id);
  if (!product) {
    res.status(404).json({ error: 'Product not found', service: SERVICE });
    return;
  }
  res.json({ service: SERVICE, pod: POD, product });
});

app.get(['/', '/catalog', '/catalog/'], (_req, res) => {
  res.json({
    service: SERVICE,
    pod: POD,
    message: 'Catalog API — share this ALB with checkout via IngressClassParams',
    endpoints: ['/catalog/products', '/catalog/products/:id', '/health'],
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE} listening on ${PORT} (pod=${POD})`);
});

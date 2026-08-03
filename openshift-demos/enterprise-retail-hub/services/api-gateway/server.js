/**
 * API Gateway — single north-south entry point for backend microservices.
 * Demonstrates OpenShift internal service discovery via Kubernetes DNS.
 */
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 8080;
const SERVICE_NAME = 'api-gateway';

const CATALOG_URL = process.env.CATALOG_SERVICE_URL || 'http://catalog-service:8081';
const CART_URL = process.env.CART_SERVICE_URL || 'http://cart-service:8082';
const ORDER_URL = process.env.ORDER_SERVICE_URL || 'http://order-service:8083';

app.disable('x-powered-by');

// Correlation ID for distributed tracing demos
app.use((req, res, next) => {
  const correlationId = req.headers['x-correlation-id'] || crypto.randomUUID();
  req.correlationId = correlationId;
  res.setHeader('X-Correlation-Id', correlationId);
  next();
});

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: SERVICE_NAME,
    upstreams: { catalog: CATALOG_URL, cart: CART_URL, order: ORDER_URL },
  });
});

function proxyService(target, basePath) {
  return createProxyMiddleware({
    target,
    changeOrigin: true,
    pathRewrite: (path) => {
      if (!path || path === '/') {
        return basePath;
      }
      return `${basePath}${path}`;
    },
    on: {
      proxyReq(proxyReq, req) {
        if (req.correlationId) {
          proxyReq.setHeader('X-Correlation-Id', req.correlationId);
        }
      },
    },
  });
}

app.use('/api/products', proxyService(CATALOG_URL, '/api/products'));
app.use('/products', proxyService(CATALOG_URL, '/api/products'));
app.use('/api/cart', proxyService(CART_URL, '/api/cart'));
app.use('/cart', proxyService(CART_URL, '/api/cart'));
app.use('/api/orders', proxyService(ORDER_URL, '/api/orders'));
app.use('/orders', proxyService(ORDER_URL, '/api/orders'));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`${SERVICE_NAME} listening on ${PORT}`);
});

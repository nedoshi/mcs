/**
 * Frontend — enterprise procurement storefront.
 * Proxies /api/* to the API Gateway so users only need one public Route.
 */
const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.PORT || 8080;
const PUBLIC_DIR = path.join(__dirname, 'public');
const API_GATEWAY_URL = process.env.API_GATEWAY_URL || 'http://api-gateway:8080';

app.disable('x-powered-by');

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'frontend' });
});

app.use('/api', createProxyMiddleware({
  target: API_GATEWAY_URL,
  changeOrigin: true,
  pathRewrite: (_path, req) => req.originalUrl,
}));

app.use(express.static(PUBLIC_DIR, { index: false }));

app.get('*', (req, res, next) => {
  if (req.path.includes('.')) {
    next();
    return;
  }
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`frontend listening on ${PORT}, gateway=${API_GATEWAY_URL}`);
});

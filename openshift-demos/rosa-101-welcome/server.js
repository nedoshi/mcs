const express = require('express');
const os = require('os');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const PUBLIC_DIR = path.join(__dirname, 'public');
const BUILD_ID = '2026-07-14-ssr-v2';

const products = [
  { id: 1, name: 'ROSA Starter Kit', price: 29.99, stock: 120, category: 'Bundles', image: '/images/starter-kit.svg' },
  { id: 2, name: 'OpenShift Coffee Mug', price: 14.99, stock: 48, category: 'Swag', image: '/images/coffee-mug.svg' },
  { id: 3, name: 'Kubernetes Sticker Pack', price: 9.99, stock: 200, category: 'Swag', image: '/images/sticker-pack.svg' },
  { id: 4, name: 'GitOps Workflow Guide', price: 0, stock: 999, category: 'Resources', image: '/images/gitops-guide.svg' },
];

function getRuntimeInfo() {
  return {
    message: process.env.WELCOME_MESSAGE || 'Welcome to ROSA!',
    hostname: process.env.POD_NAME || os.hostname(),
    namespace: process.env.OPENSHIFT_NAMESPACE || process.env.NAMESPACE || 'local',
    appVersion: process.env.APP_VERSION || '1.0.0',
    buildId: BUILD_ID,
    platform: 'Red Hat OpenShift Service on AWS',
    refreshedAt: new Date().toISOString(),
  };
}

app.disable('x-powered-by');

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', buildId: BUILD_ID });
});

app.get('/api/info', (_req, res) => {
  res.json(getRuntimeInfo());
});

app.get('/api/products', (_req, res) => {
  res.json(products);
});

app.use(express.static(PUBLIC_DIR, {
  index: false,
  setHeaders(res, filePath) {
    if (filePath.endsWith('.html')) {
      res.setHeader('Cache-Control', 'no-store');
    }
  },
}));

app.get('/', (_req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Build-Id', BUILD_ID);
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

app.get('*', (req, res, next) => {
  if (req.path.startsWith('/api/')) {
    res.status(404).json({ error: 'Not found' });
    return;
  }

  if (req.path.includes('.')) {
    next();
    return;
  }

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Build-Id', BUILD_ID);
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`rosa-101-welcome listening on port ${PORT} (${BUILD_ID})`);
});

const express = require('express');
const os = require('os');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

const products = [
  { id: 1, name: 'ROSA Starter Kit', price: 29.99, stock: 120, category: 'Bundles' },
  { id: 2, name: 'OpenShift Coffee Mug', price: 14.99, stock: 48, category: 'Swag' },
  { id: 3, name: 'Kubernetes Sticker Pack', price: 9.99, stock: 200, category: 'Swag' },
  { id: 4, name: 'GitOps Workflow Guide', price: 0, stock: 999, category: 'Resources' },
];

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/api/info', (_req, res) => {
  res.json({
    message: process.env.WELCOME_MESSAGE || 'Welcome to ROSA!',
    hostname: process.env.POD_NAME || os.hostname(),
    namespace: process.env.OPENSHIFT_NAMESPACE || process.env.NAMESPACE || 'local',
    appVersion: process.env.APP_VERSION || '1.0.0',
    platform: 'Red Hat OpenShift Service on AWS',
    refreshedAt: new Date().toISOString(),
  });
});

app.get('/api/products', (_req, res) => {
  res.json(products);
});

app.use(express.static(path.join(__dirname, 'public')));

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`rosa-101-welcome listening on port ${PORT}`);
});

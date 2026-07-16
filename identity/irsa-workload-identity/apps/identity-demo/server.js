/**
 * identity-demo — proves IRSA on ROSA HCP.
 * Webhook injects AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN_FILE; AWS SDK v3
 * uses the default credential chain (web identity) — no static keys.
 */
const express = require('express');
const { STSClient, GetCallerIdentityCommand } = require('@aws-sdk/client-sts');
const { S3Client, ListObjectsV2Command, PutObjectCommand } = require('@aws-sdk/client-s3');
const fs = require('fs');

const app = express();
const PORT = Number(process.env.PORT || 8080);
const BUCKET = process.env.S3_BUCKET || '';
const REGION = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';

app.disable('x-powered-by');

function envSnapshot() {
  return {
    AWS_ROLE_ARN: process.env.AWS_ROLE_ARN || process.env.AWS_ARN_ROLE || null,
    AWS_WEB_IDENTITY_TOKEN_FILE: process.env.AWS_WEB_IDENTITY_TOKEN_FILE || null,
    AWS_REGION: REGION,
    S3_BUCKET: BUCKET || null,
    // EKS Pod Identity vars — should be ABSENT on ROSA
    AWS_CONTAINER_CREDENTIALS_FULL_URI: process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI || null,
    token_file_exists: process.env.AWS_WEB_IDENTITY_TOKEN_FILE
      ? fs.existsSync(process.env.AWS_WEB_IDENTITY_TOKEN_FILE)
      : false,
  };
}

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'identity-demo' });
});

app.get('/', (_req, res) => {
  res.json({
    service: 'identity-demo',
    message: 'ROSA IRSA demo (not EKS Pod Identity)',
    endpoints: ['/whoami', '/s3', '/env', '/health'],
  });
});

app.get('/env', (_req, res) => {
  res.json({
    note: 'IRSA uses AWS_WEB_IDENTITY_TOKEN_FILE. EKS Pod Identity would use AWS_CONTAINER_CREDENTIALS_FULL_URI.',
    env: envSnapshot(),
  });
});

app.get('/whoami', async (_req, res) => {
  try {
    const sts = new STSClient({ region: REGION });
    const identity = await sts.send(new GetCallerIdentityCommand({}));
    res.json({
      mechanism: 'IRSA / AssumeRoleWithWebIdentity',
      identity,
      env: envSnapshot(),
    });
  } catch (err) {
    res.status(500).json({
      error: err.message,
      hint: 'Check SA annotation eks.amazonaws.com/role-arn and IAM trust sub condition',
      env: envSnapshot(),
    });
  }
});

app.get('/s3', async (_req, res) => {
  if (!BUCKET) {
    res.status(400).json({ error: 'S3_BUCKET env not set' });
    return;
  }
  try {
    const s3 = new S3Client({ region: REGION });
    const listed = await s3.send(
      new ListObjectsV2Command({ Bucket: BUCKET, MaxKeys: 20 })
    );
    res.json({
      bucket: BUCKET,
      key_count: listed.KeyCount || 0,
      objects: (listed.Contents || []).map((o) => ({
        key: o.Key,
        size: o.Size,
        last_modified: o.LastModified,
      })),
    });
  } catch (err) {
    res.status(500).json({ error: err.message, bucket: BUCKET });
  }
});

app.post('/s3/ping', async (_req, res) => {
  if (!BUCKET) {
    res.status(400).json({ error: 'S3_BUCKET env not set' });
    return;
  }
  const key = `irsa-demo/ping-${Date.now()}.txt`;
  try {
    const s3 = new S3Client({ region: REGION });
    await s3.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: key,
        Body: `hello from ROSA IRSA @ ${new Date().toISOString()}\n`,
        ContentType: 'text/plain',
      })
    );
    res.status(201).json({ bucket: BUCKET, key, written: true });
  } catch (err) {
    res.status(500).json({ error: err.message, bucket: BUCKET, key });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`identity-demo on ${PORT} region=${REGION} bucket=${BUCKET || '(none)'}`);
  console.log('env:', JSON.stringify(envSnapshot()));
});

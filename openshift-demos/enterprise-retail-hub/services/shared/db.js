/**
 * Shared PostgreSQL connection pool for catalog, cart, and order services.
 * Uses env vars injected by OpenShift Secrets/Deployments.
 */
const { Pool } = require('pg');

let pool;

function getPool() {
  if (!pool) {
    pool = new Pool({
      host: process.env.PGHOST || 'postgres',
      port: Number(process.env.PGPORT || 5432),
      database: process.env.PGDATABASE || 'retail',
      user: process.env.PGUSER || 'postgres',
      password: process.env.PGPASSWORD || 'retail',
      max: Number(process.env.PGPOOL_MAX || 5),
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
    });

    pool.on('error', (err) => {
      console.error('Unexpected PostgreSQL pool error', err);
    });
  }

  return pool;
}

async function checkDbHealth() {
  const client = await getPool().connect();
  try {
    await client.query('SELECT 1');
    return true;
  } finally {
    client.release();
  }
}

module.exports = { getPool, checkDbHealth };

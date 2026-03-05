const baseUrl = (process.env.BASE_URL || 'http://127.0.0.1:8787').replace(/\/$/, '');
const authToken = process.env.BACKEND_TOKEN || '';
const ollamaKey = process.env.OLLAMA_KEY || '';

function headers(extra = {}) {
  const h = { ...extra };
  if (authToken) h.authorization = `Bearer ${authToken}`;
  if (ollamaKey) h['x-ollama-key'] = ollamaKey;
  return h;
}

async function req(path, opts = {}) {
  const res = await fetch(`${baseUrl}${path}`, opts);
  const text = await res.text();
  return { status: res.status, text, headers: res.headers };
}

function assert(cond, message) {
  if (!cond) {
    throw new Error(message);
  }
}

async function run() {
  const live = await req('/health/live');
  console.log('health/live', live.status);
  assert(live.status === 200, 'health/live failed');

  const ready = await req('/health/ready');
  console.log('health/ready', ready.status);
  assert([200, 503].includes(ready.status), 'health/ready invalid response');

  const tags = await req('/api/tags', { headers: headers() });
  console.log('api/tags', tags.status);
  assert([200, 401, 403, 429, 502, 503].includes(tags.status), 'api/tags unexpected status');

  const metrics = await req('/admin/metrics', { headers: headers() });
  console.log('admin/metrics', metrics.status);

  console.log('smoke complete');
}

run().catch((err) => {
  console.error('smoke failed:', err.message);
  process.exit(1);
});

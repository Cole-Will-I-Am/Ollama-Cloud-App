import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import { MemoryRateLimiter } from '../src/rate-limit.mjs';
import { createApp } from '../src/server.mjs';

function baseConfig(overrides = {}) {
  return {
    nodeEnv: 'test',
    port: 0,
    host: '127.0.0.1',
    upstreamBaseUrl: 'https://ollama.com',
    upstreamTimeoutMs: 1000,
    upstreamRetryMax: 0,
    upstreamRetryBaseMs: 10,
    maxBodyBytes: 1000000,
    trustProxy: false,
    corsAllowedOrigins: [],
    securityHeaders: true,
    authMode: 'none',
    backendBearerToken: '',
    jwtIssuer: '',
    jwtAudience: '',
    jwtHs256Secret: '',
    upstreamApiKey: '',
    allowCompatibilityBearerAsUpstreamKey: true,
    rateLimitWindowMs: 60000,
    rateLimitMax: 5,
    rateLimitPrefix: 'rl',
    redisUrl: '',
    circuitFailureThreshold: 2,
    circuitOpenMs: 10000,
    allowedModels: new Set(),
    seerModelEnabled: true,
    seerAliasName: 'SEER',
    seerUpstreamModel: 'qwen3.5:397b-cloud',
    adminBearerToken: 'admin',
    ...overrides,
  };
}

function makeLogger() {
  return {
    info() {},
    warn() {},
    error() {},
    debug() {},
  };
}

async function startTestServer({ config, fetchImpl }) {
  const rateLimiter = new MemoryRateLimiter({ windowMs: config.rateLimitWindowMs, max: config.rateLimitMax });
  const app = createApp({
    config,
    logger: makeLogger(),
    rateLimiter,
    fetchImpl,
  });

  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const address = app.server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;

  return {
    baseUrl,
    close: () => app.close(),
  };
}

function toJsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function signJwtHs256(payload, secret) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const enc = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const h = enc(header);
  const p = enc(payload);
  const sig = crypto.createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${sig}`;
}

test('health endpoints work', async () => {
  const config = baseConfig();
  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const live = await fetch(`${srv.baseUrl}/health/live`);
  assert.equal(live.status, 200);

  const ready = await fetch(`${srv.baseUrl}/health/ready`);
  assert.equal(ready.status, 200);

  await srv.close();
});

test('static auth enforces bearer token', async () => {
  const config = baseConfig({ authMode: 'static', backendBearerToken: 'secret', allowCompatibilityBearerAsUpstreamKey: false });
  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const missing = await fetch(`${srv.baseUrl}/api/tags`);
  assert.equal(missing.status, 401);

  const wrong = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer wrong', 'x-ollama-key': 'k' } });
  assert.equal(wrong.status, 401);

  const ok = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer secret', 'x-ollama-key': 'k' } });
  assert.equal(ok.status, 200);

  await srv.close();
});

test('static auth accepts case-insensitive bearer scheme', async () => {
  const config = baseConfig({ authMode: 'static', backendBearerToken: 'secret', allowCompatibilityBearerAsUpstreamKey: false });
  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const ok = await fetch(`${srv.baseUrl}/api/tags`, {
    headers: {
      authorization: 'bearer secret',
      'x-ollama-key': 'k',
    },
  });

  assert.equal(ok.status, 200);
  await srv.close();
});

test('jwt auth accepts valid token', async () => {
  const now = Math.floor(Date.now() / 1000);
  const config = baseConfig({
    authMode: 'jwt',
    jwtIssuer: 'issuer',
    jwtAudience: 'aud',
    jwtHs256Secret: 'super-secret',
    allowCompatibilityBearerAsUpstreamKey: false,
  });

  const token = signJwtHs256(
    {
      iss: 'issuer',
      aud: 'aud',
      sub: 'user-123',
      exp: now + 300,
    },
    'super-secret',
  );

  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/api/tags`, {
    headers: {
      authorization: `Bearer ${token}`,
      'x-ollama-key': 'k',
    },
  });

  assert.equal(res.status, 200);
  await srv.close();
});

test('allowlist filters tags and blocks chat model', async () => {
  const config = baseConfig({
    allowedModels: new Set(['allowed-model']),
  });

  const fetchImpl = async (url) => {
    if (String(url).endsWith('/api/tags')) {
      return toJsonResponse({ models: [{ name: 'allowed-model' }, { name: 'denied-model' }] }, 200);
    }

    if (String(url).endsWith('/api/chat')) {
      return toJsonResponse({ done: true }, 200);
    }

    return toJsonResponse({}, 404);
  };

  const srv = await startTestServer({ config, fetchImpl });

  const tagsRes = await fetch(`${srv.baseUrl}/api/tags`, {
    headers: { authorization: 'Bearer k' },
  });
  assert.equal(tagsRes.status, 200);
  const tags = await tagsRes.json();
  assert.deepEqual(tags.models.map((m) => m.name), ['allowed-model']);

  const chatDenied = await fetch(`${srv.baseUrl}/api/chat`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer k',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model: 'denied-model', messages: [] }),
  });

  assert.equal(chatDenied.status, 403);
  await srv.close();
});

test('rate limiting returns 429 after threshold', async () => {
  const config = baseConfig({ rateLimitMax: 2 });
  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const r1 = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer k' } });
  const r2 = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer k' } });
  const r3 = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer k' } });

  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);
  assert.equal(r3.status, 429);
  await srv.close();
});

test('chat request is not retried on upstream failure', async () => {
  const config = baseConfig({ upstreamRetryMax: 3 });
  let chatCalls = 0;

  const fetchImpl = async (url) => {
    if (String(url).endsWith('/api/chat')) {
      chatCalls += 1;
      throw new Error('upstream failure');
    }
    return toJsonResponse({ models: [] }, 200);
  };

  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/api/chat`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer k',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model: 'allowed-model', messages: [] }),
  });

  assert.equal(res.status, 502);
  assert.equal(chatCalls, 1);
  await srv.close();
});

test('tags upstream headers are passed through on non-2xx responses', async () => {
  const config = baseConfig();
  const fetchImpl = async () => new Response(JSON.stringify({ error: 'rate limited' }), {
    status: 429,
    headers: {
      'content-type': 'application/json',
      'retry-after': '17',
      'x-ratelimit-remaining': '0',
    },
  });
  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/api/tags`, {
    headers: { authorization: 'Bearer k' },
  });

  assert.equal(res.status, 429);
  assert.equal(res.headers.get('retry-after'), '17');
  assert.equal(res.headers.get('x-ratelimit-remaining'), '0');
  await srv.close();
});

test('chat upstream headers are passed through', async () => {
  const config = baseConfig();
  const fetchImpl = async (url) => {
    if (String(url).endsWith('/api/chat')) {
      return new Response(JSON.stringify({ error: 'rate limited' }), {
        status: 429,
        headers: {
          'content-type': 'application/json',
          'retry-after': '9',
          'ratelimit-reset': '1712345678',
        },
      });
    }
    return toJsonResponse({ models: [] }, 200);
  };
  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/api/chat`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer k',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model: 'allowed-model', messages: [] }),
  });

  assert.equal(res.status, 429);
  assert.equal(res.headers.get('retry-after'), '9');
  assert.equal(res.headers.get('ratelimit-reset'), '1712345678');
  await srv.close();
});

test('chat request too large returns 413 without calling upstream', async () => {
  const config = baseConfig({ maxBodyBytes: 30 });
  let called = false;
  const fetchImpl = async () => {
    called = true;
    return toJsonResponse({ done: true }, 200);
  };
  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/api/chat`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer k',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: 'allowed-model',
      messages: [{ role: 'user', content: 'this payload is definitely too long for the test limit' }],
    }),
  });

  assert.equal(res.status, 413);
  assert.equal(called, false);
  await srv.close();
});

test('circuit breaker opens on repeated upstream failures', async () => {
  const config = baseConfig({ circuitFailureThreshold: 1, upstreamRetryMax: 0 });
  const fetchImpl = async () => {
    throw new Error('upstream failure');
  };
  const srv = await startTestServer({ config, fetchImpl });

  const first = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer k' } });
  const second = await fetch(`${srv.baseUrl}/api/tags`, { headers: { authorization: 'Bearer k' } });

  assert.equal(first.status, 502);
  assert.equal(second.status, 503);
  await srv.close();
});

test('admin metrics require explicit admin token', async () => {
  const config = baseConfig({
    authMode: 'static',
    backendBearerToken: 'client-token',
    adminBearerToken: '',
    allowCompatibilityBearerAsUpstreamKey: false,
  });
  const fetchImpl = async () => toJsonResponse({ models: [] }, 200);
  const srv = await startTestServer({ config, fetchImpl });

  const res = await fetch(`${srv.baseUrl}/admin/metrics`, {
    headers: { authorization: 'Bearer client-token' },
  });

  assert.equal(res.status, 401);
  await srv.close();
});

test('SEER alias appears in tags and routes chat to upstream model with system context', async () => {
  const config = baseConfig();
  let capturedChatBody = null;

  const fetchImpl = async (url, options = {}) => {
    if (String(url).endsWith('/api/tags')) {
      return toJsonResponse({
        models: [
          { name: 'qwen3.5:397b-cloud' },
          { name: 'qwen3:8b' },
        ],
      }, 200);
    }

    if (String(url).endsWith('/api/chat')) {
      capturedChatBody = JSON.parse(String(options.body || '{}'));
      return new Response('{"done":true}\n', {
        status: 200,
        headers: { 'content-type': 'application/x-ndjson' },
      });
    }

    return toJsonResponse({}, 404);
  };

  const srv = await startTestServer({ config, fetchImpl });

  const tagsRes = await fetch(`${srv.baseUrl}/api/tags`, {
    headers: { authorization: 'Bearer k' },
  });
  assert.equal(tagsRes.status, 200);
  const tags = await tagsRes.json();
  assert.ok(tags.models.some((model) => model.name === 'SEER'));

  const chatRes = await fetch(`${srv.baseUrl}/api/chat`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer k',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: 'SEER',
      messages: [{ role: 'user', content: 'How do scaffolds work?' }],
    }),
  });

  assert.equal(chatRes.status, 200);
  assert.equal(capturedChatBody.model, 'qwen3.5:397b-cloud');
  assert.ok(Array.isArray(capturedChatBody.messages));
  assert.equal(capturedChatBody.messages[0]?.role, 'system');
  assert.match(String(capturedChatBody.messages[0]?.content || ''), /You are SEER/i);

  await srv.close();
});

import http from 'node:http';
import crypto from 'node:crypto';
import { Readable } from 'node:stream';
import { URL } from 'node:url';

import { authenticateAdmin, authenticateRequest, resolveUpstreamKey } from './auth.mjs';
import { Metrics } from './metrics.mjs';
import { CircuitBreaker, fetchWithRetry } from './upstream.mjs';

function nowMs() {
  return Number(process.hrtime.bigint() / 1000000n);
}

function isOriginAllowed(origin, allowedOrigins) {
  if (!origin) return false;
  if (!allowedOrigins || allowedOrigins.length === 0) return false;
  return allowedOrigins.includes(origin);
}

function parseJsonBody(req, maxBodyBytes) {
  return new Promise((resolve, reject) => {
    let bytes = 0;
    const chunks = [];

    req.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes > maxBodyBytes) {
        const err = new Error('Request body too large');
        err.code = 'BODY_TOO_LARGE';
        reject(err);
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8');
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        const err = new Error('Invalid JSON body');
        err.code = 'BAD_JSON';
        reject(err);
      }
    });

    req.on('error', reject);
  });
}

function setCommonHeaders(req, res, config, requestId) {
  res.setHeader('x-request-id', requestId);
  res.setHeader('cache-control', 'no-store');

  if (config.securityHeaders) {
    res.setHeader('x-content-type-options', 'nosniff');
    res.setHeader('x-frame-options', 'DENY');
    res.setHeader('referrer-policy', 'no-referrer');
    res.setHeader('permissions-policy', 'camera=(), microphone=(), geolocation=()');
    res.setHeader('content-security-policy', "default-src 'none'");
    if (req.socket.encrypted) {
      res.setHeader('strict-transport-security', 'max-age=31536000; includeSubDomains');
    }
  }

  const origin = req.headers.origin;
  if (config.corsAllowedOrigins.length > 0 && isOriginAllowed(origin, config.corsAllowedOrigins)) {
    res.setHeader('access-control-allow-origin', origin);
    res.setHeader('vary', 'origin');
    res.setHeader('access-control-allow-headers', 'authorization,content-type,x-ollama-key,x-request-id');
    res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  }
}

function writeJson(req, res, config, { statusCode, payload, requestId }) {
  setCommonHeaders(req, res, config, requestId);
  const data = Buffer.from(JSON.stringify(payload));
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': data.length,
  });
  res.end(data);
}

function writeEmpty(req, res, config, { statusCode, requestId }) {
  setCommonHeaders(req, res, config, requestId);
  res.writeHead(statusCode);
  res.end();
}

function sanitizeRoute(pathname) {
  if (pathname.startsWith('/api/chat')) return '/api/chat';
  if (pathname.startsWith('/api/tags')) return '/api/tags';
  if (pathname.startsWith('/health')) return '/health';
  if (pathname.startsWith('/admin/metrics')) return '/admin/metrics';
  return pathname;
}

export function createApp({
  config,
  logger,
  rateLimiter,
  fetchImpl = fetch,
}) {
  const metrics = new Metrics();
  const circuitBreaker = new CircuitBreaker({
    failureThreshold: config.circuitFailureThreshold,
    openMs: config.circuitOpenMs,
  });

  async function relayTags({ req, res, requestId, route }) {
    const upstreamKey = resolveUpstreamKey(req, config);
    if (!upstreamKey) {
      writeJson(req, res, config, {
        statusCode: 401,
        payload: { error: 'Missing Ollama API key' },
        requestId,
      });
      return 401;
    }

    let upstream;
    try {
      upstream = await fetchWithRetry({
        url: `${config.upstreamBaseUrl}/api/tags`,
        options: {
          method: 'GET',
          headers: {
            authorization: `Bearer ${upstreamKey}`,
            accept: 'application/json',
          },
        },
        timeoutMs: config.upstreamTimeoutMs,
        retryMax: config.upstreamRetryMax,
        retryBaseMs: config.upstreamRetryBaseMs,
        circuitBreaker,
        fetchImpl,
        logger,
        requestId,
        route,
      });
    } catch (err) {
      metrics.recordUpstreamError();
      if (err?.code === 'CIRCUIT_OPEN') {
        writeJson(req, res, config, {
          statusCode: 503,
          payload: { error: 'Upstream temporarily unavailable' },
          requestId,
        });
        return 503;
      }

      logger.error('Upstream tags request failed', { requestId, error: String(err) });
      writeJson(req, res, config, {
        statusCode: 502,
        payload: { error: 'Upstream unavailable' },
        requestId,
      });
      return 502;
    }

    const text = await upstream.text();

    if (!upstream.ok) {
      const contentType = upstream.headers.get('content-type') || 'application/json; charset=utf-8';
      setCommonHeaders(req, res, config, requestId);
      res.writeHead(upstream.status, {
        'content-type': contentType,
      });
      res.end(text);
      return upstream.status;
    }

    let payload;
    try {
      payload = JSON.parse(text);
    } catch {
      metrics.recordUpstreamError();
      writeJson(req, res, config, {
        statusCode: 502,
        payload: { error: 'Invalid upstream response' },
        requestId,
      });
      return 502;
    }

    if (config.allowedModels.size > 0 && Array.isArray(payload.models)) {
      payload.models = payload.models.filter((model) => config.allowedModels.has(model?.name));
    }

    writeJson(req, res, config, {
      statusCode: 200,
      payload,
      requestId,
    });
    return 200;
  }

  async function relayChat({ req, res, requestId, route }) {
    const upstreamKey = resolveUpstreamKey(req, config);
    if (!upstreamKey) {
      writeJson(req, res, config, {
        statusCode: 401,
        payload: { error: 'Missing Ollama API key' },
        requestId,
      });
      return 401;
    }

    let body;
    try {
      body = await parseJsonBody(req, config.maxBodyBytes);
    } catch (err) {
      const code = err?.code;
      const statusCode = code === 'BODY_TOO_LARGE' ? 413 : 400;
      writeJson(req, res, config, {
        statusCode,
        payload: { error: err.message || 'Bad request body' },
        requestId,
      });
      return statusCode;
    }

    if (!body || typeof body !== 'object' || !Array.isArray(body.messages) || typeof body.model !== 'string') {
      writeJson(req, res, config, {
        statusCode: 400,
        payload: { error: 'Invalid chat request payload' },
        requestId,
      });
      return 400;
    }

    if (config.allowedModels.size > 0 && !config.allowedModels.has(body.model)) {
      writeJson(req, res, config, {
        statusCode: 403,
        payload: { error: `Model '${body.model}' is not allowed` },
        requestId,
      });
      return 403;
    }

    let upstream;
    try {
      upstream = await fetchWithRetry({
        url: `${config.upstreamBaseUrl}/api/chat`,
        options: {
          method: 'POST',
          headers: {
            authorization: `Bearer ${upstreamKey}`,
            'content-type': 'application/json',
            accept: 'application/x-ndjson,application/json',
          },
          body: JSON.stringify(body),
        },
        timeoutMs: config.upstreamTimeoutMs,
        retryMax: 1,
        retryBaseMs: config.upstreamRetryBaseMs,
        circuitBreaker,
        fetchImpl,
        logger,
        requestId,
        route,
      });
    } catch (err) {
      metrics.recordUpstreamError();
      if (err?.code === 'CIRCUIT_OPEN') {
        writeJson(req, res, config, {
          statusCode: 503,
          payload: { error: 'Upstream temporarily unavailable' },
          requestId,
        });
        return 503;
      }

      logger.error('Upstream chat request failed', { requestId, error: String(err) });
      writeJson(req, res, config, {
        statusCode: 502,
        payload: { error: 'Upstream unavailable' },
        requestId,
      });
      return 502;
    }

    setCommonHeaders(req, res, config, requestId);
    res.writeHead(upstream.status, {
      'content-type': upstream.headers.get('content-type') || 'application/x-ndjson',
    });

    if (!upstream.body) {
      res.end();
      return upstream.status;
    }

    const stream = Readable.fromWeb(upstream.body);
    await new Promise((resolve) => {
      stream.on('error', (err) => {
        logger.error('Upstream stream error', { requestId, error: String(err) });
        try {
          res.end();
        } catch {
          // ignore
        }
        resolve();
      });
      stream.on('end', resolve);
      stream.pipe(res);
    });

    return upstream.status;
  }

  async function handler(req, res) {
    const startedMs = nowMs();
    const requestId = (typeof req.headers['x-request-id'] === 'string' && req.headers['x-request-id'].slice(0, 128)) || crypto.randomUUID();
    const method = req.method || 'GET';
    const parsed = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
    const path = parsed.pathname;
    const route = sanitizeRoute(path);
    const clientIp = config.trustProxy && typeof req.headers['x-forwarded-for'] === 'string'
      ? req.headers['x-forwarded-for'].split(',')[0].trim()
      : req.socket.remoteAddress || 'unknown';

    const finish = (statusCode) => {
      const durationMs = Math.max(0, nowMs() - startedMs);
      metrics.record(route, statusCode, durationMs);
      logger.info('Request completed', {
        requestId,
        method,
        path,
        route,
        clientIp,
        statusCode,
        durationMs,
      });
    };

    if (method === 'OPTIONS') {
      writeEmpty(req, res, config, { statusCode: 204, requestId });
      finish(204);
      return;
    }

    if ((path === '/health' || path === '/health/live') && method === 'GET') {
      writeJson(req, res, config, {
        statusCode: 200,
        payload: {
          ok: true,
          service: 'ollama-cloud-relay',
          env: config.nodeEnv,
          startedAt: metrics.startedAt,
        },
        requestId,
      });
      finish(200);
      return;
    }

    if (path === '/health/ready' && method === 'GET') {
      const rl = rateLimiter.getReadyState();
      const ready = rl.ready && circuitBreaker.state !== 'open';
      const statusCode = ready ? 200 : 503;
      writeJson(req, res, config, {
        statusCode,
        payload: {
          ok: ready,
          dependencies: {
            rateLimiter: rl,
            circuitBreaker: { state: circuitBreaker.state },
          },
        },
        requestId,
      });
      finish(statusCode);
      return;
    }

    if (path === '/admin/metrics' && method === 'GET') {
      const adminAuth = authenticateAdmin(req, config);
      if (!adminAuth.ok) {
        writeJson(req, res, config, {
          statusCode: 401,
          payload: { error: adminAuth.reason },
          requestId,
        });
        finish(401);
        return;
      }

      writeJson(req, res, config, {
        statusCode: 200,
        payload: metrics.toJSON({
          readyState: rateLimiter.getReadyState(),
          circuitBreaker: { state: circuitBreaker.state },
        }),
        requestId,
      });
      finish(200);
      return;
    }

    if (!['/api/tags', '/api/chat'].includes(path)) {
      writeJson(req, res, config, {
        statusCode: 404,
        payload: { error: 'Not found' },
        requestId,
      });
      finish(404);
      return;
    }

    const auth = authenticateRequest(req, config);
    if (!auth.ok) {
      writeJson(req, res, config, {
        statusCode: 401,
        payload: { error: auth.reason },
        requestId,
      });
      finish(401);
      return;
    }

    const rateKey = `${auth.principal.sub || clientIp}:${route}`;
    const rl = await rateLimiter.check(rateKey);
    if (!rl.allowed) {
      metrics.recordRateLimited();
      setCommonHeaders(req, res, config, requestId);
      const retryAfter = Math.max(1, Math.ceil((rl.resetAt - Date.now()) / 1000));
      res.writeHead(429, {
        'content-type': 'application/json; charset=utf-8',
        'retry-after': retryAfter,
        'x-ratelimit-remaining': String(rl.remaining),
      });
      res.end(JSON.stringify({ error: 'Too many requests' }));
      finish(429);
      return;
    }

    try {
      let statusCode = 500;
      if (path === '/api/tags' && method === 'GET') {
        statusCode = await relayTags({ req, res, requestId, route });
      } else if (path === '/api/chat' && method === 'POST') {
        statusCode = await relayChat({ req, res, requestId, route });
      } else {
        writeJson(req, res, config, {
          statusCode: 405,
          payload: { error: 'Method not allowed' },
          requestId,
        });
        statusCode = 405;
      }
      finish(statusCode);
    } catch (err) {
      logger.error('Unhandled request failure', { requestId, error: String(err) });
      writeJson(req, res, config, {
        statusCode: 500,
        payload: { error: 'Internal server error' },
        requestId,
      });
      finish(500);
    }
  }

  const server = http.createServer((req, res) => {
    handler(req, res).catch((err) => {
      const requestId = crypto.randomUUID();
      logger.error('Unhandled server error', { requestId, error: String(err) });
      writeJson(req, res, config, {
        statusCode: 500,
        payload: { error: 'Internal server error' },
        requestId,
      });
    });
  });

  return {
    server,
    metrics,
    circuitBreaker,
    async close() {
      await new Promise((resolve) => server.close(resolve));
      await rateLimiter.close();
    },
  };
}

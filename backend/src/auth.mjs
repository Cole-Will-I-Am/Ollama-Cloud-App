import crypto from 'node:crypto';

function base64UrlDecode(input) {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(input.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64').toString('utf8');
}

function parseBearer(req) {
  const auth = req.headers.authorization;
  if (typeof auth !== 'string') {
    return null;
  }
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  return match[1].trim();
}

function timingSafeEqual(a, b) {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

function signHS256(message, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(message)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function verifyJwtHs256(token, config) {
  const parts = token.split('.');
  if (parts.length !== 3) {
    return { ok: false, reason: 'Malformed JWT' };
  }

  const [headerB64, payloadB64, signatureB64] = parts;
  let header;
  let payload;

  try {
    header = JSON.parse(base64UrlDecode(headerB64));
    payload = JSON.parse(base64UrlDecode(payloadB64));
  } catch {
    return { ok: false, reason: 'Invalid JWT encoding' };
  }

  if (header.alg !== 'HS256') {
    return { ok: false, reason: 'Unsupported JWT algorithm' };
  }

  const expectedSignature = signHS256(`${headerB64}.${payloadB64}`, config.jwtHs256Secret);
  if (!timingSafeEqual(expectedSignature, signatureB64)) {
    return { ok: false, reason: 'Invalid JWT signature' };
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp <= now) {
    return { ok: false, reason: 'JWT expired' };
  }

  if (typeof payload.nbf === 'number' && payload.nbf > now) {
    return { ok: false, reason: 'JWT not active yet' };
  }

  if (config.jwtIssuer && payload.iss !== config.jwtIssuer) {
    return { ok: false, reason: 'Invalid JWT issuer' };
  }

  if (config.jwtAudience) {
    const aud = payload.aud;
    const valid = Array.isArray(aud) ? aud.includes(config.jwtAudience) : aud === config.jwtAudience;
    if (!valid) {
      return { ok: false, reason: 'Invalid JWT audience' };
    }
  }

  return {
    ok: true,
    principal: {
      sub: typeof payload.sub === 'string' ? payload.sub : 'anonymous',
      scope: payload.scope,
      claims: payload,
      authType: 'jwt',
    },
  };
}

export function authenticateRequest(req, config) {
  if (config.authMode === 'none') {
    return {
      ok: true,
      principal: {
        sub: req.socket.remoteAddress || 'anonymous',
        authType: 'none',
      },
    };
  }

  const token = parseBearer(req);
  if (!token) {
    return { ok: false, reason: 'Missing bearer token' };
  }

  if (config.authMode === 'static') {
    if (!timingSafeEqual(token, config.backendBearerToken)) {
      return { ok: false, reason: 'Invalid bearer token' };
    }
    return {
      ok: true,
      principal: {
        sub: 'static-token-client',
        authType: 'static',
      },
    };
  }

  return verifyJwtHs256(token, config);
}

export function authenticateAdmin(req, config) {
  const token = parseBearer(req);
  const adminToken = config.adminBearerToken;

  if (!adminToken) {
    return { ok: false, reason: 'Admin token is not configured' };
  }

  if (!token || !timingSafeEqual(token, adminToken)) {
    return { ok: false, reason: 'Invalid admin token' };
  }

  return { ok: true };
}

export function resolveUpstreamKey(req, config) {
  if (config.upstreamApiKey) {
    return config.upstreamApiKey;
  }

  const explicit = req.headers['x-ollama-key'];
  if (typeof explicit === 'string' && explicit.trim().length > 0) {
    return explicit.trim();
  }

  if (config.allowCompatibilityBearerAsUpstreamKey && config.authMode === 'none') {
    const token = parseBearer(req);
    if (token) return token;
  }

  return '';
}

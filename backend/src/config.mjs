const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on']);

function parseBool(value, defaultValue = false) {
  if (value == null || value === '') return defaultValue;
  return TRUE_VALUES.has(String(value).toLowerCase());
}

function parseIntStrict(name, value, fallback) {
  const raw = value ?? fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

function parseCsvSet(value) {
  return new Set(
    String(value || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );
}

function parseCsvArray(value) {
  return String(value || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function requiredWhenProduction(name, value, nodeEnv) {
  if (nodeEnv === 'production' && (!value || String(value).trim() === '')) {
    throw new Error(`${name} is required in production`);
  }
}

export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV || 'development';
  const authMode = (env.AUTH_MODE || 'none').trim().toLowerCase();

  if (!['none', 'static', 'jwt'].includes(authMode)) {
    throw new Error(`AUTH_MODE must be one of: none, static, jwt`);
  }

  const config = {
    nodeEnv,
    port: parseIntStrict('PORT', env.PORT, 8787),
    host: env.HOST || '0.0.0.0',
    upstreamBaseUrl: (env.OLLAMA_UPSTREAM || 'https://ollama.com').replace(/\/$/, ''),
    upstreamTimeoutMs: parseIntStrict('UPSTREAM_TIMEOUT_MS', env.UPSTREAM_TIMEOUT_MS, 30000),
    upstreamRetryMax: parseIntStrict('UPSTREAM_RETRY_MAX', env.UPSTREAM_RETRY_MAX, 2),
    upstreamRetryBaseMs: parseIntStrict('UPSTREAM_RETRY_BASE_MS', env.UPSTREAM_RETRY_BASE_MS, 250),
    maxBodyBytes: parseIntStrict('MAX_BODY_BYTES', env.MAX_BODY_BYTES, 1_000_000),
    trustProxy: parseBool(env.TRUST_PROXY, false),
    corsAllowedOrigins: parseCsvArray(env.CORS_ALLOWED_ORIGINS),
    securityHeaders: parseBool(env.SECURITY_HEADERS, true),

    authMode,
    backendBearerToken: env.BACKEND_BEARER_TOKEN || '',
    jwtIssuer: env.JWT_ISSUER || '',
    jwtAudience: env.JWT_AUDIENCE || '',
    jwtHs256Secret: env.JWT_HS256_SECRET || '',

    upstreamApiKey: env.UPSTREAM_API_KEY || '',
    allowCompatibilityBearerAsUpstreamKey: parseBool(env.ALLOW_COMPAT_BEARER_KEY, true),

    rateLimitWindowMs: parseIntStrict('RATE_LIMIT_WINDOW_MS', env.RATE_LIMIT_WINDOW_MS, 60_000),
    rateLimitMax: parseIntStrict('RATE_LIMIT_MAX', env.RATE_LIMIT_MAX, 60),
    rateLimitPrefix: env.RATE_LIMIT_PREFIX || 'rl',
    redisUrl: env.REDIS_URL || '',

    circuitFailureThreshold: parseIntStrict('CIRCUIT_FAILURE_THRESHOLD', env.CIRCUIT_FAILURE_THRESHOLD, 5),
    circuitOpenMs: parseIntStrict('CIRCUIT_OPEN_MS', env.CIRCUIT_OPEN_MS, 15000),

    allowedModels: parseCsvSet(env.ALLOWED_MODELS),

    adminBearerToken: env.ADMIN_BEARER_TOKEN || '',
  };

  if (config.authMode === 'static') {
    requiredWhenProduction('BACKEND_BEARER_TOKEN', config.backendBearerToken, nodeEnv);
  }

  if (config.authMode === 'jwt') {
    requiredWhenProduction('JWT_ISSUER', config.jwtIssuer, nodeEnv);
    requiredWhenProduction('JWT_AUDIENCE', config.jwtAudience, nodeEnv);
    requiredWhenProduction('JWT_HS256_SECRET', config.jwtHs256Secret, nodeEnv);
    if (!config.jwtHs256Secret) {
      throw new Error('JWT_HS256_SECRET is required when AUTH_MODE=jwt');
    }
  }

  if (nodeEnv === 'production' && config.authMode === 'none') {
    throw new Error('AUTH_MODE=none is not allowed in production');
  }

  if (nodeEnv === 'production') {
    requiredWhenProduction('REDIS_URL', config.redisUrl, nodeEnv);
    if (!config.upstreamApiKey && !config.allowCompatibilityBearerAsUpstreamKey) {
      throw new Error('Set UPSTREAM_API_KEY or enable ALLOW_COMPAT_BEARER_KEY in production');
    }
  }

  return config;
}

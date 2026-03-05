function isRetriableStatus(status) {
  return status === 408 || status === 429 || (status >= 500 && status <= 599);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function jitter(baseMs) {
  const delta = Math.floor(Math.random() * Math.max(1, Math.floor(baseMs * 0.4)));
  return baseMs + delta;
}

function fetchWithTimeout(url, options, timeoutMs, fetchImpl = fetch) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  return fetchImpl(url, { ...options, signal: controller.signal }).finally(() => clearTimeout(timer));
}

export class CircuitBreaker {
  constructor({ failureThreshold, openMs }) {
    this.failureThreshold = failureThreshold;
    this.openMs = openMs;
    this.failures = 0;
    this.openUntil = 0;
  }

  get state() {
    if (Date.now() < this.openUntil) return 'open';
    if (this.failures > 0) return 'closed-degraded';
    return 'closed';
  }

  canRequest() {
    return Date.now() >= this.openUntil;
  }

  onSuccess() {
    this.failures = 0;
    this.openUntil = 0;
  }

  onFailure() {
    this.failures += 1;
    if (this.failures >= this.failureThreshold) {
      this.openUntil = Date.now() + this.openMs;
    }
  }
}

export async function fetchWithRetry({
  url,
  options,
  timeoutMs,
  retryMax,
  retryBaseMs,
  circuitBreaker,
  fetchImpl = fetch,
  logger,
  requestId,
  route,
}) {
  if (circuitBreaker && !circuitBreaker.canRequest()) {
    const err = new Error('Circuit is open');
    err.code = 'CIRCUIT_OPEN';
    throw err;
  }

  let attempt = 0;
  let lastError = null;

  while (attempt <= retryMax) {
    try {
      const response = await fetchWithTimeout(url, options, timeoutMs, fetchImpl);
      if (isRetriableStatus(response.status) && attempt < retryMax) {
        const delayMs = jitter(retryBaseMs * (2 ** attempt));
        await sleep(delayMs);
        attempt += 1;
        continue;
      }

      if (response.status >= 200 && response.status < 500) {
        circuitBreaker?.onSuccess();
      } else if (response.status >= 500) {
        circuitBreaker?.onFailure();
      }

      return response;
    } catch (err) {
      lastError = err;
      const isAbort = err && err.name === 'AbortError';

      if (attempt >= retryMax) {
        circuitBreaker?.onFailure();
        break;
      }

      const delayMs = jitter(retryBaseMs * (2 ** attempt));
      logger?.warn('Upstream request failed; retrying', {
        requestId,
        route,
        attempt,
        delayMs,
        isAbort,
        error: String(err),
      });

      await sleep(delayMs);
      attempt += 1;
    }
  }

  throw lastError || new Error('Upstream request failed');
}

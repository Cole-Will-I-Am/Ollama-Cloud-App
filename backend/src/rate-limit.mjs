import Redis from 'ioredis';

export class MemoryRateLimiter {
  constructor({ windowMs, max }) {
    this.windowMs = windowMs;
    this.max = max;
    this.buckets = new Map();
  }

  async check(key) {
    const now = Date.now();
    const current = this.buckets.get(key);

    if (!current || now > current.resetAt) {
      this.buckets.set(key, { count: 1, resetAt: now + this.windowMs });
      return { allowed: true, remaining: this.max - 1, resetAt: now + this.windowMs };
    }

    current.count += 1;
    const remaining = Math.max(0, this.max - current.count);
    return {
      allowed: current.count <= this.max,
      remaining,
      resetAt: current.resetAt,
    };
  }

  getReadyState() {
    return { provider: 'memory', ready: true };
  }

  async close() {
    // no-op
  }
}

export class RedisRateLimiter {
  constructor({ redisUrl, windowMs, max, prefix = 'rl', logger }) {
    this.windowMs = windowMs;
    this.max = max;
    this.prefix = prefix;
    this.logger = logger;
    this.client = new Redis(redisUrl, {
      maxRetriesPerRequest: 2,
      enableReadyCheck: true,
      lazyConnect: false,
    });
    this.client.on('error', (err) => {
      this.logger?.error('Redis rate limiter error', { error: String(err) });
    });
  }

  windowKey(key) {
    const bucket = Math.floor(Date.now() / this.windowMs);
    return `${this.prefix}:${bucket}:${key}`;
  }

  async check(key) {
    const windowKey = this.windowKey(key);
    const now = Date.now();
    const ttlSeconds = Math.ceil(this.windowMs / 1000) + 1;

    const result = await this.client
      .multi()
      .incr(windowKey)
      .expire(windowKey, ttlSeconds)
      .exec();
    if (!result) {
      throw new Error('Redis transaction failed');
    }
    const [count] = result.map((r) => r[1]);

    const used = Number(count || 0);
    const remaining = Math.max(0, this.max - used);

    return {
      allowed: used <= this.max,
      remaining,
      resetAt: now + this.windowMs,
    };
  }

  getReadyState() {
    const status = this.client.status;
    return { provider: 'redis', ready: status === 'ready', status };
  }

  async close() {
    try {
      await this.client.quit();
    } catch {
      this.client.disconnect();
    }
  }
}

export function createRateLimiter(config, logger) {
  if (!config.redisUrl) {
    logger.warn('Redis not configured; using in-memory rate limiter');
    return new MemoryRateLimiter({ windowMs: config.rateLimitWindowMs, max: config.rateLimitMax });
  }

  logger.info('Using Redis rate limiter', { redisConfigured: true });
  return new RedisRateLimiter({
    redisUrl: config.redisUrl,
    windowMs: config.rateLimitWindowMs,
    max: config.rateLimitMax,
    prefix: config.rateLimitPrefix,
    logger,
  });
}

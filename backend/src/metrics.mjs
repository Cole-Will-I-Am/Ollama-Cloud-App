export class Metrics {
  constructor() {
    this.startedAt = new Date().toISOString();
    this.requests = 0;
    this.byRoute = {};
    this.byStatus = {};
    this.rateLimited = 0;
    this.upstreamErrors = 0;
    this.latencyMs = {
      count: 0,
      sum: 0,
      max: 0,
    };
  }

  record(route, statusCode, durationMs = 0) {
    this.requests += 1;
    this.byRoute[route] = (this.byRoute[route] || 0) + 1;
    this.byStatus[statusCode] = (this.byStatus[statusCode] || 0) + 1;
    this.latencyMs.count += 1;
    this.latencyMs.sum += durationMs;
    this.latencyMs.max = Math.max(this.latencyMs.max, durationMs);
  }

  recordRateLimited() {
    this.rateLimited += 1;
  }

  recordUpstreamError() {
    this.upstreamErrors += 1;
  }

  toJSON(extra = {}) {
    const avgLatency = this.latencyMs.count ? this.latencyMs.sum / this.latencyMs.count : 0;
    return {
      startedAt: this.startedAt,
      requests: this.requests,
      byRoute: this.byRoute,
      byStatus: this.byStatus,
      rateLimited: this.rateLimited,
      upstreamErrors: this.upstreamErrors,
      latencyMs: {
        avg: Number(avgLatency.toFixed(2)),
        max: this.latencyMs.max,
      },
      ...extra,
    };
  }
}

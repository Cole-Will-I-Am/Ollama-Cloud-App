# Ollama Cloud Relay Backend

Production-focused relay for the iOS app.

## Features

- Auth modes: `none`, `static`, `jwt (HS256)`
- Distributed rate limiting (Redis) with memory fallback for local dev
- Upstream retry + timeout + circuit breaker
- Security headers and optional CORS allowlist
- Request ID propagation and structured JSON logs
- Readiness/liveness endpoints
- Admin metrics endpoint
- Graceful shutdown

## Endpoints

- `GET /health` and `GET /health/live`
- `GET /health/ready`
- `GET /api/tags`
- `POST /api/chat` (stream passthrough)
- `GET /admin/metrics` (admin token required)

## Local Run

```bash
cd backend
cp .env.example .env
# edit .env as needed
set -a && source .env && set +a
npm install
npm run start
```

## Production Baseline Config

Set these at minimum:

- `NODE_ENV=production`
- `AUTH_MODE=static` or `AUTH_MODE=jwt`
- `REDIS_URL=redis://...`
- `UPSTREAM_API_KEY=...` (recommended)
- `ADMIN_BEARER_TOKEN=...`

If `AUTH_MODE=static`, set `BACKEND_BEARER_TOKEN`.
If `AUTH_MODE=jwt`, set `JWT_ISSUER`, `JWT_AUDIENCE`, `JWT_HS256_SECRET`.

## Auth Behavior

### AUTH_MODE=none (dev only)
- No backend auth enforced.
- If `UPSTREAM_API_KEY` is unset, bearer token can be used as upstream key when `ALLOW_COMPAT_BEARER_KEY=1`.

### AUTH_MODE=static
- Require `Authorization: Bearer <BACKEND_BEARER_TOKEN>`.
- Upstream key comes from `UPSTREAM_API_KEY` or `X-Ollama-Key`.

### AUTH_MODE=jwt
- Require JWT bearer token validated against HS256 config.
- Upstream key comes from `UPSTREAM_API_KEY` or `X-Ollama-Key`.

## Container Deployment

Use included `Dockerfile` and optional `docker-compose.yml`.

```bash
docker compose up --build
```

## Testing

```bash
npm test
npm run smoke
```

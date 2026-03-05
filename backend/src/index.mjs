import { loadConfig } from './config.mjs';
import { createLogger } from './logger.mjs';
import { createRateLimiter } from './rate-limit.mjs';
import { createApp } from './server.mjs';

const config = loadConfig(process.env);
const logger = createLogger({ service: 'ollama-cloud-relay', env: config.nodeEnv });
const rateLimiter = createRateLimiter(config, logger);
const app = createApp({ config, logger, rateLimiter, fetchImpl: fetch });

app.server.listen(config.port, config.host, () => {
  logger.info('Relay server started', {
    host: config.host,
    port: config.port,
    upstreamBaseUrl: config.upstreamBaseUrl,
    authMode: config.authMode,
    redisConfigured: Boolean(config.redisUrl),
    allowlistSize: config.allowedModels.size,
    seerModelEnabled: config.seerModelEnabled,
    seerAliasName: config.seerAliasName,
    seerUpstreamModel: config.seerUpstreamModel,
  });
});

let shuttingDown = false;

async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.warn('Shutting down', { signal });
  try {
    await app.close();
    logger.info('Shutdown complete');
    process.exit(0);
  } catch (err) {
    logger.error('Shutdown failed', { error: String(err) });
    process.exit(1);
  }
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

function redactValue(key, value) {
  if (value == null) return value;
  const lower = key.toLowerCase();
  if (lower.includes('token') || lower.includes('key') || lower.includes('authorization') || lower.includes('secret')) {
    return '[REDACTED]';
  }
  return value;
}

function redactObject(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    out[k] = redactValue(k, v);
  }
  return out;
}

export function createLogger(base = {}) {
  function write(level, message, fields = {}) {
    const line = {
      ts: new Date().toISOString(),
      level,
      message,
      ...redactObject(base),
      ...redactObject(fields),
    };
    process.stdout.write(`${JSON.stringify(line)}\n`);
  }

  return {
    info: (message, fields) => write('info', message, fields),
    warn: (message, fields) => write('warn', message, fields),
    error: (message, fields) => write('error', message, fields),
    debug: (message, fields) => write('debug', message, fields),
  };
}

import test from 'node:test';
import assert from 'node:assert/strict';

import { fetchWithRetry } from '../src/upstream.mjs';

function makeLogger() {
  return {
    info() {},
    warn() {},
    error() {},
    debug() {},
  };
}

test('fetchWithRetry does not execute when client signal is already aborted', async () => {
  const signalController = new AbortController();
  signalController.abort(new Error('client disconnected'));
  let calls = 0;

  await assert.rejects(
    fetchWithRetry({
      url: 'https://example.com',
      options: { method: 'GET' },
      timeoutMs: 100,
      retryMax: 3,
      retryBaseMs: 10,
      fetchImpl: async () => {
        calls += 1;
        return new Response(null, { status: 200 });
      },
      signal: signalController.signal,
      logger: makeLogger(),
      requestId: 'r1',
      route: '/api/tags',
    }),
    (err) => err && err.code === 'CLIENT_ABORTED',
  );

  assert.equal(calls, 0);
});

test('fetchWithRetry stops retries when client disconnects during request', async () => {
  const signalController = new AbortController();
  let calls = 0;

  const pendingAbort = fetchWithRetry({
    url: 'https://example.com',
    options: { method: 'GET' },
    timeoutMs: 1000,
    retryMax: 3,
    retryBaseMs: 10,
    fetchImpl: async (_url, options) => {
      calls += 1;
      return new Promise((_resolve, reject) => {
        options.signal.addEventListener(
          'abort',
          () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })),
          { once: true },
        );
      });
    },
    signal: signalController.signal,
    logger: makeLogger(),
    requestId: 'r2',
    route: '/api/chat',
  });

  setTimeout(() => {
    signalController.abort(new Error('client disconnected'));
  }, 5);

  await assert.rejects(
    pendingAbort,
    (err) => err && err.code === 'CLIENT_ABORTED',
  );
  assert.equal(calls, 1);
});

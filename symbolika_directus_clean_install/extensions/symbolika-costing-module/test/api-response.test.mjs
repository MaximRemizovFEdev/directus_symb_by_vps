import assert from 'node:assert/strict';
import test from 'node:test';

import { directusErrorMessage, parseDirectusResponse } from '../lib/api-response.js';

function response({ ok, payload, invalidJson = false }) {
  return {
    ok,
    json: async () => {
      if (invalidJson) throw new Error('invalid json');
      return payload;
    },
  };
}

test('uses the first Directus error before the generic payload message', () => {
  const payload = { errors: [{ message: 'Field is forbidden' }], message: 'Generic error' };
  assert.equal(directusErrorMessage(payload, 'Fallback'), 'Field is forbidden');
});

test('can preserve upload fallback behavior without using payload message', () => {
  assert.equal(
    directusErrorMessage({ message: 'Generic error' }, 'Upload failed', { includePayloadMessage: false }),
    'Upload failed',
  );
});

test('returns a successful Directus payload', async () => {
  const payload = { data: { id: 42 } };
  assert.deepEqual(await parseDirectusResponse(response({ ok: true, payload }), 'Request failed'), payload);
});

test('throws the configured fallback for an invalid error response', async () => {
  await assert.rejects(
    parseDirectusResponse(response({ ok: false, invalidJson: true }), 'Request failed'),
    /Request failed/,
  );
});

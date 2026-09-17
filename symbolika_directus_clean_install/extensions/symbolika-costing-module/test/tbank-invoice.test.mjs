import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleUrl = new URL('../index.js', import.meta.url);
const composeUrl = new URL('../../../docker-compose.yml', import.meta.url);

test('order card creates a T-Bank SBP payment link through the protected server endpoint', async () => {
  const source = await readFile(moduleUrl, 'utf8');

  assert.match(source, /Создать ссылку на оплату/);
  assert.match(source, /\/symbolika-tbank\/orders\/\$\{orderId\}\/preview/);
  assert.match(source, /\/symbolika-tbank\/orders\/\$\{dialog\.orderId\}\/payment-link/);
  assert.match(source, /tbankInvoiceDialog\.items/);
  assert.match(source, /copyTbankPaymentLink/);
  assert.doesNotMatch(source, /TBANK_TOKEN\s*=/);
});

test('T-Bank acquiring credentials are injected only through server environment variables', async () => {
  const compose = await readFile(composeUrl, 'utf8');

  assert.match(compose, /SYMBOLIKA_TBANK_TERMINAL_KEY: "\$\{SYMBOLIKA_TBANK_TERMINAL_KEY:-\}"/);
  assert.match(compose, /SYMBOLIKA_TBANK_TERMINAL_PASSWORD: "\$\{SYMBOLIKA_TBANK_TERMINAL_PASSWORD:-\}"/);
  assert.match(compose, /NODE_EXTRA_CA_CERTS: "\/directus\/setup\/certs\/russian-trusted-ca-bundle\.pem"/);
  assert.doesNotMatch(compose, /Bearer\s+t\.[A-Za-z0-9_-]{20,}/);
});

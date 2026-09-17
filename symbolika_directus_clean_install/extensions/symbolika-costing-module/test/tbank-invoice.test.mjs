import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleUrl = new URL('../index.js', import.meta.url);
const composeUrl = new URL('../../../docker-compose.yml', import.meta.url);

test('order card creates a T-Bank invoice through the protected server endpoint', async () => {
  const source = await readFile(moduleUrl, 'utf8');

  assert.match(source, /Создать ссылку на оплату/);
  assert.match(source, /\/symbolika-tbank\/orders\/\$\{orderId\}\/preview/);
  assert.match(source, /\/symbolika-tbank\/orders\/\$\{dialog\.orderId\}\/invoice/);
  assert.match(source, /tbankInvoiceDialog\.items/);
  assert.match(source, /copyTbankPaymentLink/);
  assert.doesNotMatch(source, /TBANK_TOKEN\s*=/);
});

test('T-Bank credentials are injected only through server environment variables', async () => {
  const compose = await readFile(composeUrl, 'utf8');

  assert.match(compose, /SYMBOLIKA_TBANK_TOKEN: "\$\{SYMBOLIKA_TBANK_TOKEN:-\}"/);
  assert.match(compose, /SYMBOLIKA_TBANK_ACCOUNT_NUMBER: "\$\{SYMBOLIKA_TBANK_ACCOUNT_NUMBER:-\}"/);
  assert.doesNotMatch(compose, /Bearer\s+t\.[A-Za-z0-9_-]{20,}/);
});

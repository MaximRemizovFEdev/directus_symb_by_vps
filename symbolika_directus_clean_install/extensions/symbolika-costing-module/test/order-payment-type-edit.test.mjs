import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order pages load payment types and expose the selector in the order card', () => {
  assert.match(
    source,
    /allowed\.has\('my_orders'\) \|\| allowed\.has\('all_orders'\)\) tasks\.push\(this\.loadGiftCertificates\(\), this\.loadPaymentTypes\(\)\)/,
  );
  assert.match(source, /<div class="symbolika-costing-detail-label">Тип оплаты<\/div>/);
  assert.match(source, /@change="saveOrderField\(detail\.row, 'payment_type', \$event\.target\.value\)"/);
});

test('payment type editing follows the same owner boundary as other order fields', () => {
  assert.match(source, /canEditOrderPaymentType\(row\) \{/);
  assert.match(
    source,
    /canEditOrderPaymentType\(row\)[\s\S]*?this\.hasManagerOverrideAccess[\s\S]*?this\.orderBelongsToCurrentEmployee\(row\)/,
  );
  assert.match(source, /\['order_status', 'payment_type'\]\.includes\(field\)/);
});

test('order-bound payments send only the canonical order relation', () => {
  const createBranch = source.match(/await this\.request\('\/items\/order_payments', \{[\s\S]*?\n\s*\}\);/u)?.[0] || '';
  assert.match(createBranch, /order: orderId/);
  assert.doesNotMatch(createBranch, /customer:/);
  assert.doesNotMatch(createBranch, /customer_company:/);
});

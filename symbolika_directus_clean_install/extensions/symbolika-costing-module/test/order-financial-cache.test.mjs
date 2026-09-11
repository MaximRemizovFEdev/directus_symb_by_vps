import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../index.js', import.meta.url), 'utf8');

test('refreshes displayed order totals from the complete item list', () => {
  assert.match(
    source,
    /this\.syncOrderFinancialCacheFromItems\(row, this\.detailOrderItems\);/,
  );
  assert.match(
    source,
    /const activeItems = items\.filter[\s\S]*?const orderSum = activeItems\.reduce[\s\S]*?payment_due: orderSum - paidAmount/,
  );
});

test('keeps a newly created order total consistent after list reload', () => {
  const createOrder = source.match(/async createOrderWithItems\(\)[\s\S]*?\n    estimateItems\(row\)/)?.[0] || '';
  assert.match(createOrder, /await this\.loadAllowedData\(\);[\s\S]*?this\.syncOrderFinancialCacheFromItems/);
  assert.match(createOrder, /createdItems\.map\(\(\{ item \}\) => item\)/);
});

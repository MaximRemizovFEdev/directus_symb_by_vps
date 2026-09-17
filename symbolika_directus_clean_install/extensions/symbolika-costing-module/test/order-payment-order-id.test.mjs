import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('freezes a valid numeric order id when the payment dialog opens', () => {
  assert.match(source, /orderId: this\.paymentOrderId\(row, options\.orderIssueOrderId\)/);
  assert.match(source, /paymentOrderId\(row, explicitOrderId = null\)/);
  assert.match(source, /Number\.isInteger\(id\) && id > 0/);
});

test('sends the frozen numeric order id when an order payment is created', () => {
  assert.match(source, /this\.paymentOrderId\(row, this\.paymentDialog\.orderId \|\| orderIssueOrderId\)/);
  assert.match(source, /body: JSON\.stringify\(\{[\s\S]*?order: orderId,[\s\S]*?allocation_mode: 'to_order'/);
});

test('migration makes an allocation order optional in Directus metadata', () => {
  const migration = readFileSync(
    new URL('../../../setup/migrations/20260910_fix_manager_order_payment.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /ALTER TABLE payment_allocations ALTER COLUMN "order" DROP NOT NULL/);
  assert.match(migration, /UPDATE directus_fields[\s\S]*?SET required = false[\s\S]*?collection = 'payment_allocations'[\s\S]*?field = 'order'/);
});

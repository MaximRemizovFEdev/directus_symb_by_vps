import assert from 'node:assert/strict';
import test from 'node:test';

import {
  autoAllocateClientPayment,
  clientPaymentAllocationSummary,
  clientPaymentTargets,
} from '../lib/client-payment.js';

test('builds targets for one payer from orders and receivable client operations', () => {
  const targets = clientPaymentTargets([
    { entry_type: 'order', order_link: 10, order_number: 'SO-10', customer: 1, payment_due: 300, date: '2026-09-01' },
    { entry_type: 'operation', client_operation: 20, customer: 1, direction: 'customer_owes_us', payment_due: 200, description: 'Покупка' },
    { entry_type: 'operation', client_operation: 21, customer: 1, direction: 'we_owe_customer', payment_due: -100 },
    { entry_type: 'order', order_link: 11, customer: 2, payment_due: 400 },
  ], { customerId: 1 });

  assert.deepEqual(targets.map((row) => row.key), ['operation:20', 'order:10']);
});

test('allocates sequentially and keeps excess as customer advance', () => {
  const targets = autoAllocateClientPayment([
    { key: 'order:1', due: 300 },
    { key: 'operation:2', due: 200 },
  ], 600);
  const summary = clientPaymentAllocationSummary(targets, 600);

  assert.deepEqual(targets.map((row) => row.allocation), ['300', '200']);
  assert.equal(summary.allocated, 500);
  assert.equal(summary.unallocated, 100);
  assert.equal(summary.exceedsPayment, false);
});

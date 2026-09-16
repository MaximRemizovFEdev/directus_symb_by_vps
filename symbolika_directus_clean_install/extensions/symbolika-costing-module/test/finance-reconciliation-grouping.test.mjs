import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { CostingModule } from '../index.js';

function financeContext(filter) {
  return {
    ...CostingModule.methods,
    financeDebtFilter: filter,
    customers: [
      { id: 10, balance: -1200 },
      { id: 11, balance: 450 },
      { id: 12, balance: 0 },
    ],
    companies: [
      { id: 20, balance: -3000 },
      { id: 21, balance: 700 },
    ],
  };
}

test('debt-side filter uses the payer net balance', () => {
  const customerDebt = financeContext('customer_owes_us');
  assert.equal(customerDebt.matchesFinanceDebtFilter({ customer: 10 }), true);
  assert.equal(customerDebt.matchesFinanceDebtFilter({ customer: 11 }), false);
  assert.equal(customerDebt.matchesFinanceDebtFilter({ customer_company: 20, customer: 11 }), true);

  const companyDebt = financeContext('we_owe_customer');
  assert.equal(companyDebt.matchesFinanceDebtFilter({ customer_company: 21 }), true);
  assert.equal(companyDebt.matchesFinanceDebtFilter({ customer_company: 20 }), false);

  const settled = financeContext('settled');
  assert.equal(settled.matchesFinanceDebtFilter({ customer: 12 }), true);
  assert.equal(settled.matchesFinanceDebtFilter({ customer: 10 }), false);
});

test('all company orders are reduced to one payer row', () => {
  const context = {
    ...financeContext('all'),
    visibleFinanceRows: [
      { id: 1, entry_type: 'order', customer: 10, customer_name: 'Первый контакт', customer_company: 20, customer_company_name: 'Компания', manager_name: 'Менеджер', order_sum: 1000, paid_amount: 200, payment_due: 800, overpayment: 0 },
      { id: 2, entry_type: 'order', customer: 11, customer_name: 'Второй контакт', customer_company: 20, customer_company_name: 'Компания', manager_name: 'Менеджер', order_sum: 2500, paid_amount: 500, payment_due: 2000, overpayment: 0 },
    ],
    giftCertificates: [],
    customerGiftCertificateSummary: () => ({ count: 0, activeCount: 0, nominal: 0, remaining: 0 }),
  };

  const rows = CostingModule.computed.visibleClientRows.call(context);

  assert.equal(rows.length, 1);
  assert.equal(rows[0].key, 'company:20');
  assert.equal(rows[0].orders.length, 2);
  assert.equal(rows[0].order_sum, 3500);
  assert.equal(rows[0].payment_due, 3000);
});

test('order reconciliation is grouped by payer and exposes expandable details', async () => {
  const source = await readFile(new URL('../index.js', import.meta.url), 'utf8');

  assert.match(source, /<template v-for="row in visibleClientRows" :key="row\.key">/);
  assert.match(source, /symbolika-costing-finance-payers-wrap/);
  assert.match(source, /symbolika-costing-finance-payers/);
  assert.match(source, /symbolika-costing-finance-balance-layout/);
  assert.match(source, /Показать заказы и операции/);
  assert.match(source, /v-for="order in row\.orders"/);
  assert.match(source, /v-for="operation in row\.operations"/);
  assert.match(source, /financeDebtFilter/);
});

test('finance sources are completely loaded before payer grouping', async () => {
  const source = await readFile(new URL('../index.js', import.meta.url), 'utf8');

  assert.match(source, /loadCompletePagedCollection\('finance',/);
  assert.match(source, /loadCompletePagedCollection\('finance_items',/);
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const moduleSource = readFileSync(new URL('../index.js', import.meta.url), 'utf8');
const detailFieldsSource = readFileSync(new URL('../lib/order-detail-fields.js', import.meta.url), 'utf8');
const bootstrapSql = readFileSync(new URL('../../../setup/create-work-views.sql', import.meta.url), 'utf8');
const migrationSql = readFileSync(new URL('../../../setup/migrations/20260916_add_order_1c_invoice_number.sql', import.meta.url), 'utf8');

test('order editor creates, reads, updates and searches by the 1C invoice number', () => {
  assert.match(detailFieldsSource, /'invoice_number_1c'/);
  assert.match(moduleSource, /invoice_number_1c: String\(form\.invoice_number_1c/);
  assert.match(moduleSource, /saveOrderField\(detail\.row, 'invoice_number_1c'/);
  assert.match(moduleSource, /row\.invoice_number_1c/);
  assert.match(moduleSource, /Номер счёта в 1С/);
});

test('database and every order list mirror expose the 1C invoice number', () => {
  for (const sql of [bootstrapSql, migrationSql]) {
    assert.match(sql, /ALTER TABLE orders[\s\S]*invoice_number_1c character varying\(255\)/);
    assert.match(sql, /symbolika_fill_order_invoice_number_1c/);
    assert.match(sql, /my_orders_in_work[\s\S]*invoice_number_1c/);
    assert.match(sql, /orders_overview[\s\S]*invoice_number_1c/);
  }
});

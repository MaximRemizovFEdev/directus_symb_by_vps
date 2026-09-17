import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order view settings are stored separately per user and order page', () => {
  assert.match(source, /symbolika-order-view:v1:\$\{user\}:\$\{tab\}/);
  assert.match(source, /\['all_orders', 'my_orders'\]\.includes\(tab\)/);
  assert.match(source, /persistOrderViewPreferences\(previousTab\)[\s\S]*?restoreOrderViewPreferences\(tab/);
});

test('stored order view includes filters, display mode and both sort contexts', () => {
  for (const field of [
    'activeFilter',
    'orderDeadlineFrom',
    'orderDeadlineTo',
    'orderDateFrom',
    'orderDateTo',
    'orderManagerFilter',
    'orderStatusFilters',
    'officeStatusFilters',
    'orderDisplayMode',
    'orderArchiveMode',
    'orderSort',
    'itemSort',
  ]) {
    assert.match(source, new RegExp(`${field}:`));
  }
});

test('order view settings are restored on mount and flushed before leaving', () => {
  assert.match(source, /this\.restoreOrderViewPreferences\(this\.activeTab\);/);
  assert.match(source, /beforeunload', this\.persistCurrentOrderViewPreferences/);
  assert.match(source, /beforeUnmount\(\)[\s\S]*?this\.persistOrderViewPreferences\(this\.activeTab\)/);
});

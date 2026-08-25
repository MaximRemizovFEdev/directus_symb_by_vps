import assert from 'node:assert/strict';
import test from 'node:test';

import {
  detailEntityType,
  detailIsOrder,
  detailItemId,
} from '../lib/entity-context.js';

test('uses an explicit entity marker before source and row heuristics', () => {
  assert.equal(detailEntityType('orders', { _entity_type: 'item' }), 'item');
  assert.equal(detailEntityType('orders_items', { _entity_type: 'order' }), 'order');
});

test('classifies every supported order and item source', () => {
  const orderSources = ['order', 'orders', 'all_orders', 'my_orders', 'orders_archive', 'office', 'office_issue'];
  const itemSources = ['orders_items', 'costing', 'contractor_costing', 'items_archive', 'production_work', 'screen_printing_work', 'contractor_work'];

  orderSources.forEach((source) => assert.equal(detailEntityType(source, {}), 'order', source));
  itemSources.forEach((source) => assert.equal(detailEntityType(source, {}), 'item', source));
});

test('falls back to stable row-shape heuristics', () => {
  assert.equal(detailEntityType('', { order_item: 15 }), 'item');
  assert.equal(detailEntityType('', { product_name: '' }), 'item');
  assert.equal(detailEntityType('', { order_number: 'SO-00001' }), 'order');
  assert.equal(detailIsOrder(null), true);
});

test('extracts only identifiers that belong to item rows', () => {
  assert.equal(detailItemId({ order_item: { id: 18 }, id: 99 }), '18');
  assert.equal(detailItemId({ _entity_type: 'item', id: 21 }), '21');
  assert.equal(detailItemId({ _entity_type: 'order', id: 21 }), '');
});

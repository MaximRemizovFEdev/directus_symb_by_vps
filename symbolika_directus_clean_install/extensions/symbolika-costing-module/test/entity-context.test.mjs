import assert from 'node:assert/strict';
import test from 'node:test';

import {
  detailEntityType,
  detailIsOrder,
  detailItemId,
  findOrderContext,
  orderId,
  orderItemId,
  orderItemIdentityKey,
  orderNumber,
  orderRowKey,
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

test('normalizes order identifiers and display numbers across row shapes', () => {
  assert.deepEqual(orderId({ order_link: { id: 7 } }), { id: 7 });
  assert.equal(orderId({ id: 8, order_number: 'SO-00008' }), 8);
  assert.equal(orderId({ order: { id: 9 } }), 9);
  assert.equal(orderId({ order: 10 }), 10);
  assert.equal(orderNumber({ order_number: 'SO-00008' }), 'SO-00008');
  assert.equal(orderNumber({ order: { id: 9, order_number: 'SO-00009' } }), 'SO-00009');
  assert.equal(orderNumber({ order: 10 }), '#10');
});

test('builds order keys without confusing item ids with order ids', () => {
  assert.equal(orderRowKey({ order: 5, id: 99, product_name: 'Item' }), '5');
  assert.equal(orderRowKey({ id: 6, order_number: 'SO-00006' }), '6');
  assert.equal(orderRowKey({ id: 6, product_name: 'Item' }), '');
});

test('finds the loaded order context by id or direct order number', () => {
  const byId = { id: 12, order_number: 'SO-00012' };
  const byNumber = { id: 13, order_number: 'SO-00013' };
  const sources = [byId, byNumber];

  assert.equal(findOrderContext({ order: 12, product_name: 'Item' }, sources), byId);
  assert.equal(findOrderContext({ order_number: 'SO-00013', product_name: 'Item' }, sources), byNumber);
  const embedded = { id: 14 };
  assert.equal(findOrderContext({ order_context: embedded }, sources), embedded);
});

test('builds one stable identity for an order item across Directus row shapes', () => {
  assert.equal(orderItemId({ order_item: { id: 18 }, id: 99 }), '18');
  assert.equal(orderItemIdentityKey({ order_item: 18, product_name: 'Ignored' }), 'id:18');
  assert.equal(orderItemIdentityKey({ id: 21, product_name: 'Ignored' }), 'id:21');
});

test('uses normalized product and quantity only when an item id is unavailable', () => {
  const item = { order_number: 'SO-00007', product_name: '  Блокноты A5  ', quantity: '12,50' };
  assert.equal(orderItemIdentityKey(item), 'блокноты a5:12,5');
  assert.equal(orderItemIdentityKey(item, { includeOrder: true }), 'SO-00007:блокноты a5:12,5');
  assert.equal(orderItemIdentityKey({ product_name: 'Папка', quantity: 'bad' }), 'папка:0');
});

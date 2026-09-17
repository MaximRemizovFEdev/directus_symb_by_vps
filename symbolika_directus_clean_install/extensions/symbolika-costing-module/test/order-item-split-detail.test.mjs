import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order item opened from an order keeps the linked order panel visible', () => {
  assert.match(source, /detailSplitOrder:\s*null/);
  assert.match(source, /detailPanels\(\)\s*\{[\s\S]*return \[this\.detailSplitOrder, this\.detail\]/);
  assert.match(source, /const opensLinkedOrderItem = entityType === 'item'[\s\S]*options\.returnToParentOrder/);
  assert.match(source, /v-for="detail in detailPanels"/);
  assert.match(source, /@click="closeDetailPanel\(detail\)"/);
});

test('linked detail panels use a desktop split and a sequential mobile layout', () => {
  assert.match(source, /\.symbolika-costing-detail\.is-split-order\s*\{[\s\S]*inset-inline-end: min\(720px, 52vw\)/);
  assert.match(source, /\.symbolika-costing-detail\.is-split-item\s*\{[\s\S]*inline-size: min\(720px, 52vw\)/);
  assert.match(source, /@media \(max-width: 980px\)[\s\S]*\.symbolika-costing-detail\.is-split-order\s*\{\s*display: none/);
});

test('closing an item restores the linked order and its scroll position', () => {
  assert.match(source, /const parentOrder = this\.detailSplitOrder\?\.row \|\| this\.detailParentOrder/);
  assert.match(source, /const parentScrollTop = Number\(document\.querySelector\('aside\.symbolika-costing-detail\.is-split-order'\)/);
  assert.match(source, /if \(orderPanel\) orderPanel\.scrollTop = parentScrollTop/);
});

test('each visible panel receives its own event feed', () => {
  assert.match(source, /detailEventRows\(row = this\.detail\?\.row\)/);
  assert.match(source, /detailEventRows\(detail\.row\)/);
});

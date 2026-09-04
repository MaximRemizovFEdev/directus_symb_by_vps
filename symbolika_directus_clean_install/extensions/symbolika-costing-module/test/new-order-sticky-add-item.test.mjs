import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../index.js', import.meta.url), 'utf8');

test('кнопка добавления позиции закреплена только в новом заказе', () => {
  const stickyHeaders = source.match(/symbolika-costing-new-order-items-head is-sticky-add-item/g) || [];

  assert.equal(stickyHeaders.length, 1);
  assert.match(source, /\.symbolika-costing-new-order-items-head\.is-sticky-add-item\s*\{[\s\S]*?position:\s*sticky;/);
  assert.match(source, /symbolika-costing-order-modal \.symbolika-costing-new-order-items-head\.is-sticky-add-item\s*\{[\s\S]*?inset-block-start:\s*62px;/);
  assert.match(source, /class="symbolika-costing-new-order-items-head is-sticky-add-item"[\s\S]*?@click="addNewOrderItem"/);
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order tables expose ascending and descending deadline and order number sorting', () => {
  assert.match(source, /id: 'deadline_asc', key: 'deadline', direction: 'asc'/);
  assert.match(source, /id: 'deadline_desc', key: 'deadline', direction: 'desc'/);
  assert.match(source, /id: 'order_number_asc', key: 'order_number', direction: 'asc'/);
  assert.match(source, /id: 'order_number_desc', key: 'order_number', direction: 'desc'/);
  assert.match(source, /const option = this\.tableSortOptions\.find/);
  assert.match(source, /const direction = option\?\.direction/);
});

test('positions of the same order keep their creation sequence', () => {
  const sortRows = source.match(/sortRows\(rows, context\) \{(?<body>[\s\S]*?)\n    \},\n\n    positionSortOrderKey/)?.groups?.body || '';
  const orderItems = source.match(/orderItemsForRows\(orderRows\) \{(?<body>[\s\S]*?)\n    \},\n\n    detailPositions/)?.groups?.body || '';

  assert.match(sortRows, /arePositionsFromSameOrder\(left, right\)/);
  assert.match(sortRows, /positionCreationSortValue\(left\)/);
  assert.match(sortRows, /leftSortRow = bothPositions \? this\.detailOrderContext\(left\) : left/);
  assert.doesNotMatch(sortRows, /'product'/);
  assert.match(orderItems, /positionCreationSortValue\(left\)/);
  assert.doesNotMatch(orderItems, /product_name \|\| ''\)\.localeCompare/);
});

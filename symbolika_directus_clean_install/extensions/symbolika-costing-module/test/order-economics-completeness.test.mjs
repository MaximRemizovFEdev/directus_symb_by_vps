import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const moduleSource = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order economics uses its complete item dataset everywhere', () => {
  const itemRowsMethod = moduleSource.match(
    /visibleOrderEconomicsItemRows\(\) \{(?<body>[\s\S]*?)\n    \},\n\n    orderEconomicsManagerOptions/,
  )?.groups?.body || '';
  const orderItemsMethod = moduleSource.match(
    /orderEconomicsItems\(row\) \{(?<body>[\s\S]*?)\n    \},\n\n    orderEconomicsContractors/,
  )?.groups?.body || '';

  assert.match(moduleSource, /loadCompletePagedCollection\('order_economics_items', '\/items\/contractor_costing'/);
  assert.match(itemRowsMethod, /this\.orderEconomicsItemRows/);
  assert.doesNotMatch(itemRowsMethod, /this\.rows/);
  assert.match(orderItemsMethod, /this\.orderEconomicsItemRows/);
  assert.doesNotMatch(orderItemsMethod, /this\.rows/);
  assert.match(moduleSource, /allowed\.has\('order_economics'\)[^\n]*this\.loadOrderEconomicsItemRows\(\)/);
});

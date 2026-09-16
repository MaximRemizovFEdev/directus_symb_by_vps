import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { CostingModule } from '../index.js';

const moduleSource = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('order economics rows expand independently without changing source data', () => {
  const context = {
    expandedOrderEconomicsRows: {},
    entityId: CostingModule.methods.entityId,
    toggleOrderEconomicsRow: CostingModule.methods.toggleOrderEconomicsRow,
    isOrderEconomicsRowExpanded: CostingModule.methods.isOrderEconomicsRowExpanded,
  };
  const row = { id: 83 };

  assert.equal(context.isOrderEconomicsRowExpanded(row), false);
  context.toggleOrderEconomicsRow(row);
  assert.equal(context.isOrderEconomicsRowExpanded(row), true);
  context.toggleOrderEconomicsRow(row);
  assert.equal(context.isOrderEconomicsRowExpanded(row), false);
});

test('grouped economics table shows every item and its financial values', () => {
  assert.match(moduleSource, /toggleOrderEconomicsRow\(row\)/);
  assert.match(moduleSource, /v-for="item in orderEconomicsItems\(row\)"/);
  assert.match(moduleSource, /formatMoney\(item\.order_sum\)/);
  assert.match(moduleSource, /formatMoney\(item\.total_cost\)/);
  assert.match(moduleSource, /formatMoney\(item\.tax_sum\)/);
  assert.match(moduleSource, /orderEconomicsMargin\(item, true\)/);
  assert.match(moduleSource, /colspan="8"/);
});

test('summary remains based on filtered order rows, not expanded state', () => {
  const summaryBlock = moduleSource.match(/orderEconomicsSummary\(\) \{(?<body>[\s\S]*?)\n    \},\n\n    visiblePurchaseRows/)?.groups?.body || '';
  assert.match(summaryBlock, /this\.visibleOrderEconomicsRows/);
  assert.doesNotMatch(summaryBlock, /expandedOrderEconomicsRows/);
});

test('expand column clips overflow without drawing an ellipsis beside the plus button', () => {
  const styleBlock = moduleSource.match(/\.symbolika-economics-expand-column,[\s\S]*?\n        \}/)?.[0] || '';

  assert.match(styleBlock, /max-inline-size: 46px/);
  assert.match(styleBlock, /padding-inline: 8px !important/);
  assert.match(styleBlock, /text-overflow: clip !important/);
  assert.match(styleBlock, /white-space: normal !important/);
  assert.doesNotMatch(styleBlock, /text-overflow: ellipsis/);
});

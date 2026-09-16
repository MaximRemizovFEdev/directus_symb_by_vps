import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { CostingModule } from '../index.js';

const moduleSource = readFileSync(new URL('../index.js', import.meta.url), 'utf8');
const bootstrapSql = readFileSync(new URL('../../../setup/create-work-views.sql', import.meta.url), 'utf8');
const migrationSql = readFileSync(new URL('../../../setup/migrations/20260916_customer_operation_markup.sql', import.meta.url), 'utf8');

test('calculates reconciliation amount from actual expense plus percentage', () => {
  const context = {
    ...CostingModule.methods,
    parseMoney: CostingModule.methods.parseMoney,
  };

  assert.equal(context.clientOperationCalculatedAmount(10000, 20), 12000);
  assert.equal(context.clientOperationCalculatedAmount('1 234,50', '12,5'), 1388.81);
});

test('client operation editor sends source values and shows calculated reconciliation amount', () => {
  assert.match(moduleSource, /actual_amount: actualAmount/);
  assert.match(moduleSource, /markup_percent: markupPercent/);
  assert.match(moduleSource, /Фактический расход/);
  assert.match(moduleSource, /Сумма в сверку/);
  assert.match(moduleSource, /clientOperationCalculatedAmount\(clientOperationDialog\.actualAmount, clientOperationDialog\.markupPercent\)/);
});

test('database remains the source of truth for operation markup', () => {
  for (const source of [bootstrapSql, migrationSql]) {
    assert.match(source, /actual_amount numeric\(14,2\)/);
    assert.match(source, /markup_percent numeric\(7,3\)/);
    assert.match(source, /NEW\.amount := round\(NEW\.actual_amount \* \(1 \+ NEW\.markup_percent \/ 100\), 2\)/);
  }
  assert.match(migrationSql, /SET actual_amount = amount,[\s\S]*markup_percent = 0/);
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('production table controls do not bubble clicks into the row detail action', () => {
  assert.match(
    source,
    /:value="contractorId\(row\.production_status\)"\s+@click\.stop\s+@change\.stop="saveWorkField/,
  );
  assert.match(
    source,
    /:value="row\.production_comment"\s+@click\.stop\s+@change\.stop="saveWorkField/,
  );
});

test('single work field saves reconcile the row from PATCH without reloading the table', () => {
  const method = source.match(/async saveWorkField\(collection, row, field, value\) \{[\s\S]*?\n    \},\n\n    async saveLimitedProductionField/)?.[0] || '';
  assert.match(method, /const previousValue = row\?\.\[field\]/);
  assert.match(method, /const optimisticValue = field === 'production_status'/);
  assert.match(method, /payload\?\.data/);
  assert.match(method, /this\.updateOrderItemCaches\(itemId, \{ \[field\]: savedValue \}\)/);
  assert.doesNotMatch(method, /scheduleBackgroundAreaRefresh\(\);/);
});

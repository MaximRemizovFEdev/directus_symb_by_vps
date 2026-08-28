import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('costing can be filtered by either contractor side', () => {
  assert.match(source, /costingContractorFilter: ''/);
  assert.match(source, /costingFieldsForContractor\(row, contractorId\)/);
  assert.match(source, /row\?\.contractor_1.*contractor_1_cost/s);
  assert.match(source, /row\?\.contractor_2.*contractor_2_cost/s);
  assert.match(source, /aria-label="Фильтр по контрагенту"/);
});

test('bulk costing updates every filtered item at its matching contractor field', () => {
  assert.match(source, /async bulkSetFilteredCostingCost\(\)/);
  assert.match(source, /await this\.loadAllActivePages\(\)/);
  assert.match(source, /Object\.fromEntries\(fields\.map\(\(field\) => \[field, normalizedCost\]\)\)/);
  assert.match(source, /\/items\/orders_items\/\$\{itemId\}/);
  assert.match(source, /Себестоимость обновлена: \$\{targets\.length\} поз\./);
});

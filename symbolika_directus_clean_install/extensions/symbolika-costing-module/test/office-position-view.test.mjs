import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { CostingModule } from '../index.js';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('office position view filters by each position status instead of the order status', () => {
  const method = source.match(
    /officePositionRowsForBucket\(bucket = this\.officeBucket\) \{(?<body>[\s\S]*?)\n    \},\n\n    officeBucketCount/,
  )?.groups?.body || '';

  assert.match(method, /bucket === 'in_office'/);
  assert.match(method, /item\.office_status === 'in_office'/);
  assert.doesNotMatch(method, /order\.office_status === 'in_office'/);
  assert.match(source, /officeViewMode: 'orders'/);
  assert.match(source, /officeViewMode === 'items'/);
  assert.match(source, /v-for="row in visibleOfficePositionRows"/);
  assert.match(source, /officeOrderRowsForBucket\(bucket = this\.officeBucket\)[\s\S]*?officePositionRowsForBucket\(bucket\)/);
  assert.match(source, /visibleOfficeIssueRows\(\)[\s\S]*?officeOrderRowsForBucket\(this\.officeBucket\)/);
});

test('office datasets are fully loaded for reliable order and position counts', () => {
  for (const key of ['office_rows', 'office_issue', 'office_archive', 'office_archive_items']) {
    assert.match(source, new RegExp(`loadCompletePagedCollection\\('${key}'`));
  }
});

test('a partially arrived order is present in both matching office buckets', () => {
  const context = {
    officeIssueRows: [{ id: 10, order_number: 'SO-00010', office_status: 'not_in_office' }],
    officeArchiveRows: [],
    officeArchiveItems: [],
    officeRows: [
      { id: 101, order: 10, office_issue: 10, product_name: 'В офисе', office_status: 'in_office' },
      { id: 102, order: 10, office_issue: 10, product_name: 'Ещё в работе', office_status: 'not_in_office' },
    ],
    entityId: (value) => (value && typeof value === 'object' ? value.id : value),
    relatedName: () => '',
  };
  context.officePositionRowsForBucket = CostingModule.methods.officePositionRowsForBucket.bind(context);

  const inOfficeItems = context.officePositionRowsForBucket('in_office');
  const plannedItems = context.officePositionRowsForBucket('planned');
  const inOfficeOrders = CostingModule.methods.officeOrderRowsForBucket.call(context, 'in_office');
  const plannedOrders = CostingModule.methods.officeOrderRowsForBucket.call(context, 'planned');

  assert.deepEqual(inOfficeItems.map((row) => row.id), [101]);
  assert.deepEqual(plannedItems.map((row) => row.id), [102]);
  assert.deepEqual(inOfficeOrders.map((row) => row.id), [10]);
  assert.deepEqual(plannedOrders.map((row) => row.id), [10]);
});

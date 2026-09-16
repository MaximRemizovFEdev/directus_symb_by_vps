import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { CostingModule } from '../index.js';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(testDir, '../../..');
const bootstrapSql = fs.readFileSync(path.join(projectRoot, 'setup/create-work-views.sql'), 'utf8');
const migrationSql = fs.readFileSync(path.join(projectRoot, 'setup/migrations/20260914_keep_completed_screen_costing.sql'), 'utf8');

test('completed items remain in work projections for costing history', () => {
  assert.match(
    bootstrapSql,
    /item_work_status NOT IN \('sent_to_work', 'in_work', 'layout_revision', 'ready', 'cancelled', 'delivered'\)/,
  );
  assert.match(migrationSql, /pg_get_functiondef\('sync_work_item\(integer\)'::regprocedure\)/);
  assert.match(migrationSql, /symbolika_normalize_item_status\(oi\.item_status\) = 'delivered'/);
  assert.match(migrationSql, /SELECT sync_work_item\(oi\.id\)/);
});

test('screen-printing cost month follows the order date, not the production deadline', () => {
  const month = CostingModule.methods.screenCostMonthKey({
    date: '2026-09-30',
    deadline: '2026-10-15',
  });

  assert.equal(month, '2026-09');
});

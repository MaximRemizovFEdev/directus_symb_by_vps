import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const canonicalSql = await readFile(
  new URL('../../../setup/create-work-views.sql', import.meta.url),
  'utf8',
);
const migrationSql = await readFile(
  new URL('../../../setup/migrations/20260828_serialize_office_issue_refresh.sql', import.meta.url),
  'utf8',
);

for (const [label, sql] of [
  ['canonical SQL', canonicalSql],
  ['incremental migration', migrationSql],
]) {
  test(`${label}: office mirror refresh is concurrency-safe`, () => {
    const functionBody = sql.match(
      /CREATE OR REPLACE FUNCTION sync_office_issue_items\(order_id integer\)[\s\S]*?\n\$\$;/,
    )?.[0];

    assert.ok(functionBody, 'sync_office_issue_items definition must exist');
    assert.match(functionBody, /pg_advisory_xact_lock\(205117, order_id\)/);
    assert.equal((functionBody.match(/ON CONFLICT \(id\) DO UPDATE SET/g) || []).length, 2);
    assert.ok(
      functionBody.indexOf('pg_advisory_xact_lock') < functionBody.indexOf('DELETE FROM office_issue_items'),
      'the per-order lock must be acquired before rebuilding mirror rows',
    );
  });
}

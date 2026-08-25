import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sqlPath = new URL('../../../setup/create-work-views.sql', import.meta.url);
const sql = await readFile(sqlPath, 'utf8');

const functionDefinitions = [...sql.matchAll(
  /^CREATE\s+OR\s+REPLACE\s+FUNCTION\s+([a-zA-Z0-9_."]+)/gim,
)].map((match) => ({
  name: match[1].replaceAll('"', '').toLowerCase(),
  index: match.index,
}));

const definitionsByName = new Map();
for (const definition of functionDefinitions) {
  const definitions = definitionsByName.get(definition.name) || [];
  definitions.push(definition.index);
  definitionsByName.set(definition.name, definitions);
}

const stagedDefinitions = new Map([
  ['apply_category_contractors_trigger', {
    dependency: 'CREATE TABLE IF NOT EXISTS contractor_capabilities',
    dependencyPosition: 'between',
  }],
  ['refresh_customer_reconciliation', {
    dependency: 'CREATE TABLE IF NOT EXISTS customer_operations',
    dependencyPosition: 'between',
  }],
  ['symbolika_order_work_completion', {
    dependency: 'CREATE TABLE IF NOT EXISTS contractor_capabilities',
    dependencyPosition: 'between',
  }],
  ['symbolika_order_work_readiness', {
    dependency: 'CREATE TABLE IF NOT EXISTS contractor_capabilities',
    dependencyPosition: 'between',
  }],
  ['symbolika_validate_item_route_for_work', {
    dependency: 'CREATE TABLE IF NOT EXISTS contractor_capabilities',
    dependencyPosition: 'before-bootstrap',
  }],
]);

test('allows only documented staged SQL function definitions', () => {
  const duplicateNames = [...definitionsByName]
    .filter(([, indexes]) => indexes.length > 1)
    .map(([name]) => name)
    .sort();

  assert.deepEqual(duplicateNames, [...stagedDefinitions.keys()].sort());
  for (const name of duplicateNames) {
    assert.equal(definitionsByName.get(name).length, 2, `${name} must have one bootstrap and one final definition`);
  }
});

test('keeps staged definitions in their documented dependency order', () => {
  for (const [name, { dependency, dependencyPosition }] of stagedDefinitions) {
    const [bootstrapIndex, finalIndex] = definitionsByName.get(name) || [];
    const dependencyIndex = sql.indexOf(dependency);

    assert.ok(bootstrapIndex >= 0, `${name} bootstrap definition is missing`);
    assert.ok(dependencyIndex >= 0, `${dependency} is missing`);
    if (dependencyPosition === 'between') {
      assert.ok(dependencyIndex > bootstrapIndex, `${dependency} must follow the ${name} bootstrap definition`);
      assert.ok(finalIndex > dependencyIndex, `${name} final definition must follow ${dependency}`);
    } else {
      assert.ok(bootstrapIndex > dependencyIndex, `${name} bootstrap definition must follow ${dependency}`);
      assert.ok(finalIndex > bootstrapIndex, `${name} final definition must follow its transition-only guard`);
    }
  }
});

test('serializes full due-bucket rebuilds', () => {
  const definition = sql.match(
    /CREATE OR REPLACE FUNCTION refresh_orders_due_tables\(\)[\s\S]*?\n\$\$;/i,
  )?.[0] || '';

  assert.match(definition, /pg_advisory_xact_lock\(hashtext\('symbolika_orders_due_refresh'\)\)/i);
  assert.ok(
    definition.indexOf('pg_advisory_xact_lock') < definition.indexOf('DELETE FROM orders_due_today'),
    'the lock must be acquired before any due table is rebuilt',
  );
});

test('skips duplicate automatic consistency refreshes without blocking writes', () => {
  const definition = sql.match(
    /CREATE OR REPLACE FUNCTION symbolika_refresh_automation_issues_trigger\(\)[\s\S]*?\n\$\$;/i,
  )?.[0] || '';

  assert.match(definition, /pg_try_advisory_xact_lock\(hashtext\('symbolika_automation_issues_refresh'\)\)/i);
  assert.ok(
    definition.indexOf('pg_try_advisory_xact_lock') < definition.indexOf('refresh_symbolika_automation_issues()'),
    'the trigger must try the lock before starting the expensive refresh',
  );
});

test('refreshes contractor costing only for source fields used by the projection', () => {
  const itemTrigger = sql.match(
    /CREATE TRIGGER contractor_costing_sync_item[\s\S]*?EXECUTE FUNCTION sync_contractor_costing_item_trigger\(\);/i,
  )?.[0] || '';
  const orderTrigger = sql.match(
    /CREATE TRIGGER contractor_costing_sync_order[\s\S]*?EXECUTE FUNCTION sync_contractor_costing_order_trigger\(\);/i,
  )?.[0] || '';

  assert.match(itemTrigger, /UPDATE OF[\s\S]*product_name[\s\S]*contractor_1_cost[\s\S]*production_status/i);
  assert.doesNotMatch(itemTrigger, /\burl\b|office_status/i);
  assert.match(orderTrigger, /UPDATE OF[\s\S]*order_number[\s\S]*manager_employee/i);
  assert.doesNotMatch(orderTrigger, /order_sum|office_status|paid_amount/i);
});

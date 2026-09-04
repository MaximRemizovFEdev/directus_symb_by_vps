import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sqlPath = new URL('../../../setup/create-work-views.sql', import.meta.url);
const sql = await readFile(sqlPath, 'utf8');
const waitingLayoutMigrationPath = new URL(
  '../../../setup/migrations/20260901_order_item_waiting_layout_status.sql',
  import.meta.url,
);
const waitingLayoutMigration = await readFile(waitingLayoutMigrationPath, 'utf8');
const managerScreenCostPermissionMigrationPath = new URL(
  '../../../setup/migrations/20260904_manager_screen_printing_cost_permission.sql',
  import.meta.url,
);
const managerScreenCostPermissionMigration = await readFile(managerScreenCostPermissionMigrationPath, 'utf8');

const extractFunction = (source, name) => source.match(
  new RegExp(`CREATE OR REPLACE FUNCTION ${name.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\b[\\s\\S]*?\\n\\$\\$;`, 'i'),
)?.[0].replaceAll('\r\n', '\n').trim() || '';
const normalizeSqlDefinition = (definition) => definition
  .replace(/^\s*--.*$/gm, '')
  .replace(/\s+/g, ' ')
  .trim();

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

test('keeps waiting for layout as a real item workflow status', () => {
  const normalizer = sql.match(
    /CREATE OR REPLACE FUNCTION symbolika_normalize_item_status\(status_value character varying\)[\s\S]*?\n\$\$;/i,
  )?.[0] || '';
  const itemTransition = sql.match(
    /CREATE OR REPLACE FUNCTION symbolika_apply_item_status_from_production_trigger\(\)[\s\S]*?\n\$\$;/i,
  )?.[0] || '';
  const orderProjection = sql.match(
    /CREATE OR REPLACE FUNCTION symbolika_recalc_order_status_from_items\(order_id integer\)[\s\S]*?\n\$\$;/i,
  )?.[0] || '';

  assert.doesNotMatch(normalizer, /WHEN 'waiting_layout' THEN 'new'/i);
  assert.match(itemTransition, /previous_item_status IN \('new', 'waiting_layout', 'approval'\)/i);
  assert.match(orderProjection, /item_status = 'waiting_layout'/i);
});

test('keeps the waiting-layout migration aligned with canonical workflow functions', () => {
  const functions = [
    'symbolika_normalize_item_status',
    'symbolika_recalc_order_status_from_items',
    'symbolika_apply_item_status_from_production_trigger',
    'symbolika_apply_order_status_to_items_trigger',
  ];

  for (const name of functions) {
    const canonicalDefinition = extractFunction(sql, name);
    const migrationDefinition = extractFunction(waitingLayoutMigration, name);
    assert.ok(canonicalDefinition, `${name} is missing from the canonical SQL`);
    assert.ok(migrationDefinition, `${name} is missing from the migration`);
    assert.equal(
      normalizeSqlDefinition(migrationDefinition),
      normalizeSqlDefinition(canonicalDefinition),
      `${name} differs between migration and canonical SQL`,
    );
  }
});

test('grants managers the persisted screen-printing cost without widening row access', () => {
  for (const source of [sql, managerScreenCostPermissionMigration]) {
    assert.match(source, /screen_printing_cost_per_unit/);
    assert.match(source, /collection\s*=\s*'orders_items'/i);
    assert.match(source, /action IN \('create', 'read', 'update'\)/i);
    assert.match(source, /policy\s*=\s*'00000000-0000-4000-8000-000000000202'/i);
  }

  assert.doesNotMatch(managerScreenCostPermissionMigration, /SET\s+permissions\s*=/i);
  assert.doesNotMatch(managerScreenCostPermissionMigration, /fields\s*=\s*'\*'/i);
});

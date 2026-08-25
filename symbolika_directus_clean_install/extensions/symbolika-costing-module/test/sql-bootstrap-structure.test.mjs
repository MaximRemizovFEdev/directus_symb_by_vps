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

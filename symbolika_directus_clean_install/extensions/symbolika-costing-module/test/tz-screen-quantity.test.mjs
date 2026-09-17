import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleSource = await readFile(new URL('../index.js', import.meta.url), 'utf8');
const seedSql = await readFile(new URL('../../../setup/create-tz-constructor.sql', import.meta.url), 'utf8');
const migrationSql = await readFile(
  new URL('../../../setup/migrations/20260908_include_quantity_in_screen_tz.sql', import.meta.url),
  'utf8',
);
const allTemplatesMigrationSql = await readFile(
  new URL('../../../setup/migrations/20260910_include_quantity_in_all_tz.sql', import.meta.url),
  'utf8',
);

test('includes item quantity in every screen-printing task source', () => {
  assert.match(
    seedSql,
    /'\{\{product_name\}\}, \{\{quantity\}\} шт\., шелкография \{\{application_size\}\}/,
  );
  assert.match(
    seedSql,
    /WHEN method_name IN \('Шелкография', 'Шелкография с трансфером'\) THEN '[^']*\{\{quantity\}\} шт\./,
  );
  assert.match(moduleSource, /application_method_name,route_area,fields,template/);
  assert.match(moduleSource, /if \(!template\.includes\('\{\{quantity\}\}'\)\)/);
  assert.match(migrationSql, /route_area = 'screen_printing'/);
  assert.match(migrationSql, /template NOT LIKE '%\{\{quantity\}\}%'/);
  assert.match(migrationSql, /FROM screen_printing_work work/);
});

test('includes item quantity in every active technical-task template', () => {
  assert.match(seedSql, /UPDATE tz_constructor_specs[\s\S]*?template NOT LIKE '%\{\{quantity\}\}%'/);
  assert.match(allTemplatesMigrationSql, /CREATE TEMP TABLE symbolika_affected_tz_specs/);
  assert.match(allTemplatesMigrationSql, /UPDATE tz_constructor_specs/);
  assert.match(allTemplatesMigrationSql, /UPDATE orders_items item/);
  assert.doesNotMatch(allTemplatesMigrationSql, /route_area\s*=/);
  assert.match(moduleSource, /updateTzAfterQuantityChange\(item, persist = false\)/);
  assert.match(moduleSource, /item\.tz_constructor_expanded === true[\s\S]*?updateTzConstructor\(item, persist, true\)/);
  assert.match(moduleSource, /saveOrderItemQuantity\(detail\.row, \$event\.target\.value\)/);
});

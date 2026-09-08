import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleSource = await readFile(new URL('../index.js', import.meta.url), 'utf8');
const seedSql = await readFile(new URL('../../../setup/create-tz-constructor.sql', import.meta.url), 'utf8');
const migrationSql = await readFile(
  new URL('../../../setup/migrations/20260908_include_quantity_in_screen_tz.sql', import.meta.url),
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
  assert.match(moduleSource, /spec\.route_area === 'screen_printing' && !template\.includes\('\{\{quantity\}\}'\)/);
  assert.match(migrationSql, /route_area = 'screen_printing'/);
  assert.match(migrationSql, /template NOT LIKE '%\{\{quantity\}\}%'/);
  assert.match(migrationSql, /FROM screen_printing_work work/);
});

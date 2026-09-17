import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('client operations use searchable customer and company relations', () => {
  const clientOperations = source.slice(
    source.indexOf('client_operations: {'),
    source.indexOf('\n  contractors: {'),
  );

  assert.match(clientOperations, /key: 'customer'.*options: 'customers'.*searchable: true/);
  assert.match(clientOperations, /key: 'customer_company'.*options: 'companies'.*searchable: true/);
  assert.match(source, /syncAdminSearchableRelation\(column\)/);
  assert.match(source, /hydrateAdminSearchableRelations\(\)/);
  assert.match(source, /:list="adminRelationSuggestionList\(column\)"/);
});

test('searchable relations still save relation ids instead of labels', () => {
  assert.match(source, /this\.adminForm\[column\.key\] = selected\?\.id \? String\(selected\.id\) : ''/);
  assert.match(source, /if \(column\.type === 'relation'\) value = value && value !== '__other__' \? value : null/);
});

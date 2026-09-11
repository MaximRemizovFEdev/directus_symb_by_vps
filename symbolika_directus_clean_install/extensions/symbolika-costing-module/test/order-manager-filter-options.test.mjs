import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('all-orders manager filter only uses managers referenced by orders', () => {
  const method = source.match(/orderManagerOptions\(\) \{(?<body>[\s\S]*?)\n    \},\n\n    orderFilterSummary\(\)/)?.groups?.body || '';

  assert.match(method, /\(this\.allOrderRows \|\| \[\]\)\.forEach/);
  assert.doesNotMatch(method, /\(this\.employees \|\| \[\]\)\.forEach/);
  assert.match(method, /options\.set\(String\(id\), name\)/);
});

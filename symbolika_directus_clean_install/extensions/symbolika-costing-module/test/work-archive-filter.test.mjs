import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('production status filter does not bypass active and archive separation', () => {
  const body = source.match(/matchesWorkArchiveMode\(row\) \{(?<body>[\s\S]*?)\n    \},/)?.groups?.body || '';

  assert.doesNotMatch(body, /workProductionStatusFilter/);
  assert.match(body, /workArchiveMode === 'archive'\) return this\.isWorkArchived\(row\)/);
  assert.match(body, /workArchiveMode === 'all'\) return true/);
  assert.match(body, /return !this\.isWorkArchived\(row\)/);
});

test('ready production work is treated as archived', () => {
  assert.match(source, /isWorkArchived\(row\) \{[\s\S]*?\['готов', 'отмен'\]/);
});

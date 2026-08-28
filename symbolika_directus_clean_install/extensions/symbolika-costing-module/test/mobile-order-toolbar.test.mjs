import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('mobile order toolbar keeps advanced controls collapsed by default', () => {
  assert.match(source, /mobileOrderToolbarOpen:\s*false/);
  assert.match(source, /Фильтры и вид/);
  assert.match(source, /mobileOrderToolbarOpen\s*=\s*!mobileOrderToolbarOpen/);
  assert.match(source, /symbolika-costing-order-controls-row:not\(\.is-mobile-open\)\s*\{\s*display:\s*none\s*!important/);
});

test('mobile order workspace is constrained to the viewport', () => {
  assert.match(source, /@media \(max-width:\s*760px\)/);
  assert.match(source, /symbolika-costing-smart-toolbar\.is-order-toolbar/);
  assert.match(source, /grid-template-columns:\s*minmax\(0,\s*1fr\)\s*auto\s*20px/);
  assert.match(source, /symbolika-costing-modal :is\(input, select, textarea\)[\s\S]*?max-inline-size:\s*100%/);
});

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  compareSortValues,
  createdRecordId,
  dateOnly,
  entityId,
  formatFileSize,
  isEmptySortValue,
  matchesDateRange,
  normalizeAppearanceTheme,
  normalizeExternalHttpUrl,
  sortDateValue,
} from '../lib/core-utils.js';

test('normalizes relation identifiers without leaking object values', () => {
  assert.equal(entityId({ id: 17 }), '17');
  assert.equal(entityId({ value: 'abc' }), 'abc');
  assert.equal(entityId(null), '');
});

test('allows only configured themes', () => {
  const themes = [{ id: 'graphite' }, { id: 'pearl' }];
  assert.equal(normalizeAppearanceTheme('pearl', themes), 'pearl');
  assert.equal(normalizeAppearanceTheme('unknown', themes), 'graphite');
});

test('normalizes safe external links', () => {
  assert.equal(normalizeExternalHttpUrl('example.ru'), 'https://example.ru/');
  assert.equal(normalizeExternalHttpUrl('https://example.ru/path'), 'https://example.ru/path');
  assert.equal(normalizeExternalHttpUrl('javascript:alert(1)'), '');
});

test('parses ISO and localized calendar dates consistently', () => {
  assert.notEqual(sortDateValue('2026-08-25'), '');
  assert.equal(sortDateValue('25.08.26'), sortDateValue('2026-08-25'));
  assert.equal(sortDateValue('31.02.2026'), '');
  assert.equal(dateOnly('25.08.26'), '2026-08-25');
});

test('matches inclusive date ranges', () => {
  assert.equal(matchesDateRange('2026-08-25', '2026-08-25', '2026-08-25'), true);
  assert.equal(matchesDateRange('2026-08-24', '2026-08-25', ''), false);
  assert.equal(matchesDateRange('', '', ''), true);
});

test('keeps sort comparison and empty values deterministic', () => {
  assert.equal(isEmptySortValue('-'), true);
  assert.equal(isEmptySortValue(0), false);
  assert.ok(compareSortValues('SO-2', 'SO-10') < 0);
  assert.ok(compareSortValues(10, 2) > 0);
});

test('extracts created record identifiers from Directus responses', () => {
  assert.equal(createdRecordId({ data: { id: 42 } }), 42);
  assert.equal(createdRecordId({ data: [{ id: '7' }] }), 7);
  assert.equal(createdRecordId({ data: [] }), null);
});

test('formats binary file sizes', () => {
  assert.equal(formatFileSize(512), '512 Б');
  assert.equal(formatFileSize(2048), '2 КБ');
  assert.equal(formatFileSize(1.5 * 1024 * 1024), '1.5 МБ');
});

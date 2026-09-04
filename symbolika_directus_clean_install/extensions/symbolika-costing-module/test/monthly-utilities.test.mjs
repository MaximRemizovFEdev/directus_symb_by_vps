import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleSource = await readFile(new URL('../index.js', import.meta.url), 'utf8');
const bootstrapSql = await readFile(new URL('../../../setup/create-work-views.sql', import.meta.url), 'utf8');
const migrationSql = await readFile(new URL('../../../setup/migrations/20260828_monthly_utilities.sql', import.meta.url), 'utf8');

test('rent and utilities are tracked as separate monthly expenses', () => {
  assert.match(moduleSource, /text: 'Коммунальные услуги', value: 'utilities'/);
  assert.match(moduleSource, /currentUtilitiesStatus\(\)/);
  assert.match(moduleSource, /row\.expense_type !== 'utilities'/);
  assert.match(moduleSource, /openCurrentUtilitiesPayment\(\)/);
  assert.match(moduleSource, /openExpenseDialog\('utilities'/);
});

test('premises forecast combines unpaid rent and utilities', () => {
  assert.match(moduleSource, /currentPremisesStatus\(\)/);
  assert.match(moduleSource, /planned: rent\.planned \+ utilities\.planned/);
  assert.match(moduleSource, /const unpaidPremises = this\.currentPremisesStatus\.due/);
});

test('utilities setting is represented in bootstrap and deploy migration', () => {
  assert.match(bootstrapSql, /monthly_utilities numeric\(14,2\) NOT NULL DEFAULT 0/);
  assert.match(migrationSql, /ADD COLUMN IF NOT EXISTS monthly_utilities numeric\(14,2\) NOT NULL DEFAULT 0/);
  assert.match(migrationSql, /"Коммунальные услуги","value":"utilities"/);
});

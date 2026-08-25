import assert from 'node:assert/strict';
import test from 'node:test';

import {
  formatMoney,
  formatMoneyCompact,
  formatShortDate,
  moneyInput,
  monthKey,
  monthLabel,
  normalizeStatusText,
  officeBadgeClass,
  officeSelectClass,
  pluralRu,
  statusBadgeClass,
  statusToneClass,
  todayInput,
  toInputDate,
} from '../lib/presentation-utils.js';

test('formats calendar values for the Russian interface', () => {
  assert.equal(formatShortDate('2026-08-25'), '25.08.26');
  assert.equal(formatShortDate('not-a-date'), '-');
  assert.equal(monthKey('25.08.26'), '2026-08');
  assert.match(monthLabel('2026-08'), /август/i);
  assert.equal(todayInput(new Date(2026, 7, 25)), '2026-08-25');
  assert.equal(toInputDate('2026-08-25T12:00:00Z'), '2026-08-25');
});

test('maps workflow statuses to stable visual classes', () => {
  assert.equal(normalizeStatusText('  ГОТОВ  '), 'готов');
  assert.equal(statusBadgeClass('Доработка макета'), 'symbolika-costing-pill-danger');
  assert.equal(statusBadgeClass('В работе'), 'symbolika-costing-pill-orange');
  assert.equal(statusToneClass('Согласование'), 'symbolika-costing-select-purple');
  assert.equal(officeBadgeClass('issued'), 'symbolika-costing-pill-green');
  assert.equal(officeSelectClass('in_office'), 'symbolika-costing-select-orange');
});

test('formats money without changing stored precision', () => {
  assert.equal(formatMoney('1234.5').replace(/\s/g, ' '), '1 234,50');
  assert.equal(formatMoney('bad'), '0,00');
  assert.equal(formatMoneyCompact('1200').replace(/\s/g, ' '), '1 200');
  assert.equal(formatMoneyCompact('1200.5').replace(/\s/g, ' '), '1 200,50');
  assert.equal(moneyInput('12,349'), '12.35');
});

test('selects Russian plural forms', () => {
  assert.equal(pluralRu(1, 'позиция', 'позиции', 'позиций'), 'позиция');
  assert.equal(pluralRu(3, 'позиция', 'позиции', 'позиций'), 'позиции');
  assert.equal(pluralRu(12, 'позиция', 'позиции', 'позиций'), 'позиций');
});

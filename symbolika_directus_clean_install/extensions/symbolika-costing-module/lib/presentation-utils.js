import { dateFromValue } from './core-utils.js';

export function formatShortDate(value, locale = 'ru-RU') {
  const date = dateFromValue(value);
  if (!date) return '-';
  return new Intl.DateTimeFormat(locale, {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(date);
}

export function monthKey(value) {
  const date = dateFromValue(value);
  if (!date) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

export function monthLabel(value, locale = 'ru-RU') {
  if (!value) return '-';
  const [year, month] = String(value).split('-').map(Number);
  if (!year || !month) return '-';
  return new Intl.DateTimeFormat(locale, {
    month: 'long',
    year: 'numeric',
  }).format(new Date(year, month - 1, 1));
}

export function todayInput(now = new Date()) {
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) return '';
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function toInputDate(value) {
  return value ? String(value).slice(0, 10) : '';
}

export function normalizeStatusText(value) {
  return String(value || '').trim().toLowerCase();
}

export function statusBadgeClass(value) {
  const status = normalizeStatusText(value);
  if (status.includes('доработ')) return 'symbolika-costing-pill-danger';
  if (status.includes('отмен')) return 'symbolika-costing-pill-muted';
  if (status.includes('достав') || status.includes('выдан')) return 'symbolika-costing-pill-green';
  if (status.includes('готов')) return 'symbolika-costing-pill-blue';
  if (status.includes('не в работе') || status.includes('ждем') || status.includes('ждём')) return 'symbolika-costing-pill-muted';
  if (status.includes('работ')) return 'symbolika-costing-pill-orange';
  if (status.includes('соглас')) return 'symbolika-costing-pill-purple';
  if (status.includes('нов')) return 'symbolika-costing-pill-blue';
  return 'symbolika-costing-pill-muted';
}

export function statusToneClass(value) {
  return statusBadgeClass(value).replace('symbolika-costing-pill-', 'symbolika-costing-select-');
}

export function officeBadgeClass(value) {
  if (value === 'issued') return 'symbolika-costing-pill-green';
  if (value === 'in_office') return 'symbolika-costing-pill-orange';
  return 'symbolika-costing-pill-muted';
}

export function officeSelectClass(value) {
  if (value === 'issued') return 'symbolika-costing-select-green';
  if (value === 'in_office') return 'symbolika-costing-select-orange';
  return 'symbolika-costing-select-muted';
}

function numericValue(value) {
  const number = Number(String(value ?? '').replace(',', '.'));
  return Number.isFinite(number) ? number : null;
}

export function formatMoney(value, locale = 'ru-RU') {
  const number = numericValue(value);
  if (number === null) return '0,00';
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(number);
}

export function formatMoneyCompact(value, locale = 'ru-RU') {
  const number = numericValue(value);
  if (number === null) return '0';
  const hasCents = Math.round(number * 100) % 100 !== 0;
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: hasCents ? 2 : 0,
    maximumFractionDigits: hasCents ? 2 : 0,
  }).format(number);
}

export function pluralRu(count, one, few, many) {
  const value = Math.abs(Number(count)) % 100;
  const last = value % 10;
  if (value > 10 && value < 20) return many;
  if (last > 1 && last < 5) return few;
  if (last === 1) return one;
  return many;
}

export function moneyInput(value) {
  const number = numericValue(value);
  if (number === null) return '';
  return String(Math.round(number * 100) / 100);
}

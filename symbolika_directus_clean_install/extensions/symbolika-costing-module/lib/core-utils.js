export function entityId(value) {
  if (value === null || value === undefined || value === '') return '';
  if (typeof value === 'object') return String(value.id ?? value.value ?? '');
  return String(value);
}

export function normalizeAppearanceTheme(value, themes = [], fallback = 'graphite') {
  return themes.some((theme) => theme?.id === value) ? value : fallback;
}

export function normalizeExternalHttpUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const candidate = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(candidate);
    return ['http:', 'https:'].includes(url.protocol) && url.hostname ? url.href : '';
  } catch {
    return '';
  }
}

export function sortDateValue(value) {
  if (value === null || value === undefined || value === '') return '';
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? '' : value.getTime();
  if (typeof value === 'number') return Number.isFinite(value) ? value : '';

  const source = String(value).trim();
  if (!source) return '';

  const isoDate = source.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoDate) {
    const [, year, month, day] = isoDate.map(Number);
    const date = new Date(year, month - 1, day);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
      ? date.getTime()
      : '';
  }

  const localizedDate = source.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{2}|\d{4})$/);
  if (localizedDate) {
    const day = Number(localizedDate[1]);
    const month = Number(localizedDate[2]);
    const yearPart = Number(localizedDate[3]);
    const year = localizedDate[3].length === 2 ? 2000 + yearPart : yearPart;
    const date = new Date(year, month - 1, day);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
      ? date.getTime()
      : '';
  }

  const date = new Date(source);
  return Number.isNaN(date.getTime()) ? '' : date.getTime();
}

export function dateFromValue(value) {
  const timestamp = sortDateValue(value);
  return timestamp === '' ? null : new Date(timestamp);
}

export function dateOnly(value) {
  const date = dateFromValue(value);
  if (!date) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function matchesDateRange(value, from, to) {
  const current = dateOnly(value);
  if (!current) return !from && !to;
  if (from && current < from) return false;
  if (to && current > to) return false;
  return true;
}

export function isEmptySortValue(value) {
  return value === null || value === undefined || value === '' || value === '-';
}

export function compareSortValues(a, b) {
  if (typeof a === 'number' || typeof b === 'number') {
    return Number(a || 0) - Number(b || 0);
  }
  return String(a).localeCompare(String(b), 'ru', { numeric: true, sensitivity: 'base' });
}

export function createdRecordId(payload) {
  const data = payload?.data;
  const value = Array.isArray(data) ? data[0] : data;
  const id = value && typeof value === 'object' ? value.id : value;
  const numericId = Number(id || 0);
  return Number.isFinite(numericId) && numericId > 0 ? numericId : null;
}

export function formatFileSize(value) {
  const bytes = Number(value || 0);
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} Б`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} КБ`;
  return `${(bytes / (1024 * 1024)).toFixed(bytes >= 10 * 1024 * 1024 ? 0 : 1)} МБ`;
}

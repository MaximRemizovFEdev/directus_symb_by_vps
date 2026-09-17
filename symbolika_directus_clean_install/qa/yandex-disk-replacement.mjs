import { readFile } from 'node:fs/promises';

const envText = await readFile(new URL('../.env', import.meta.url), 'utf8');
const localEnv = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .filter((line) => line && !line.trimStart().startsWith('#') && line.includes('='))
    .map((line) => {
      const separator = line.indexOf('=');
      return [line.slice(0, separator).trim(), line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, '')];
    }),
);

const directusUrl = String(process.env.DIRECTUS_URL || localEnv.DIRECTUS_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminEmail = process.env.ADMIN_EMAIL || localEnv.ADMIN_EMAIL;
const adminPassword = process.env.ADMIN_PASSWORD || localEnv.ADMIN_PASSWORD;
const configuredAccessToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN || '';
const diskToken = process.env.SYMBOLIKA_YANDEX_DISK_TOKEN || localEnv.SYMBOLIKA_YANDEX_DISK_TOKEN;

if ((!configuredAccessToken && (!adminEmail || !adminPassword)) || !diskToken) {
  throw new Error('Для теста нужен SYMBOLIKA_QA_ADMIN_TOKEN либо ADMIN_EMAIL/ADMIN_PASSWORD, а также токен Яндекс.Диска.');
}

async function request(url, options = {}) {
  const response = await fetch(url, options);
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${url}: ${payload?.errors?.[0]?.message || payload?.description || response.status}`);
  return payload;
}

async function directus(path, options = {}) {
  return request(`${directusUrl}${path}`, {
    ...options,
    headers: {
      ...(options.body && typeof options.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      ...(options.headers || {}),
    },
  });
}

async function diskResource(path) {
  const url = new URL('https://cloud-api.yandex.net/v1/disk/resources');
  url.searchParams.set('path', path);
  url.searchParams.set('fields', 'name,path');
  return fetch(url, { headers: { Authorization: `OAuth ${diskToken}` } });
}

async function deleteDiskResource(path) {
  if (!path) return;
  const url = new URL('https://cloud-api.yandex.net/v1/disk/resources');
  url.searchParams.set('path', path);
  url.searchParams.set('permanently', 'true');
  const response = await fetch(url, { method: 'DELETE', headers: { Authorization: `OAuth ${diskToken}` } });
  if (![202, 204, 404].includes(response.status)) throw new Error(`Не удалось удалить тестовый файл с Диска: HTTP ${response.status}`);
}

let accessToken = configuredAccessToken;
let customerId = null;
let orderId = null;
let itemId = null;
let firstPath = '';
let secondPath = '';

try {
  if (!accessToken) {
    const login = await request(`${directusUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: adminEmail, password: adminPassword }),
    });
    accessToken = login.data.access_token;
  }

  customerId = (await directus('/items/customers', {
    method: 'POST',
    body: JSON.stringify({ name: 'Анатолий QA' }),
  })).data.id;
  orderId = (await directus('/items/orders', {
    method: 'POST',
    body: JSON.stringify({ date: '2026-08-10', customer: customerId }),
  })).data.id;
  itemId = (await directus('/items/orders_items', {
    method: 'POST',
    body: JSON.stringify({ order: orderId, product_name: 'Блокноты', quantity: 50, price_per_unit: 0 }),
  })).data.id;

  const first = await directus(`/symbolika-yandex-disk/orders-items/${itemId}/upload`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/pdf',
      'X-File-Name': encodeURIComponent('исходный макет.pdf'),
      'X-File-Size': '12',
    },
    body: Buffer.from('first-layout'),
  });
  firstPath = first.data.path;
  if (first.data.name !== '100826, Анатолий QA, Блокноты - 50шт.pdf') {
    throw new Error(`Неожиданное имя первого файла: ${first.data.name}`);
  }

  await directus(`/items/orders_items/${itemId}`, {
    method: 'PATCH',
    body: JSON.stringify({ quantity: 51 }),
  });
  const second = await directus(`/symbolika-yandex-disk/orders-items/${itemId}/upload`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/pdf',
      'X-File-Name': encodeURIComponent('новый макет.pdf'),
      'X-File-Size': '13',
    },
    body: Buffer.from('second-layout'),
  });
  secondPath = second.data.path;
  if (second.data.name !== '100826, Анатолий QA, Блокноты - 51шт.pdf') {
    throw new Error(`Неожиданное имя второго файла: ${second.data.name}`);
  }
  if (firstPath === secondPath) throw new Error('Путь нового файла не изменился после изменения количества.');

  let oldStatus = 200;
  for (let attempt = 0; attempt < 10; attempt += 1) {
    oldStatus = (await diskResource(firstPath)).status;
    if (oldStatus === 404) break;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (oldStatus !== 404) throw new Error(`Старый файл остался на Диске: HTTP ${oldStatus}`);
  if ((await diskResource(secondPath)).status !== 200) throw new Error('Новый файл не найден на Диске.');

  console.log(JSON.stringify({ fileName: second.data.name, oldFileDeleted: true, replacementStored: true }));
} finally {
  await deleteDiskResource(secondPath).catch(() => {});
  if (accessToken && itemId) await directus(`/items/orders_items/${itemId}`, { method: 'DELETE' }).catch(() => {});
  if (accessToken && orderId) await directus(`/items/orders/${orderId}`, { method: 'DELETE' }).catch(() => {});
  if (accessToken && customerId) await directus(`/items/customers/${customerId}`, { method: 'DELETE' }).catch(() => {});
}

const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

async function api(endpoint, options = {}, token = '') {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(options.headers || {}),
    },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`);
  return payload?.data ?? payload;
}

async function login(page, credentials) {
  await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.locator('input[type="email"]').fill(credentials.email);
  await page.locator('input[type="password"]').fill(credentials.password);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
}

async function run() {
  const token = adminToken;
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = { email: `qa-layout-link-${suffix}@example.com`, password: `Qa!${crypto.randomBytes(18).toString('hex')}` };
  let userId;
  let customerId;
  let orderId;
  let itemId;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 960 } });

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1', {}, token);
    const user = await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Layout Link' }),
    }, token);
    userId = user.id;
    const customer = await api('/items/customers', {
      method: 'POST',
      body: JSON.stringify({ name: `QA ссылка на макет ${suffix}` }),
    }, token);
    customerId = customer.id;
    const order = await api('/items/orders', {
      method: 'POST',
      body: JSON.stringify({ date: new Date().toISOString().slice(0, 10), customer: customerId, order_status: 1, office_status: 'not_in_office' }),
    }, token);
    orderId = order.id;
    const item = await api('/items/orders_items', {
      method: 'POST',
      body: JSON.stringify({ order: orderId, product_name: `QA макет ${suffix}`, quantity: 1, price_per_unit: 0, order_sum: 0, item_status: 'new', office_status: 'not_in_office' }),
    }, token);
    itemId = item.id;

    await login(page, credentials);
    await page.goto(`${baseUrl}/admin/symbolika-orders?item=${itemId}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    const detail = page.locator('aside.symbolika-costing-detail');
    await detail.waitFor({ timeout: 60_000 });
    await detail.getByRole('button', { name: /Добавить файл или ссылку/ }).click();

    const modal = page.locator('.symbolika-layout-upload-modal');
    await modal.waitFor({ timeout: 15_000 });
    await modal.getByRole('button', { name: /Вставить ссылку/ }).click();
    await modal.locator('input[inputmode="url"]').fill('example.com/customer-layout.pdf');
    await modal.getByRole('button', { name: /Сохранить ссылку/ }).click();
    await modal.waitFor({ state: 'hidden', timeout: 20_000 });

    const saved = await api(`/items/orders_items/${itemId}?fields=id,url,layout_disk_path`, {}, token);
    if (saved.url !== 'https://example.com/customer-layout.pdf') throw new Error(`Unexpected saved URL: ${saved.url}`);
    if (saved.layout_disk_path) throw new Error('Disk metadata was not cleared for an external link.');
    await detail.getByText('https://example.com/customer-layout.pdf', { exact: false }).waitFor({ timeout: 15_000 });
    console.log(JSON.stringify({ externalLinkSaved: true, displayedInItemCard: true, diskMetadataCleared: true }));
  } finally {
    await browser.close();
    if (itemId) await api(`/items/orders_items/${itemId}`, { method: 'DELETE' }, token).catch(() => null);
    if (orderId) await api(`/items/orders/${orderId}`, { method: 'DELETE' }, token).catch(() => null);
    if (customerId) await api(`/items/customers/${customerId}`, { method: 'DELETE' }, token).catch(() => null);
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }, token).catch(() => null);
  }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });

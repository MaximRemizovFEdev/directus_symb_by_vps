const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

async function api(endpoint, options = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json', ...(options.headers || {}) },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${JSON.stringify(payload)}`);
  return payload?.data ?? payload;
}

async function run() {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = { email: `qa-office-detail-${suffix}@example.com`, password: `Qa!${crypto.randomBytes(18).toString('hex')}` };
  let userId;
  let employeeId;
  let customerId;
  let orderId;
  let itemId;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 960 } });
  const forbidden = [];
  page.on('response', (response) => {
    if (response.status() === 403 && response.url().includes('/items/orders_items')) forbidden.push(response.url());
  });

  try {
    const roles = await api('/roles?filter[name][_eq]=Офис-менеджер&fields=id&limit=1');
    const category = (await api('/items/product_categories?fields=id&limit=1'))[0];
    if (!roles[0]?.id || !category?.id) throw new Error('Не найдены роль офис-менеджера или категория.');
    userId = (await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Office Detail' }),
    })).id;
    employeeId = (await api('/items/employees', {
      method: 'POST',
      body: JSON.stringify({ full_name: `QA Office Detail ${suffix}`, directus_user: userId, is_active: true }),
    })).id;
    customerId = (await api('/items/customers', {
      method: 'POST',
      body: JSON.stringify({ name: `QA Customer ${suffix}`, manager: employeeId }),
    })).id;
    orderId = (await api('/items/orders', {
      method: 'POST',
      body: JSON.stringify({ date: new Date().toISOString().slice(0, 10), customer: customerId, manager_employee: employeeId, office_status: 'not_in_office' }),
    })).id;
    itemId = (await api('/items/orders_items', {
      method: 'POST',
      body: JSON.stringify({ order: orderId, product_name: `QA Блокноты ${suffix}`, quantity: 1, product_category: category.id, office_status: 'not_in_office' }),
    })).id;

    await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('input[type="email"]').fill(credentials.email);
    await page.locator('input[type="password"]').fill(credentials.password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
    await page.goto(`${baseUrl}/admin/symbolika-orders?item=${itemId}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });

    const detail = page.locator('aside.symbolika-costing-detail');
    await detail.waitFor({ timeout: 60_000 });
    const categorySelect = detail.locator('.symbolika-costing-detail-field').filter({ hasText: 'Категория' }).locator('select').first();
    await categorySelect.waitFor({ timeout: 20_000 });
    const categoryValue = await categorySelect.inputValue();
    if (categoryValue !== String(category.id)) {
      const diagnostics = await detail.locator('select').evaluateAll((nodes) => nodes.map((node) => ({ value: node.value, options: [...node.options].map((option) => ({ value: option.value, text: option.textContent })) })));
      throw new Error(`Категория не отображается в карточке позиции: ожидалось ${category.id}, получено ${categoryValue}; ${JSON.stringify(diagnostics)}`);
    }
    await detail.locator('.symbolika-costing-detail-close').click();
    await detail.waitFor({ state: 'hidden', timeout: 10_000 });
    if (forbidden.length) throw new Error(`Карточка получила 403: ${forbidden.join(', ')}`);
    console.log(JSON.stringify({ officeItemDetailInteractive: true, categoryVisible: true, forbiddenRequests: 0 }));
  } finally {
    await browser.close();
    if (itemId) await api(`/items/orders_items/${itemId}`, { method: 'DELETE' }).catch(() => null);
    if (orderId) await api(`/items/orders/${orderId}`, { method: 'DELETE' }).catch(() => null);
    if (customerId) await api(`/items/customers/${customerId}`, { method: 'DELETE' }).catch(() => null);
    if (employeeId) await api(`/items/employees/${employeeId}`, { method: 'DELETE' }).catch(() => null);
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => null);
  }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });

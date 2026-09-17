const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = String(process.env.SYMBOLIKA_QA_ADMIN_TOKEN || '').trim();

if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

let token = adminToken;
let orderId = null;
let itemId = null;
let userId = null;

async function api(endpoint, options = {}) {
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

async function fieldByLabel(modal, label) {
  return modal.locator('label').filter({ hasText: new RegExp(`^${label}`) }).first();
}

(async () => {
  const roleRows = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
  if (!roleRows[0]?.id) throw new Error('Administrator role was not found.');
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-textile-tz-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const qaUser = await api('/users', {
    method: 'POST',
    body: JSON.stringify({ ...credentials, role: roleRows[0].id, status: 'active', first_name: 'QA', last_name: 'Textile TZ' }),
  });
  userId = qaUser.id;

  const [customers, categories] = await Promise.all([
    api('/items/customers?fields=id&limit=1'),
    api('/items/product_categories?fields=id,name&filter[name][_eq]=Текстиль&limit=1'),
  ]);
  if (!customers[0]?.id || !categories[0]?.id) throw new Error('Customer or Textile category was not found.');
  const categoryId = categories[0].id;
  const methods = await api(`/items/product_application_methods?fields=id,name&filter[category][_eq]=${categoryId}&filter[name][_eq]=Шелкография&limit=1`);
  if (!methods[0]?.id) throw new Error('Screen printing method was not found.');

  const order = await api('/items/orders', {
    method: 'POST',
    body: JSON.stringify({
      date: new Date().toISOString().slice(0, 10),
      customer: customers[0].id,
      order_status: 1,
      office_status: 'not_in_office',
      shipping_method: 'office_pickup',
    }),
  });
  orderId = order.id;
  const item = await api('/items/orders_items', {
    method: 'POST',
    body: JSON.stringify({
      order: orderId,
      product_name: 'QA Футболки',
      quantity: 20,
      price_per_unit: 1,
      order_sum: 20,
      product_category: categoryId,
      application_method: methods[0].id,
      blank_source: 'customer',
      item_status: 'new',
      office_status: 'not_in_office',
      shipping_method: 'office_pickup',
    }),
  });
  itemId = item.id;

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 960 }, colorScheme: 'dark' });
    await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('input[type="email"]').fill(credentials.email);
    await page.locator('input[type="password"]').fill(credentials.password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
    await page.goto(`${baseUrl}/admin/symbolika-orders?item=${itemId}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.waitForSelector('.symbolika-costing-page', { timeout: 30_000 });
    const builderButton = page.locator('button.symbolika-costing-tz-toggle').filter({ hasText: /Собрать ТЗ|Открыть конструктор/ }).first();
    await builderButton.waitFor({ state: 'visible', timeout: 20_000 });
    await builderButton.click();

    const modal = page.locator('.symbolika-costing-tz-modal');
    await modal.waitFor({ state: 'visible', timeout: 10_000 });
    await (await fieldByLabel(modal, 'Цвет изделия')).locator('input').fill('Черный');
    await (await fieldByLabel(modal, 'Количество принтов')).locator('input').fill('2');
    await modal.locator('.symbolika-costing-tz-size-grid label').filter({ hasText: /^XS/ }).locator('input').fill('5');
    await modal.locator('.symbolika-costing-tz-size-grid label').filter({ hasText: /^S/ }).locator('input').fill('15');
    await (await fieldByLabel(modal, 'Размер нанесения 1')).locator('select').selectOption({ label: 'А4' });
    await (await fieldByLabel(modal, 'Количество цветов нанесения 1')).locator('input').fill('2');
    await (await fieldByLabel(modal, 'Размер нанесения 2')).locator('select').selectOption({ label: 'А6' });
    await (await fieldByLabel(modal, 'Количество цветов нанесения 2')).locator('input').fill('1');

    const preview = modal.locator('.symbolika-costing-tz-preview strong');
    await preview.waitFor({ state: 'visible' });
    const previewText = (await preview.innerText()).replace(/\s+/g, ' ');
    for (const expected of ['Цвет изделия: Черный', 'XS — 5 шт.', 'S — 15 шт.', 'принт 1 — А4, 2 цвета', 'принт 2 — А6, 1 цвет']) {
      if (!previewText.includes(expected)) throw new Error(`Preview does not include "${expected}": ${previewText}`);
    }
    await modal.locator('.symbolika-costing-tz-size-total.is-valid').waitFor({ state: 'visible' });

    const sizeBox = await (await fieldByLabel(modal, 'Размер нанесения 1')).boundingBox();
    const colorsBox = await (await fieldByLabel(modal, 'Количество цветов нанесения 1')).boundingBox();
    if (!sizeBox || !colorsBox || Math.abs(sizeBox.y - colorsBox.y) > 12 || colorsBox.x <= sizeBox.x) {
      throw new Error(`Print fields are not aligned: ${JSON.stringify({ sizeBox, colorsBox })}`);
    }
    await modal.screenshot({ path: 'qa-results/textile-tz-desktop.png' });

    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(250);
    const overflow = await modal.evaluate((element) => element.scrollWidth - element.clientWidth);
    await modal.screenshot({ path: 'qa-results/textile-tz-mobile.png' });
    if (overflow > 2) {
      const offenders = await modal.evaluate((element) => [...element.querySelectorAll('*')]
        .map((node) => ({
          name: node.className || node.tagName,
          overflow: node.scrollWidth - node.clientWidth,
          right: Math.round(node.getBoundingClientRect().right - element.getBoundingClientRect().right),
        }))
        .filter((row) => row.overflow > 2 || row.right > 2)
        .sort((left, right) => Math.max(right.overflow, right.right) - Math.max(left.overflow, left.right))
        .slice(0, 8));
      throw new Error(`Mobile modal has horizontal overflow: ${overflow}px ${JSON.stringify(offenders)}`);
    }

    console.log(JSON.stringify({ passed: true, preview: previewText, desktopAligned: true, mobileOverflow: overflow }));
  } finally {
    await browser.close();
  }
})().finally(async () => {
  if (itemId) await api(`/items/orders_items/${itemId}`, { method: 'DELETE' }).catch(() => {});
  if (orderId) await api(`/items/orders/${orderId}`, { method: 'DELETE' }).catch(() => {});
  if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => {});
}).catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});

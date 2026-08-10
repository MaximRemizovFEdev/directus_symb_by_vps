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
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status}`);
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
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = { email: `qa-layout-progress-${suffix}@example.com`, password: `Qa!${crypto.randomBytes(18).toString('hex')}` };
  let userId;
  let customerId;
  let orderId;
  let itemId;
  let uploadRequested = false;
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 960 } });
  const page = await context.newPage();

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    const user = await api('/users', { method: 'POST', body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Layout Progress' }) });
    userId = user.id;
    const customer = await api('/items/customers', { method: 'POST', body: JSON.stringify({ name: `QA Layout Progress ${suffix}` }) });
    customerId = customer.id;

    await page.route('**/symbolika-yandex-disk/orders-items/*/upload', async (route) => {
      uploadRequested = true;
      if (!route.request().postDataBuffer()?.length) throw new Error('Upload request has no file body.');
      await new Promise((resolve) => setTimeout(resolve, 1400));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { url: 'https://disk.example.test/mock-layout.pdf', path: '/mock/layout.pdf', name: 'layout.pdf', size: 6 * 1024 * 1024, mime_type: 'application/pdf' } }),
      });
    });

    await login(page, credentials);
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    const openButton = page.locator('.symbolika-costing-actions .symbolika-costing-button').filter({ hasText: 'Новый заказ' }).first();
    await openButton.waitFor({ timeout: 60_000 });
    await openButton.click();

    const orderModal = page.locator('.symbolika-costing-order-modal');
    await orderModal.waitFor({ timeout: 15_000 });
    await orderModal.locator('select').filter({ has: page.locator('option', { hasText: `QA Layout Progress ${suffix}` }) }).selectOption(String(customerId));
    await orderModal.locator('input[list="symbolika-product-name-suggestions"]').first().fill(`QA макет ${suffix}`);
    await orderModal.locator('input[inputmode="decimal"]').first().fill('1');
    await orderModal.locator('.symbolika-layout-draft-button').first().click();

    const fileModal = page.locator('.symbolika-layout-upload-modal');
    await fileModal.locator('input[type="file"]').setInputFiles({
      name: 'layout.pdf',
      mimeType: 'application/pdf',
      buffer: Buffer.alloc(6 * 1024 * 1024, 65),
    });
    await fileModal.locator('.symbolika-costing-modal-actions .symbolika-costing-button').click();
    await fileModal.waitFor({ state: 'hidden' });

    const saveButton = orderModal.locator('.symbolika-costing-modal-actions .symbolika-costing-button');
    await saveButton.click();
    const progress = orderModal.locator('.symbolika-layout-save-progress');
    await progress.waitFor({ timeout: 20_000 });
    await progress.getByText(/Яндекс\.Диск/).waitFor({ timeout: 20_000 });
    if (!await saveButton.isDisabled()) throw new Error('Save button is not locked during upload.');
    if (!await orderModal.locator('.symbolika-costing-modal-actions .symbolika-costing-mini-button').isDisabled()) throw new Error('Close button is not locked during upload.');
    await orderModal.waitFor({ state: 'hidden', timeout: 30_000 });
    if (!uploadRequested) throw new Error('File upload request was not sent after saving the order.');

    const orders = await api(`/items/orders?filter[customer][_eq]=${customerId}&fields=id&limit=1`);
    orderId = orders[0]?.id;
    const items = orderId ? await api(`/items/orders_items?filter[order][_eq]=${orderId}&fields=id&limit=1`) : [];
    itemId = items[0]?.id;
    console.log(JSON.stringify({ uploadAfterSave: true, progressVisible: true, actionsLocked: true, closesAfterUpload: true }));
  } finally {
    await browser.close();
    if (itemId) await api(`/items/orders_items/${itemId}`, { method: 'DELETE' }).catch(() => null);
    if (orderId) await api(`/items/orders/${orderId}`, { method: 'DELETE' }).catch(() => null);
    if (customerId) await api(`/items/customers/${customerId}`, { method: 'DELETE' }).catch(() => null);
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => null);
  }
}

run().catch((error) => { console.error(error); process.exitCode = 1; });

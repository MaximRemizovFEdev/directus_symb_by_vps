const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;

if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

async function api(endpoint, options = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: {
      authorization: `Bearer ${adminToken}`,
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
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

async function triggerValidationToast(page) {
  const dialog = page.locator('.symbolika-costing-modal').filter({ hasText: 'Новый заказ' });
  if (!await dialog.isVisible().catch(() => false)) {
    const createButton = page.locator('.symbolika-costing-actions .symbolika-costing-button').filter({ hasText: 'Новый заказ' }).first();
    await createButton.waitFor({ timeout: 60_000 });
    await createButton.click();
    await dialog.waitFor({ timeout: 15_000 });
  }
  const submitButton = page.getByRole('button', { name: /Создать заказ/ }).last();
  await submitButton.waitFor({ timeout: 30_000 });
  await submitButton.click();
  const toast = page.locator('.symbolika-costing-error-toast');
  await toast.waitFor({ timeout: 10_000 });
  if (!String(await toast.textContent()).includes('Выберите клиента')) {
    throw new Error('Validation error text is not shown in the toast.');
  }
  const box = await toast.boundingBox();
  const viewport = page.viewportSize();
  if (!box || !viewport || box.x < 0 || box.y < 0 || box.x + box.width > viewport.width || box.y + box.height > viewport.height) {
    throw new Error('Error toast does not fit in the viewport.');
  }
  return toast;
}

async function run() {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-error-toast-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  let userId;
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 960 } });
  const page = await context.newPage();

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    const user = await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Error Toast' }),
    });
    userId = user.id;
    await login(page, credentials);
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });

    let toast = await triggerValidationToast(page);
    await toast.locator('.symbolika-costing-error-toast-close').click();
    await toast.waitFor({ state: 'hidden', timeout: 2_000 });

    toast = await triggerValidationToast(page);
    await toast.waitFor({ state: 'hidden', timeout: 6_500 });

    await page.setViewportSize({ width: 390, height: 844 });
    toast = await triggerValidationToast(page);
    await toast.locator('.symbolika-costing-error-toast-close').click();
    await toast.waitFor({ state: 'hidden', timeout: 2_000 });

    console.log(JSON.stringify({ desktop: true, autoClose: true, manualClose: true, mobile: true }));
  } finally {
    await browser.close();
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => null);
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

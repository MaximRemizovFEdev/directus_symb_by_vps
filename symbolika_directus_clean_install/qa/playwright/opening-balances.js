const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const resultsDir = path.resolve(__dirname, 'qa-results', 'opening-balances');

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
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`.trim());
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
  fs.mkdirSync(resultsDir, { recursive: true });
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-opening-balance-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  let userId;
  let customerId;
  const browser = await chromium.launch({ headless: process.argv.includes('--headed') === false });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const badResponses = [];
  page.on('response', (response) => {
    const pathname = new URL(response.url()).pathname;
    const ignored = pathname.startsWith('/assets/')
      || (pathname === '/auth/refresh' && response.status() === 400)
      || (pathname === '/translations' && response.status() === 403);
    if (response.status() >= 400 && !ignored) {
      badResponses.push(`${response.status()} ${response.url()}`);
    }
  });

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    if (!roles?.[0]?.id) throw new Error('Administrator role not found.');
    const user = await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Opening Balance' }),
    });
    userId = user.id;

    const customer = await api('/items/customers', {
      method: 'POST',
      body: JSON.stringify({
        name: `QA Остаток ${suffix}`,
        opening_balance_amount: 1543.21,
        opening_balance_direction: 'customer_owes_us',
        opening_balance_date: '2026-01-15',
        opening_balance_comment: 'Перенос из старой системы',
      }),
    });
    customerId = customer.id;

    const createdOperations = await api(`/items/customer_operations?filter[customer][_eq]=${customerId}&filter[operation_type][_eq]=opening_balance&fields=id,amount,direction,status&limit=-1`);
    if (createdOperations.length !== 1 || Number(createdOperations[0].amount) !== 1543.21 || createdOperations[0].status !== 'confirmed') {
      throw new Error('Opening balance operation was not created correctly through API.');
    }

    await login(page, credentials);
    await page.goto(`${baseUrl}/admin/symbolika-clients`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.getByRole('button', { name: customer.name, exact: true }).waitFor({ timeout: 30_000 });
    await page.getByRole('button', { name: customer.name, exact: true }).click();
    await page.getByText('Начальный остаток взаиморасчётов', { exact: true }).waitFor({ timeout: 15_000 });
    await page.locator('.symbolika-costing-opening-balance-card').screenshot({ path: path.join(resultsDir, 'client-card.png') });

    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    const newOrderButton = page.locator('button[title="Новый заказ"]').first();
    await newOrderButton.waitFor({ timeout: 30_000 });
    await newOrderButton.click();
    const modal = page.locator('.symbolika-costing-order-modal');
    await modal.waitFor({ timeout: 15_000 });
    await modal.locator('.symbolika-costing-field-with-action button').first().click();
    await modal.getByText('Начальный остаток клиента (необязательно)', { exact: true }).waitFor();
    await modal.locator('.symbolika-costing-field-with-action button').nth(1).click();
    await modal.getByText('Начальный остаток компании (необязательно)', { exact: true }).waitFor();
    await modal.screenshot({ path: path.join(resultsDir, 'new-order.png') });

    if (badResponses.length) throw new Error(`Unexpected HTTP errors:\n${badResponses.join('\n')}`);
    console.log('opening balances UI/API: OK');
  } finally {
    await browser.close();
    if (customerId) await api(`/items/customers/${customerId}`, { method: 'DELETE' }).catch(() => {});
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => {});
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

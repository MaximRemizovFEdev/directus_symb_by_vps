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
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`);
  return payload?.data ?? payload;
}

(async () => {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const role = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
  const credentials = {
    email: `qa-contractor-site-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const user = await api('/users', {
    method: 'POST',
    body: JSON.stringify({ ...credentials, role: role[0].id, status: 'active', first_name: 'QA', last_name: 'Contractor site' }),
  });
  let contractorId = null;
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, colorScheme: 'dark' });
    await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('input[type="email"]').fill(credentials.email);
    await page.locator('input[type="password"]').fill(credentials.password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
    await page.goto(`${baseUrl}/admin/symbolika-admin`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.waitForSelector('.symbolika-costing-page', { timeout: 30_000 });
    await page.locator('.symbolika-costing-side-nav button').filter({ hasText: 'Контрагенты' }).click();
    await page.waitForSelector('.symbolika-costing-admin-head');
    await page.locator('.symbolika-costing-admin-head button').filter({ hasText: 'Добавить' }).click();

    const testName = `QA Сайт контрагента ${suffix}`;
    await page.locator('label').filter({ hasText: /^Название \*/ }).locator('input').fill(testName);
    await page.locator('label').filter({ hasText: /^Сайт/ }).locator('input').fill('example.com/catalog');
    await page.locator('.symbolika-costing-admin-actions button').filter({ hasText: 'Сохранить' }).click();
    await page.waitForFunction((name) => document.body.innerText.includes(name), testName, { timeout: 15_000 });

    const rows = await api(`/items/contractors?filter[name][_eq]=${encodeURIComponent(testName)}&fields=id,website_url&limit=1`);
    contractorId = rows[0]?.id || null;
    const link = page.locator(`a.symbolika-costing-contractor-site[href="https://example.com/catalog"]`).first();
    await link.waitFor({ state: 'visible', timeout: 10_000 });
    if (rows[0]?.website_url !== 'https://example.com/catalog') {
      throw new Error(`Website was not normalized: ${rows[0]?.website_url || 'empty'}`);
    }
    console.log(JSON.stringify({ passed: true, website_url: rows[0].website_url, linkVisible: true }));
  } finally {
    await browser.close();
    if (contractorId) await api(`/items/contractors/${contractorId}`, { method: 'DELETE' }).catch(() => {});
    await api(`/users/${user.id}`, { method: 'DELETE' }).catch(() => {});
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});

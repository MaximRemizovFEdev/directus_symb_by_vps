const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN.');

async function api(endpoint, options = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json', ...(options.headers || {}) },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status}`);
  return payload?.data ?? payload;
}

async function run() {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = { email: `qa-modal-stack-${suffix}@example.com`, password: `Qa!${crypto.randomBytes(18).toString('hex')}` };
  let userId;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 960 } });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    userId = (await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Modal Stack' }),
    })).id;

    await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('input[type="email"]').fill(credentials.email);
    await page.locator('input[type="password"]').fill(credentials.password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('.symbolika-costing-page').waitFor({ timeout: 60_000 });
    await page.waitForTimeout(4000);

    const layers = await page.evaluate(async () => {
      const root = document.querySelector('.symbolika-costing-page');
      const add = (className, marker) => {
        const element = document.createElement(className.includes('detail') && !className.includes('backdrop') ? 'aside' : 'div');
        element.className = className;
        element.dataset.qaOverlay = marker;
        root.appendChild(element);
        return element;
      };

      const firstModal = add('symbolika-costing-modal-backdrop', 'first-modal');
      await new Promise((resolve) => setTimeout(resolve, 30));
      add('symbolika-costing-detail-backdrop', 'detail-backdrop');
      const detail = add('symbolika-costing-detail', 'detail');
      await new Promise((resolve) => setTimeout(resolve, 30));
      const secondModal = add('symbolika-costing-modal-backdrop', 'second-modal');
      await new Promise((resolve) => setTimeout(resolve, 30));

      const result = {
        firstModal: Number(getComputedStyle(firstModal).zIndex),
        detail: Number(getComputedStyle(detail).zIndex),
        secondModal: Number(getComputedStyle(secondModal).zIndex),
      };
      document.querySelectorAll('[data-qa-overlay]').forEach((element) => element.remove());
      return result;
    });

    if (!(layers.firstModal < layers.detail && layers.detail < layers.secondModal)) {
      throw new Error(`Неверный порядок слоёв: ${JSON.stringify(layers)}; ошибки страницы: ${JSON.stringify(pageErrors)}`);
    }
    console.log(JSON.stringify({ newestOverlayOnTop: true, layers }));
  } finally {
    await browser.close();
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => null);
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

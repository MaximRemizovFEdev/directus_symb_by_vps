const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const resultsDir = path.resolve(__dirname, 'qa-results', 'pilot-safety');

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
  if (!response.ok) {
    throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || payload?.error || ''}`.trim());
  }
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
  const reportComment = `QA pilot feedback ${suffix}: проверка контекста страницы`;
  const credentials = {
    email: `qa-pilot-safety-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  let userId;
  let reportId;
  const browser = await chromium.launch({ headless: !process.argv.includes('--headed') });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const badResponses = [];
  page.on('response', (response) => {
    const pathname = new URL(response.url()).pathname;
    const ignored = pathname.startsWith('/assets/')
      || (pathname === '/auth/refresh' && response.status() === 400)
      || (pathname === '/translations' && response.status() === 403);
    if (response.status() >= 400 && !ignored) badResponses.push(`${response.status()} ${response.url()}`);
  });

  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    if (!roles?.[0]?.id) throw new Error('Administrator role not found.');
    const user = await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Pilot Safety' }),
    });
    userId = user.id;

    await login(page, credentials);
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });

    const feedbackButton = page.getByTitle('Сообщить об ошибке');
    await feedbackButton.waitFor({ timeout: 30_000 });
    await feedbackButton.click();
    const feedbackModal = page.locator('.symbolika-costing-feedback-modal');
    await feedbackModal.waitFor();
    await feedbackModal.locator('textarea').fill(reportComment);
    await feedbackModal.getByRole('button', { name: 'Отправить', exact: true }).click();
    await page.getByText('Спасибо. Сообщение и контекст страницы сохранены.', { exact: true }).waitFor({ timeout: 15_000 });

    const reports = await api('/symbolika-support/reports');
    const createdReport = reports.find((row) => row.comment === reportComment);
    if (!createdReport) throw new Error('Feedback report was not persisted.');
    reportId = createdReport.id;
    if (!String(createdReport.page_url || '').includes('/admin/symbolika-orders') || createdReport.reported_by !== userId) {
      throw new Error('Feedback report has incomplete page/user context.');
    }

    await page.getByTitle('Новый заказ').first().click();
    let orderModal = page.locator('.symbolika-costing-order-modal');
    await orderModal.waitFor();
    await orderModal.locator('.symbolika-costing-new-order-item').first().locator('input').nth(0).fill(`QA Черновик ${suffix}`);
    await orderModal.locator('.symbolika-costing-new-order-item').first().locator('input').nth(1).fill('7');
    await orderModal.locator('.symbolika-costing-detail-close').click();
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 60_000 });

    const draftModal = page.locator('.symbolika-costing-draft-modal');
    await draftModal.waitFor({ timeout: 30_000 });
    await draftModal.screenshot({ path: path.join(resultsDir, 'draft-recovery.png') });
    await draftModal.getByRole('button', { name: /Восстановить/ }).click();
    orderModal = page.locator('.symbolika-costing-order-modal');
    await orderModal.waitFor();
    const restoredInputs = orderModal.locator('.symbolika-costing-new-order-item').first().locator('input');
    if (await restoredInputs.nth(0).inputValue() !== `QA Черновик ${suffix}` || await restoredInputs.nth(1).inputValue() !== '7') {
      throw new Error('Order draft fields were not restored.');
    }
    await orderModal.locator('.symbolika-costing-detail-close').click();
    await page.evaluate(() => {
      Object.keys(localStorage).filter((key) => key.startsWith('symbolika-order-draft:')).forEach((key) => localStorage.removeItem(key));
    });

    const healthBefore = await api('/symbolika-support/automation-health');
    if (!healthBefore.handlers?.some((handler) => handler.handler_key === 'workflow_consistency')) {
      throw new Error('Workflow health handler is missing.');
    }
    await api('/symbolika-support/automation-health/retry', {
      method: 'POST',
      body: JSON.stringify({ type: 'workflow_consistency' }),
    });
    const healthAfter = await api('/symbolika-support/automation-health');
    const workflow = healthAfter.handlers.find((handler) => handler.handler_key === 'workflow_consistency');
    if (!workflow?.last_success_at || workflow.status !== 'ok') throw new Error('Safe workflow retry did not finish successfully.');

    await page.goto(`${baseUrl}/admin/symbolika-management`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.getByText('Контроль автоматизаций', { exact: true }).waitFor({ timeout: 30_000 });
    await page.getByText('Контроль автоматизаций', { exact: true }).click();
    await page.getByText('Здоровье обработчиков', { exact: true }).waitFor({ timeout: 30_000 });
    await page.locator('.symbolika-costing-health-panel').screenshot({ path: path.join(resultsDir, 'automation-health.png') });

    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await feedbackButton.waitFor({ timeout: 30_000 });
    const buttonBox = await feedbackButton.boundingBox();
    if (!buttonBox || buttonBox.x < 0 || buttonBox.y < 0 || buttonBox.x + buttonBox.width > 390 || buttonBox.y + buttonBox.height > 844) {
      throw new Error('Mobile feedback button is outside viewport.');
    }
    await page.screenshot({ path: path.join(resultsDir, 'mobile-feedback-button.png'), fullPage: false });

    if (badResponses.length) throw new Error(`Unexpected HTTP errors:\n${badResponses.join('\n')}`);
    console.log('pilot safety UI/API: OK');
  } finally {
    await browser.close();
    if (reportId) await api(`/items/symbolika_feedback_reports/${reportId}`, { method: 'DELETE' }).catch(() => {});
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => {});
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

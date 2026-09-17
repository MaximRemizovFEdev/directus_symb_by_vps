const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const configuredEmail = process.env.SYMBOLIKA_QA_EMAIL;
const configuredPassword = process.env.SYMBOLIKA_QA_PASSWORD;
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const selectedTheme = process.env.SYMBOLIKA_QA_THEME || 'graphite';
const viewportWidth = Math.max(390, Number(process.env.SYMBOLIKA_QA_VIEWPORT_WIDTH || 1440));
const viewportHeight = Math.max(700, Number(process.env.SYMBOLIKA_QA_VIEWPORT_HEIGHT || 900));
const sendReply = process.env.SYMBOLIKA_QA_SEND_REPLY !== '0';
const qaVariant = `${selectedTheme}-${viewportWidth}`;
const resultsDir = path.resolve(__dirname, 'qa-results');

if ((!configuredEmail || !configuredPassword) && !adminToken) {
  throw new Error('Set SYMBOLIKA_QA_EMAIL/SYMBOLIKA_QA_PASSWORD or SYMBOLIKA_QA_ADMIN_TOKEN.');
}
fs.mkdirSync(resultsDir, { recursive: true });

async function api(endpoint, options = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json', ...(options.headers || {}) },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`);
  return payload?.data ?? payload;
}

async function temporaryAdmin() {
  const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
  const credentials = {
    email: `qa-mail-${Date.now()}-${crypto.randomBytes(3).toString('hex')}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const user = await api('/users', {
    method: 'POST',
    body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Mail' }),
  });
  return { ...credentials, id: user.id };
}

(async () => {
  const credentials = configuredEmail && configuredPassword
    ? { email: configuredEmail, password: configuredPassword, id: null }
    : await temporaryAdmin();
  if (credentials.id && adminToken) {
    await api(`/users/${credentials.id}`, { method: 'PATCH', body: JSON.stringify({ symbolika_theme: selectedTheme }) });
  }
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: viewportWidth, height: viewportHeight }, colorScheme: selectedTheme === 'pearl' || selectedTheme === 'frost' ? 'light' : 'dark' });
  const page = await context.newPage();
  const httpFailures = [];
  const consoleErrors = [];
  page.on('response', (response) => {
    const pathname = new URL(response.url()).pathname;
    const ignored = pathname === '/auth/refresh' || pathname === '/translations' || pathname.startsWith('/assets/');
    if (response.url().startsWith(baseUrl) && response.status() >= 400 && !ignored) {
      httpFailures.push({ status: response.status(), url: response.url().replace(baseUrl, '') });
    }
  });
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });

  try {
    await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.locator('input[type="email"]').fill(credentials.email);
    await page.locator('input[type="password"]').fill(credentials.password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
    await page.evaluate((theme) => {
      localStorage.setItem('symbolika-theme', theme);
      document.documentElement.dataset.symbolikaTheme = theme;
      document.body.dataset.symbolikaTheme = theme;
      window.dispatchEvent(new CustomEvent('symbolika-theme-change', { detail: { theme } }));
    }, selectedTheme);

    await page.goto(`${baseUrl}/admin/symbolika-mail-module`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await page.waitForSelector('.symbolika-mail-page', { timeout: 30_000 });
    await page.waitForSelector('.symbolika-mail-thread', { timeout: 30_000 });
    await page.waitForTimeout(700);
    const navigationOverlay = page.locator('#dialog-outlet .overlay').first();
    if (await navigationOverlay.isVisible().catch(() => false)) {
      await navigationOverlay.evaluate((element) => element.click());
      await navigationOverlay.waitFor({ state: 'hidden', timeout: 3_000 }).catch(() => {});
    }
    await page.screenshot({ path: path.join(resultsDir, `mail-inbox-${qaVariant}.png`), fullPage: false });

    await page.locator('.symbolika-mail-thread').first().click();
    await page.waitForSelector('.symbolika-mail-message', { timeout: 15_000 });
    await page.waitForTimeout(350);
    await page.screenshot({ path: path.join(resultsDir, `mail-thread-${qaVariant}.png`), fullPage: false });

    const layout = await page.evaluate(() => {
      const viewportWidth = document.documentElement.clientWidth;
      const interactive = [...document.querySelectorAll('.symbolika-mail-page button, .symbolika-mail-page input, .symbolika-mail-page textarea, .symbolika-mail-page select, .symbolika-mail-side-nav button')];
      const outside = interactive.map((element) => {
        const rect = element.getBoundingClientRect();
        return { text: (element.innerText || element.value || '').trim().slice(0, 50), left: rect.left, right: rect.right };
      }).filter((row) => row.left < -2 || row.right > viewportWidth + 2);
      const systemRail = document.querySelector('.module-bar, .modules');
      const mailNavigation = document.querySelector('.symbolika-mail-side-nav');
      const navChildren = mailNavigation ? [...mailNavigation.querySelectorAll('button')] : [];
      const navRect = mailNavigation?.getBoundingClientRect();
      const clippedNavigation = navChildren.map((element) => {
        const rect = element.getBoundingClientRect();
        return { text: element.innerText.trim().slice(0, 50), left: rect.left, right: rect.right };
      }).filter((row) => navRect && (row.left < navRect.left - 1 || row.right > navRect.right + 1));
      return {
        documentOverflow: Math.max(0, document.documentElement.scrollWidth - viewportWidth),
        outside,
        clippedNavigation,
        navigationOverflow: mailNavigation ? Math.max(0, mailNavigation.scrollWidth - mailNavigation.clientWidth) : null,
        systemRailScrollbarWidth: systemRail ? getComputedStyle(systemRail).scrollbarWidth : null,
        threads: document.querySelectorAll('.symbolika-mail-thread').length,
        messages: document.querySelectorAll('.symbolika-mail-message').length,
        subject: document.querySelector('.symbolika-mail-reader-title h2')?.textContent?.trim() || '',
        bodyText: document.body.innerText,
      };
    });

    let responseVisible = true;
    if (sendReply) {
      await page.getByRole('button', { name: 'Ответить' }).first().click();
      await page.waitForSelector('.symbolika-mail-dialog');
      await page.locator('.symbolika-mail-textarea').fill('Тестовый ответ из Playwright. Проверяем форму и отображение переписки.');
      await page.locator('.symbolika-mail-dialog button[type="submit"]').click();
      await page.waitForSelector('.symbolika-mail-dialog', { state: 'detached', timeout: 15_000 });
      await page.waitForTimeout(500);
      responseVisible = Boolean(await page.getByText('Тестовый ответ из Playwright.', { exact: false }).count());
    }

    const settingsButton = page.locator('button[title="Настройки почты"]').first();
    let settingsVisible = false;
    if (await settingsButton.isVisible().catch(() => false)) {
      await settingsButton.click();
      settingsVisible = await page.locator('.symbolika-mail-dialog.is-settings').waitFor({ timeout: 5_000 }).then(() => true).catch(() => false);
      if (settingsVisible) await page.screenshot({ path: path.join(resultsDir, `mail-settings-${qaVariant}.png`), fullPage: false });
    }

    const report = {
      layout: { ...layout, bodyText: undefined },
      responseVisible: Boolean(responseVisible),
      settingsVisible,
      httpFailures,
      consoleErrors,
      checks: {
        testMode: viewportWidth <= 760 || /тестовая почта/i.test(layout.bodyText),
        hasThreads: layout.threads >= 1,
        openedThread: layout.messages >= 1 && Boolean(layout.subject),
        noHorizontalOverflow: layout.documentOverflow <= 2 && layout.outside.length === 0,
        navigationFits: (layout.navigationOverflow === null || layout.navigationOverflow === 0) && layout.clippedNavigation.length === 0,
        systemRailScrollbarHidden: layout.systemRailScrollbarWidth === null || layout.systemRailScrollbarWidth === 'none',
      },
    };
    fs.writeFileSync(path.join(resultsDir, `mail-report-${qaVariant}.json`), `${JSON.stringify(report, null, 2)}\n`);
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    const failed = Object.entries(report.checks).filter(([, value]) => !value).map(([key]) => key);
    if (sendReply && !responseVisible) failed.push('mock reply');
    if (httpFailures.length) failed.push('http failures');
    if (failed.length) process.exitCode = 1;
  } finally {
    await browser.close();
    if (credentials.id && adminToken) await api(`/users/${credentials.id}`, { method: 'DELETE' }).catch(() => {});
  }
})();

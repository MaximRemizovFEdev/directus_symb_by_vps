const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const headed = process.argv.includes('--headed');
const viewport = { width: 1280, height: 800 };
const resultsDir = path.resolve(__dirname, 'qa-results');

if (!adminToken) {
  throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');
}

fs.mkdirSync(resultsDir, { recursive: true });

async function waitForServer(timeoutMs = 90_000) {
  const startedAt = Date.now();
  let lastError = null;
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await fetch(`${baseUrl}/server/health`);
      if (response.ok) return;
      lastError = new Error(`health returned ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_500));
  }
  throw new Error(`Directus did not become healthy within ${timeoutMs}ms: ${lastError?.message || 'unknown error'}`);
}

const roleCases = [
  { key: 'admin', role: 'Administrator', modules: ['symbolika-orders', 'symbolika-management', 'symbolika-procurement', 'symbolika-admin', 'symbolika-clients', 'symbolika-production', 'symbolika-finance', 'symbolika-mail-module', 'symbolika-profile-module'] },
  { key: 'managerial', role: 'Управляющий', modules: ['symbolika-orders', 'symbolika-management', 'symbolika-procurement', 'symbolika-clients', 'symbolika-finance'] },
  { key: 'manager', role: 'Менеджер', modules: ['symbolika-orders', 'symbolika-procurement', 'symbolika-clients', 'symbolika-finance'] },
  { key: 'office', role: 'Офис-менеджер', modules: ['symbolika-orders', 'symbolika-procurement'] },
  { key: 'production', role: 'Производство', modules: ['symbolika-production', 'symbolika-procurement'] },
  { key: 'screen', role: 'Шелкография', modules: ['symbolika-production', 'symbolika-procurement'] },
  { key: 'designer', role: 'Дизайнер', modules: ['symbolika-tasks', 'symbolika-procurement'] },
];

const optionalRoleTokens = Object.fromEntries(roleCases.map(({ key }) => [
  key,
  process.env[`SYMBOLIKA_QA_${key.toUpperCase()}_TOKEN`] || null,
]));
const selectedRoleKeys = new Set(String(process.env.SYMBOLIKA_QA_ROLES || '')
  .split(',').map((value) => value.trim()).filter(Boolean));
const selectedRoleCases = selectedRoleKeys.size
  ? roleCases.filter(({ key }) => selectedRoleKeys.has(key))
  : roleCases;

async function api(token, endpoint, options = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`.trim());
  }
  return payload?.data ?? payload;
}

async function roleIdByName(name) {
  const rows = await api(adminToken, `/roles?filter[name][_eq]=${encodeURIComponent(name)}&fields=id,name&limit=1`);
  if (!rows[0]?.id) throw new Error(`Role not found: ${name}`);
  return rows[0].id;
}

async function createTemporaryUser(roleName, key) {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-e2e-${key}-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const user = await api(adminToken, '/users', {
    method: 'POST',
    body: JSON.stringify({
      ...credentials,
      role: await roleIdByName(roleName),
      status: 'active',
      first_name: 'QA',
      last_name: 'Playwright',
    }),
  });
  return { ...credentials, id: user.id };
}

async function login(page, credentials) {
  await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.locator('input[type="email"]').fill(credentials.email);
  await page.locator('input[type="password"]').fill(credentials.password);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
}

function ignoredHttpFailure(response) {
  const pathname = new URL(response.url()).pathname;
  return (pathname === '/auth/refresh' && response.status() === 400)
    || (pathname === '/translations' && response.status() === 403)
    || pathname.startsWith('/assets/');
}

async function inspectLayout(page) {
  return page.evaluate(() => {
    const visible = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 1 && rect.height > 1 && style.display !== 'none' && style.visibility !== 'hidden';
    };
    const viewportWidth = document.documentElement.clientWidth;
    const interactive = [...document.querySelectorAll('.symbolika-costing-page button, .symbolika-costing-page input, .symbolika-costing-page select, .symbolika-costing-page textarea, aside.symbolika-costing-detail')];
    const outside = interactive.filter(visible).map((element) => {
      const rect = element.getBoundingClientRect();
      return { text: (element.innerText || element.value || '').trim().slice(0, 60), left: Math.round(rect.left), right: Math.round(rect.right) };
    }).filter(({ left, right }) => left < -2 || right > viewportWidth + 2);
    const bodyText = document.body.innerText;
    return {
      documentOverflow: Math.max(0, document.documentElement.scrollWidth - viewportWidth),
      outside,
      errorBanners: [...document.querySelectorAll('.symbolika-costing-error')].filter(visible).map((element) => element.innerText.trim()),
      mojibake: /(?:Р[Ѐ-ӿ]|С[Ѐ-ӿ]){3,}/.test(bodyText),
      activeSection: document.querySelector('.symbolika-costing-side-item.is-active')?.innerText?.trim() || null,
    };
  });
}

async function inspectStickyToolbar(page) {
  return page.evaluate(async () => {
    const toolbar = document.querySelector('.symbolika-costing-smart-toolbar');
    if (!toolbar) return { found: false };
    let scroller = toolbar.parentElement;
    while (scroller && scroller !== document.body) {
      const style = getComputedStyle(scroller);
      if (/(auto|scroll)/.test(style.overflowY) && scroller.scrollHeight > scroller.clientHeight) break;
      scroller = scroller.parentElement;
    }
    if (!scroller || scroller === document.body) scroller = document.scrollingElement;
    const before = toolbar.getBoundingClientRect().top;
    const maxScroll = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
    scroller.scrollTop = Math.min(600, maxScroll);
    scroller.dispatchEvent(new Event('scroll'));
    await new Promise((resolve) => setTimeout(resolve, 250));
    return {
      found: true,
      position: getComputedStyle(toolbar).position,
      before: Math.round(before),
      after: Math.round(toolbar.getBoundingClientRect().top),
      scrollTop: Math.round(scroller.scrollTop),
      maxScroll: Math.round(maxScroll),
    };
  });
}

async function inspectPrimaryModules(page) {
  return page.locator('.module-bar a[href], nav a[href]').evaluateAll((links) => links.map((link) => ({
    href: link.getAttribute('href') || '',
    label: (link.getAttribute('aria-label') || link.getAttribute('title') || link.textContent || '').trim(),
    visible: Boolean(link.offsetWidth || link.offsetHeight || link.getClientRects().length),
  })).filter((link) => link.href.includes('/admin/symbolika-')));
}

async function inspectPositionDeepLink(page) {
  await page.waitForSelector('.symbolika-costing-side-item', { timeout: 30_000 });
  const labels = await page.locator('.symbolika-costing-side-item').allInnerTexts();
  const clicked = await page.locator('.symbolika-costing-side-item').evaluateAll((items) => {
    const target = items.find((item) => item.textContent?.includes('Все заказы'));
    if (!target) return false;
    target.click();
    return true;
  });
  if (!clicked) return { skipped: 'Нет вкладки «Все заказы»', labels };
  await page.waitForTimeout(1_200);
  const expandButtons = page.locator('.symbolika-costing-table-all-orders .symbolika-costing-expand');
  for (let index = 0; index < await expandButtons.count(); index += 1) {
    await expandButtons.nth(index).click();
    const positions = page.locator('.symbolika-costing-position-row-clickable');
    if (!await positions.count()) continue;
    await positions.first().click();
    await page.waitForSelector('aside.symbolika-costing-detail', { timeout: 8_000 });
    const linkedUrl = page.url();
    await page.reload({ waitUntil: 'domcontentloaded' });
    const reopened = await page.waitForSelector('aside.symbolika-costing-detail', { timeout: 10_000 }).then(() => true).catch(() => false);
    return { linkedUrl, reopened };
  }
  return { skipped: 'В доступных заказах нет позиций' };
}

function assertScreen(result) {
  const failures = [];
  if (result.layout.documentOverflow > 2) failures.push(`document overflow ${result.layout.documentOverflow}px`);
  if (result.layout.outside.length) failures.push(`${result.layout.outside.length} controls outside viewport`);
  if (result.layout.errorBanners.length) failures.push(`error banners: ${result.layout.errorBanners.join('; ')}`);
  if (result.layout.mojibake) failures.push('mojibake detected');
  if (result.httpFailures.length) failures.push(`HTTP errors: ${result.httpFailures.map(({ status, path }) => `${status} ${path}`).join(', ')}`);
  return failures;
}

(async () => {
  await waitForServer();
  const browser = await chromium.launch({ headless: !headed });
  const temporaryUsers = [];
  const report = { startedAt: new Date().toISOString(), baseUrl, viewport, screens: [], specialChecks: {}, failures: [] };
  try {
    for (const roleCase of selectedRoleCases) {
      const credentials = await createTemporaryUser(roleCase.role, roleCase.key);
      temporaryUsers.push(credentials.id);
      const context = await browser.newContext({ viewport, colorScheme: 'dark' });
      const page = await context.newPage();
      const httpFailures = [];
      page.on('response', (response) => {
        if (response.url().startsWith(baseUrl) && response.status() >= 400 && !ignoredHttpFailure(response)) {
          httpFailures.push({ status: response.status(), path: response.url().replace(baseUrl, '').slice(0, 220) });
        }
      });
      await login(page, credentials);
      const representativeToken = optionalRoleTokens[roleCase.key];
      if (representativeToken) {
        await page.route(`${baseUrl}/items/**`, (route) => route.continue({
          headers: { ...route.request().headers(), authorization: `Bearer ${representativeToken}` },
        }));
      }
      for (const moduleName of roleCase.modules) {
        httpFailures.length = 0;
        await page.goto(`${baseUrl}/admin/${moduleName}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
        await page.waitForSelector(moduleName === 'symbolika-mail-module' ? '.symbolika-mail-page' : '.symbolika-costing-page', { timeout: 30_000 });
        await page.waitForTimeout(900);
        const result = {
          role: roleCase.role,
          module: moduleName,
          layout: await inspectLayout(page),
          httpFailures: [...httpFailures],
        };
        result.failures = assertScreen(result);
        report.screens.push(result);
        report.failures.push(...result.failures.map((message) => `${roleCase.key}/${moduleName}: ${message}`));
        if (result.failures.length) {
          await page.screenshot({ path: path.join(resultsDir, `${roleCase.key}-${moduleName}.png`), fullPage: false });
        }
      }
      if (roleCase.key === 'admin') {
        report.specialChecks.primaryModules = await inspectPrimaryModules(page);
        for (const modulePath of ['symbolika-mail-module', 'symbolika-profile-module']) {
          if (!report.specialChecks.primaryModules.some((link) => link.visible && link.href.includes(modulePath))) {
            report.failures.push(`primary module is not visible: ${modulePath}`);
          }
        }
        await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
        await page.waitForTimeout(1_200);
        report.specialChecks.positionDeepLink = await inspectPositionDeepLink(page);
        if (!report.specialChecks.positionDeepLink.skipped) {
          await page.locator('.symbolika-costing-detail-close').first().click().catch(() => {});
          await page.waitForTimeout(250);
        }
        report.specialChecks.stickyToolbar = await inspectStickyToolbar(page);
      }
      await context.close();
      await api(adminToken, `/users/${credentials.id}`, { method: 'DELETE' });
      temporaryUsers.splice(temporaryUsers.indexOf(credentials.id), 1);
    }
    const sticky = report.specialChecks.stickyToolbar;
    const stickyMoved = sticky?.scrollTop > 0 && Math.abs(sticky.after - sticky.before) > 2;
    if (!sticky?.found || sticky.position !== 'sticky' || stickyMoved) report.failures.push(`sticky toolbar failed: ${JSON.stringify(sticky)}`);
    const deepLink = report.specialChecks.positionDeepLink;
    if (deepLink && !deepLink.skipped && !deepLink.reopened) report.failures.push(`position deep-link failed: ${JSON.stringify(deepLink)}`);
  } finally {
    await browser.close();
    for (const id of temporaryUsers) {
      await api(adminToken, `/users/${id}`, { method: 'DELETE' }).catch(() => {});
    }
  }
  report.finishedAt = new Date().toISOString();
  report.passed = report.failures.length === 0;
  fs.writeFileSync(path.join(resultsDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({ passed: report.passed, screens: report.screens.length, specialChecks: report.specialChecks, failures: report.failures }, null, 2));
  if (!report.passed) process.exitCode = 1;
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});

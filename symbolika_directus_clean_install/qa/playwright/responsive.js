const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const resultsDir = path.resolve(__dirname, 'qa-results', 'responsive');
const captureAllScreens = process.env.SYMBOLIKA_QA_CAPTURE_ALL === '1';
const inspectOrderForm = process.env.SYMBOLIKA_QA_OPEN_ORDER_FORM === '1';
const debugNavigation = process.env.SYMBOLIKA_QA_DEBUG_NAV === '1';
const inspectOrderList = process.env.SYMBOLIKA_QA_ORDER_LIST === '1';
const inspectMobileNavigation = process.env.SYMBOLIKA_QA_MOBILE_NAV === '1';
const inspectOrderDetail = process.env.SYMBOLIKA_QA_ORDER_DETAIL === '1';

if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

const allViewports = [
  { key: 'phone-360', width: 360, height: 800, mobile: true },
  { key: 'phone-390', width: 390, height: 844, mobile: true },
  { key: 'tablet-portrait', width: 768, height: 1024, mobile: false },
  { key: 'tablet-landscape', width: 1024, height: 768, mobile: false },
  { key: 'desktop-wide', width: 1920, height: 1080, mobile: false },
];

const allModules = [
  'symbolika-orders',
  'symbolika-tasks',
  'symbolika-production',
  'symbolika-management',
  'symbolika-procurement',
  'symbolika-clients',
  'symbolika-finance',
  'symbolika-admin',
  'symbolika-mail-module',
  'symbolika-profile-module',
];

function selectedValues(environmentName, available, keySelector = (item) => item) {
  const requested = String(process.env[environmentName] || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  if (!requested.length) return available;
  const selected = available.filter((item) => requested.includes(keySelector(item)));
  if (!selected.length) throw new Error(`${environmentName} does not match any configured values.`);
  return selected;
}

const viewports = selectedValues('SYMBOLIKA_QA_VIEWPORTS', allViewports, (viewport) => viewport.key);
const modules = selectedValues('SYMBOLIKA_QA_MODULES', allModules);

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

async function createUser() {
  const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
  if (!roles?.[0]?.id) throw new Error('Administrator role not found.');
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-responsive-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const user = await api('/users', {
    method: 'POST',
    body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Responsive' }),
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

function ignoredResponse(response) {
  const pathname = new URL(response.url()).pathname;
  return pathname.startsWith('/assets/')
    || (pathname === '/translations' && response.status() === 403)
    || (pathname === '/auth/refresh' && response.status() === 400);
}

async function inspect(page) {
  return page.evaluate(() => {
    const root = document.querySelector('.symbolika-costing-page, .symbolika-mail-page');
    const visible = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 1 && rect.height > 1 && style.display !== 'none' && style.visibility !== 'hidden';
    };
    const hasHorizontalScroller = (element) => {
      let parent = element.parentElement;
      while (parent && parent !== document.body) {
        const style = getComputedStyle(parent);
        if (/(auto|scroll)/.test(style.overflowX) && parent.scrollWidth > parent.clientWidth + 2) return true;
        parent = parent.parentElement;
      }
      return false;
    };
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    const interactive = [...document.querySelectorAll('button, input, select, textarea, a[href], aside.symbolika-costing-detail')]
      .filter(visible);
    const outside = interactive.map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        tag: element.tagName.toLowerCase(),
        text: (element.innerText || element.value || element.getAttribute('aria-label') || '').trim().slice(0, 70),
        left: Math.round(rect.left),
        right: Math.round(rect.right),
        width: Math.round(rect.width),
        scrollable: hasHorizontalScroller(element),
      };
    }).filter((item) => !item.scrollable && (item.left < -2 || item.right > viewportWidth + 2));
    const tinyTargets = interactive.map((element) => {
      const rect = element.getBoundingClientRect();
      return { text: (element.innerText || element.getAttribute('aria-label') || '').trim().slice(0, 50), width: Math.round(rect.width), height: Math.round(rect.height) };
    }).filter((item) => item.width < 28 || item.height < 28).slice(0, 30);
    const scrollRegions = [...document.querySelectorAll('*')].filter(visible).filter((element) => {
      const style = getComputedStyle(element);
      return /(auto|scroll)/.test(style.overflowX) && element.scrollWidth > element.clientWidth + 8;
    }).map((element) => ({
      className: String(element.className || '').slice(0, 100),
      overflow: Math.round(element.scrollWidth - element.clientWidth),
    })).slice(0, 20);
    return {
      rootFound: Boolean(root),
      viewport: { width: viewportWidth, height: viewportHeight },
      documentOverflow: Math.max(0, document.documentElement.scrollWidth - viewportWidth),
      rootOverflow: root ? Math.max(0, root.scrollWidth - root.clientWidth) : null,
      outside,
      tinyTargets,
      scrollRegions,
      errors: [...document.querySelectorAll('.symbolika-costing-error, .symbolika-mail-error')].filter(visible).map((element) => element.innerText.trim()),
    };
  });
}

(async () => {
  fs.mkdirSync(resultsDir, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  let user;
  const report = { startedAt: new Date().toISOString(), baseUrl, screens: [], failures: [] };
  try {
    user = await createUser();
    for (const viewport of viewports) {
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
        colorScheme: 'dark',
        hasTouch: viewport.mobile,
        isMobile: viewport.mobile,
        deviceScaleFactor: viewport.mobile ? 2 : 1,
      });
      const page = await context.newPage();
      await login(page, user);
      for (const moduleName of modules) {
        process.stdout.write(`[responsive] ${viewport.key} / ${moduleName} ... `);
        const httpFailures = [];
        const listener = (response) => {
          if (response.url().startsWith(baseUrl) && response.status() >= 400 && !ignoredResponse(response)) {
            httpFailures.push({ status: response.status(), path: response.url().replace(baseUrl, '').slice(0, 180) });
          }
        };
        page.on('response', listener);
        if (inspectOrderList && moduleName === 'symbolika-orders') {
          await page.evaluate((userId) => localStorage.setItem(`symbolika-last-tab:${userId}:orders`, 'all_orders'), user.id);
        }
        await page.goto(`${baseUrl}/admin/${moduleName}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
        const selector = moduleName === 'symbolika-mail-module' ? '.symbolika-mail-page' : '.symbolika-costing-page';
        const loaded = await page.waitForSelector(selector, { timeout: 8_000 }).then(() => true).catch(() => false);
        await page.waitForTimeout(900);
        if (debugNavigation && viewport.mobile) {
          console.log(await page.evaluate(() => [...document.querySelectorAll('#dialog-outlet button')].map((button) => {
            const rect = button.getBoundingClientRect();
            return { text: button.innerText.trim(), title: button.title, aria: button.getAttribute('aria-label'), className: button.className, rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height } };
          })));
        }
        if (viewport.mobile) {
          const mobileNavigationClose = page.locator('#dialog-outlet .nav-toggle').first();
          if (await mobileNavigationClose.isVisible().catch(() => false)) {
            const navigation = page.locator('#dialog-outlet .symbolika-costing-side-nav').first();
            if (await navigation.isVisible().catch(() => false)) await mobileNavigationClose.click({ force: true });
          }
        }
        const navigationOverlays = page.locator('.overlay');
        for (let overlayIndex = (await navigationOverlays.count()) - 1; overlayIndex >= 0; overlayIndex -= 1) {
          const navigationOverlay = navigationOverlays.nth(overlayIndex);
          if (await navigationOverlay.isVisible().catch(() => false)) {
            await navigationOverlay.evaluate((element) => element.click());
            await navigationOverlay.waitFor({ state: 'hidden', timeout: 3_000 }).catch(() => {});
          }
        }
        await page.waitForTimeout(150);
        let mobileNavigation = null;
        const hasCostingNavigation = !['symbolika-mail-module', 'symbolika-profile-module'].includes(moduleName);
        if (inspectMobileNavigation && viewport.mobile && hasCostingNavigation) {
          await page.locator('.symbolika-costing-mobile-nav-toggle').click();
          const sideNavigation = page.locator('.symbolika-costing-mobile-nav-panel').first();
          const opened = await sideNavigation.isVisible().catch(() => false);
          if (opened) await sideNavigation.locator('.symbolika-costing-detail-close').click();
          mobileNavigation = { opened, closed: !(await sideNavigation.isVisible().catch(() => false)) };
        }
        let orderForm = null;
        if (inspectOrderForm && moduleName === 'symbolika-orders') {
          const createButton = page.locator('.symbolika-costing-smart-toolbar .symbolika-costing-button').first();
          if (await createButton.isVisible().catch(() => false)) {
            await createButton.click();
            await page.waitForSelector('.symbolika-costing-order-modal', { timeout: 5_000 });
            orderForm = await page.evaluate(() => {
              const visible = (element) => {
                const rect = element.getBoundingClientRect();
                const style = getComputedStyle(element);
                return rect.width > 1 && rect.height > 1 && style.display !== 'none' && style.visibility !== 'hidden';
              };
              const modal = document.querySelector('.symbolika-costing-order-modal');
              const visibleLabels = [...modal.querySelectorAll('.symbolika-costing-label')]
                .filter(visible)
                .map((label) => label.innerText.trim().split('\n')[0]);
              return {
                visibleLabels,
                hiddenOrderExtras: [...modal.querySelectorAll('.symbolika-mobile-order-extra')].filter((element) => !visible(element)).length,
                hiddenItemExtras: [...modal.querySelectorAll('.symbolika-mobile-item-extra')].filter((element) => !visible(element)).length,
                modalOverflow: Math.max(0, modal.scrollWidth - modal.clientWidth),
                overflowingChildren: [...modal.querySelectorAll('*')].map((element) => ({
                  tag: element.tagName.toLowerCase(),
                  className: typeof element.className === 'string' ? element.className.slice(0, 120) : '',
                  right: Math.round(element.getBoundingClientRect().right - modal.getBoundingClientRect().right),
                })).filter((element) => element.right > 2).slice(0, 12),
              };
            });
            await page.screenshot({ path: path.join(resultsDir, `${viewport.key}-${moduleName}-new-order.png`), fullPage: false });
            await page.locator('.symbolika-costing-detail-close').last().click();
          }
        }
        let orderDetail = null;
        if (inspectOrderDetail && moduleName === 'symbolika-orders') {
          const firstEntry = (await page.locator('.symbolika-costing-work-card').first().isVisible().catch(() => false))
            ? page.locator('.symbolika-costing-work-card').first()
            : page.locator('.symbolika-costing-table-order-list tbody tr').first();
          if (await firstEntry.isVisible().catch(() => false)) {
            await firstEntry.click();
            const detail = page.locator('aside.symbolika-costing-detail').first();
            const openedOnFirstClick = await detail.waitFor({ state: 'visible', timeout: 1_200 }).then(() => true).catch(() => false);
            if (!openedOnFirstClick) await firstEntry.click();
            await detail.waitFor({ state: 'visible', timeout: 5_000 });
            orderDetail = await detail.evaluate((element) => ({
              overflow: Math.max(0, element.scrollWidth - element.clientWidth),
              visibleFields: [...element.querySelectorAll('.symbolika-costing-detail-label')]
                .filter((field) => {
                  const rect = field.getBoundingClientRect();
                  const style = getComputedStyle(field);
                  return rect.width > 1 && rect.height > 1 && style.display !== 'none' && style.visibility !== 'hidden';
                })
                .map((field) => field.innerText.trim()),
            }));
            await page.screenshot({ path: path.join(resultsDir, `${viewport.key}-${moduleName}-detail.png`), fullPage: false });
            await detail.locator('.symbolika-costing-detail-close').click();
          }
        }
        const layout = await inspect(page);
        const failures = [];
        if (!loaded || !layout.rootFound) failures.push('working root not found');
        if (layout.documentOverflow > 2) failures.push(`document overflow ${layout.documentOverflow}px`);
        if (layout.outside.length) failures.push(`${layout.outside.length} controls outside viewport`);
        if (layout.errors.length) failures.push(`visible errors: ${layout.errors.join('; ')}`);
        if (httpFailures.length) failures.push(`HTTP errors: ${httpFailures.map((row) => `${row.status} ${row.path}`).join(', ')}`);
        if (inspectOrderForm && moduleName === 'symbolika-orders' && !orderForm) failures.push('new order form did not open');
        if (inspectOrderDetail && moduleName === 'symbolika-orders' && !orderDetail) failures.push('order detail did not open');
        if (orderDetail?.overflow > 2) failures.push(`order detail overflow ${orderDetail.overflow}px`);
        if (orderForm?.modalOverflow > 2) failures.push(`new order form overflow ${orderForm.modalOverflow}px`);
        if (viewport.mobile && orderForm && (!orderForm.hiddenOrderExtras || !orderForm.hiddenItemExtras)) failures.push('mobile order extras are not collapsed');
        if (inspectMobileNavigation && viewport.mobile && hasCostingNavigation && (!mobileNavigation?.opened || !mobileNavigation?.closed)) failures.push('mobile navigation did not open and close');
        const screen = { viewport: viewport.key, module: moduleName, layout, orderForm, orderDetail, mobileNavigation, httpFailures, failures };
        report.screens.push(screen);
        report.failures.push(...failures.map((failure) => `${viewport.key}/${moduleName}: ${failure}`));
        if (failures.length || captureAllScreens) await page.screenshot({ path: path.join(resultsDir, `${viewport.key}-${moduleName}.png`), fullPage: false });
        process.stdout.write(`${failures.length ? `FAIL (${failures.join(', ')})` : 'OK'}\n`);
        page.off('response', listener);
      }
      await context.close();
    }
  } finally {
    if (user?.id) await api(`/users/${user.id}`, { method: 'DELETE' }).catch(() => {});
    await browser.close();
  }
  report.finishedAt = new Date().toISOString();
  report.passed = report.failures.length === 0;
  fs.writeFileSync(path.join(resultsDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({ passed: report.passed, screens: report.screens.length, failures: report.failures }, null, 2));
  if (!report.passed) process.exitCode = 1;
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});

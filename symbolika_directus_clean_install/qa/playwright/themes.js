const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
let adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
const adminEmail = process.env.SYMBOLIKA_QA_ADMIN_EMAIL;
const adminPassword = process.env.SYMBOLIKA_QA_ADMIN_PASSWORD;
const resultsDir = path.resolve(__dirname, 'qa-results', 'themes');
const captureAllScreens = process.env.SYMBOLIKA_QA_CAPTURE_ALL !== '0';
const openForms = process.env.SYMBOLIKA_QA_OPEN_FORMS !== '0';
const showOrderCards = process.env.SYMBOLIKA_QA_ORDER_CARDS === '1';
const showOrderItems = process.env.SYMBOLIKA_QA_ORDER_ITEMS === '1';
const viewportWidth = Math.max(960, Number(process.env.SYMBOLIKA_QA_VIEWPORT_WIDTH || 1920));

if (!adminToken && !(adminEmail && adminPassword)) {
  throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN or temporary admin credentials. Real credentials must never be committed.');
}

const allThemes = ['graphite', 'espresso', 'pearl', 'frost'];
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

function selectedValues(environmentName, available) {
  const requested = String(process.env[environmentName] || '').split(',').map((value) => value.trim()).filter(Boolean);
  if (!requested.length) return available;
  const selected = available.filter((value) => requested.includes(value));
  if (!selected.length) throw new Error(`${environmentName} does not match any configured values.`);
  return selected;
}

const themes = selectedValues('SYMBOLIKA_QA_THEMES', allThemes);
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

async function ensureAdminToken() {
  if (adminToken) return;
  const response = await fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: adminEmail, password: adminPassword }),
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload?.data?.access_token) throw new Error(`Admin login failed: ${response.status}`);
  adminToken = payload.data.access_token;
}

async function createUser() {
  const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
  if (!roles?.[0]?.id) throw new Error('Administrator role not found.');
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = {
    email: `qa-themes-${suffix}@example.com`,
    password: `Qa!${crypto.randomBytes(18).toString('hex')}`,
  };
  const user = await api('/users', {
    method: 'POST',
    body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Themes' }),
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

async function applyTheme(page, userId, theme) {
  await api(`/users/${userId}`, { method: 'PATCH', body: JSON.stringify({ symbolika_theme: theme }) });
  await page.evaluate((selectedTheme) => {
    localStorage.setItem('symbolika-theme', selectedTheme);
    document.documentElement.dataset.symbolikaTheme = selectedTheme;
    document.body.dataset.symbolikaTheme = selectedTheme;
    window.dispatchEvent(new CustomEvent('symbolika-theme-change', { detail: { theme: selectedTheme } }));
  }, theme);
}

async function openSafeForm(page, moduleName) {
  const labels = {
    'symbolika-orders': /Новый заказ/i,
    'symbolika-procurement': /Создать заявку|Добавить/i,
    'symbolika-mail-module': /Написать/i,
  };
  const label = labels[moduleName];
  if (!label) return false;
  const button = page.locator('button').filter({ hasText: label }).last();
  if (!await button.isVisible().catch(() => false)) return false;
  await button.click();
  await page.waitForTimeout(350);
  return true;
}

async function inspect(page, expectedTheme) {
  return page.evaluate(({ expectedTheme }) => {
    const light = ['pearl', 'frost'].includes(expectedTheme);
    const visible = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 2 && rect.height > 2 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > .04;
    };
    const rgba = (value) => {
      const functionMatch = String(value).match(/rgba?\(([^)]+)\)/i);
      if (!functionMatch) return null;
      const channels = functionMatch[1].match(/[\d.]+%?/g);
      if (!channels || channels.length < 3) return null;
      const alpha = channels[3] === undefined ? 1 : (channels[3].endsWith('%') ? +channels[3].slice(0, -1) / 100 : +channels[3]);
      return { r: +channels[0].replace('%', ''), g: +channels[1].replace('%', ''), b: +channels[2].replace('%', ''), a: alpha };
    };
    const blend = (foreground, background) => ({
      r: foreground.r * foreground.a + background.r * (1 - foreground.a),
      g: foreground.g * foreground.a + background.g * (1 - foreground.a),
      b: foreground.b * foreground.a + background.b * (1 - foreground.a),
      a: 1,
    });
    const effectiveBackground = (element) => {
      if (!element) return light ? { r: 255, g: 255, b: 255, a: 1 } : { r: 0, g: 0, b: 0, a: 1 };
      const style = getComputedStyle(element);
      const parentBackground = effectiveBackground(element.parentElement);
      const gradientColor = rgba(style.backgroundImage);
      if (gradientColor && gradientColor.a > .01) return blend(gradientColor, parentBackground);
      const parsed = rgba(style.backgroundColor);
      return parsed && parsed.a > .01 ? blend(parsed, parentBackground) : parentBackground;
    };
    const luminance = ({ r, g, b }) => {
      const values = [r, g, b].map((channel) => {
        const value = channel / 255;
        return value <= .03928 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
      });
      return .2126 * values[0] + .7152 * values[1] + .0722 * values[2];
    };
    const contrast = (foreground, background) => {
      const a = luminance(foreground);
      const b = luminance(background);
      return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
    };
    const describe = (element) => ({
      tag: element.tagName.toLowerCase(),
      className: String(element.className || '').split(/\s+/).slice(0, 3).join('.'),
      text: String(element.innerText || element.value || element.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 60),
    });
    const root = document.querySelector('.symbolika-costing-page, .symbolika-mail-page');
    const nav = [...document.querySelectorAll('.symbolika-costing-side-nav, .symbolika-mail-side-nav')].find(visible) || null;
    const rootLum = root ? luminance(effectiveBackground(root)) : null;
    const navLum = nav ? luminance(effectiveBackground(nav)) : null;
    const controls = [...document.querySelectorAll('input, textarea, select, .v-field, [role="combobox"]')].filter(visible);
    const controlAudit = controls.slice(0, 120).map((element) => {
      const style = getComputedStyle(element);
      const foreground = rgba(style.color);
      const background = effectiveBackground(element);
      return {
        ...describe(element),
        backgroundLuminance: +luminance(background).toFixed(3),
        contrast: foreground ? +contrast(foreground, background).toFixed(2) : null,
        colorScheme: style.colorScheme,
      };
    });
    const textSelectors = [
      '.symbolika-costing-table th', '.symbolika-costing-table td', '.symbolika-costing-card-title',
      '.symbolika-costing-card-value', '.symbolika-costing-side-item', '.symbolika-mail-thread',
      '.symbolika-mail-message', '.symbolika-mail-side-folder', 'label', '.field-name', '.v-list-item',
      '.symbolika-costing-work-card-head > strong', '.symbolika-costing-work-card-subtitle',
      '.symbolika-costing-work-card-meta > span', '.symbolika-costing-date',
      '.symbolika-costing-amount-badge', '.symbolika-costing-issue-button',
    ];
    const textNodes = [...document.querySelectorAll(textSelectors.join(','))].filter(visible).slice(0, 220);
    const lowContrast = textNodes.map((element) => {
      const foreground = rgba(getComputedStyle(element).color);
      const background = effectiveBackground(element);
      const ratio = foreground ? contrast(foreground, background) : 21;
      return { ...describe(element), ratio: +ratio.toFixed(2) };
    }).filter((row) => row.ratio < 2.8).slice(0, 30);
    const dateControls = controls.filter((element) => ['date', 'datetime-local', 'month', 'week'].includes(element.type)).map((element) => ({
      ...describe(element),
      colorScheme: getComputedStyle(element).colorScheme,
      accentColor: getComputedStyle(element).accentColor,
    }));
    const itemCards = [...document.querySelectorAll('.symbolika-costing-work-card.is-kind-item')].filter(visible).map((card) => {
      const title = card.querySelector('.symbolika-costing-work-card-head > strong');
      const status = card.querySelector('.symbolika-costing-card-status');
      const titleStyle = title ? getComputedStyle(title) : null;
      const titleRect = title?.getBoundingClientRect();
      const statusRect = status?.getBoundingClientRect();
      return {
        title: String(title?.textContent || '').trim(),
        titleWidth: titleRect ? +titleRect.width.toFixed(1) : null,
        titleHeight: titleRect ? +titleRect.height.toFixed(1) : null,
        titleWhiteSpace: titleStyle?.whiteSpace || '',
        statusWidth: statusRect ? +statusRect.width.toFixed(1) : null,
      };
    });
    return {
      actualTheme: document.documentElement.dataset.symbolikaTheme || document.body.dataset.symbolikaTheme || '',
      rootFound: Boolean(root),
      debug: root ? {
        htmlTheme: document.documentElement.dataset.symbolikaTheme || '',
        bodyTheme: document.body.dataset.symbolikaTheme || '',
        bodyBackground: getComputedStyle(document.body).backgroundColor,
        bodySymbolikaBackground: getComputedStyle(document.body).getPropertyValue('--symbolika-bg').trim(),
        rootBackground: getComputedStyle(root).backgroundColor,
        rootSymbolikaBackground: getComputedStyle(root).getPropertyValue('--symbolika-bg').trim(),
        navigationClass: nav ? String(nav.className || '') : '',
        navigationBackground: nav ? getComputedStyle(nav).backgroundColor : '',
        navigationImage: nav ? getComputedStyle(nav).backgroundImage : '',
        lightSelectorMatches: document.documentElement.matches(':is([data-symbolika-theme="pearl"], [data-symbolika-theme="frost"])'),
      } : null,
      rootLuminance: rootLum === null ? null : +rootLum.toFixed(3),
      navigationLuminance: navLum === null ? null : +navLum.toFixed(3),
      controls: controlAudit,
      dateControls,
      itemCards,
      lowContrast,
      visibleErrors: [...document.querySelectorAll('.symbolika-costing-error, .symbolika-mail-error')].filter(visible).map((element) => element.innerText.trim()),
      documentOverflow: Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth),
    };
  }, { expectedTheme });
}

(async () => {
  fs.mkdirSync(resultsDir, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  let user;
  const report = { startedAt: new Date().toISOString(), baseUrl, screens: [], failures: [], warnings: [] };
  try {
    await ensureAdminToken();
    user = await createUser();
    const context = await browser.newContext({ viewport: { width: viewportWidth, height: 1080 }, colorScheme: 'dark' });
    const page = await context.newPage();
    await login(page, user);
    for (const theme of themes) {
      await applyTheme(page, user.id, theme);
      const light = ['pearl', 'frost'].includes(theme);
      for (const moduleName of modules) {
        process.stdout.write(`[themes] ${theme} / ${moduleName} ... `);
        const httpFailures = [];
        const listener = (response) => {
          if (response.url().startsWith(baseUrl) && response.status() >= 400 && !ignoredResponse(response)) {
            httpFailures.push({ status: response.status(), path: response.url().replace(baseUrl, '').slice(0, 180) });
          }
        };
        page.on('response', listener);
        await page.goto(`${baseUrl}/admin/${moduleName}`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
        await page.waitForSelector(moduleName === 'symbolika-mail-module' ? '.symbolika-mail-page' : '.symbolika-costing-page', { timeout: 10_000 }).catch(() => {});
        await page.waitForTimeout(700);
        if (showOrderCards && moduleName === 'symbolika-orders') {
          await page.locator('.symbolika-costing-side-item').filter({ hasText: 'Все заказы' }).click();
          await page.locator('.symbolika-costing-view-button[title="Карточки"]').click();
          if (showOrderItems) await page.locator('.symbolika-costing-filter-chip').filter({ hasText: 'По позициям' }).click();
          await page.waitForTimeout(700);
        }
        const formOpened = openForms ? await openSafeForm(page, moduleName).catch(() => false) : false;
        const audit = await inspect(page, theme);
        const failures = [];
        const warnings = [];
        if (!audit.rootFound) failures.push('working root not found');
        if (audit.actualTheme !== theme) failures.push(`theme mismatch: ${audit.actualTheme || 'none'}`);
        if (light && audit.rootLuminance !== null && audit.rootLuminance < .55) failures.push(`dark page in light theme (${audit.rootLuminance})`);
        if (light && audit.navigationLuminance !== null && audit.navigationLuminance < .45) failures.push(`dark navigation in light theme (${audit.navigationLuminance})`);
        if (!light && audit.rootLuminance !== null && audit.rootLuminance > .35) failures.push(`light page in dark theme (${audit.rootLuminance})`);
        const wrongControls = audit.controls.filter((control) => light
          ? control.backgroundLuminance < .45 || control.colorScheme === 'dark'
          : control.backgroundLuminance > .55 || control.colorScheme === 'light');
        if (wrongControls.length) failures.push(`${wrongControls.length} controls use the wrong color scheme`);
        if (audit.lowContrast.length) warnings.push(`${audit.lowContrast.length} low-contrast text samples`);
        if (audit.visibleErrors.length) failures.push(`visible errors: ${audit.visibleErrors.join('; ')}`);
        if (audit.documentOverflow > 2) failures.push(`document overflow ${audit.documentOverflow}px`);
        const malformedItemCards = audit.itemCards.filter((card) => card.titleWhiteSpace !== 'nowrap' || (card.statusWidth !== null && card.statusWidth > 181));
        if (showOrderItems && !audit.itemCards.length) failures.push('item cards not found');
        if (malformedItemCards.length) failures.push(`${malformedItemCards.length} item cards wrap titles or have oversized statuses`);
        if (httpFailures.length) failures.push(`HTTP errors: ${httpFailures.map((row) => `${row.status} ${row.path}`).join(', ')}`);
        const screen = { theme, module: moduleName, formOpened, audit, wrongControls: wrongControls.slice(0, 30), httpFailures, failures, warnings };
        report.screens.push(screen);
        report.failures.push(...failures.map((failure) => `${theme}/${moduleName}: ${failure}`));
        report.warnings.push(...warnings.map((warning) => `${theme}/${moduleName}: ${warning}`));
        if (captureAllScreens || failures.length) await page.screenshot({ path: path.join(resultsDir, `${theme}-${moduleName}.png`), fullPage: false });
        if (formOpened) await page.keyboard.press('Escape').catch(() => {});
        page.off('response', listener);
        process.stdout.write(`${failures.length ? `FAIL (${failures.join(', ')})` : 'OK'}${warnings.length ? ` WARN (${warnings.join(', ')})` : ''}\n`);
      }
    }
    await context.close();
  } finally {
    if (user?.id) await api(`/users/${user.id}`, { method: 'DELETE' }).catch(() => {});
    await browser.close();
  }
  report.finishedAt = new Date().toISOString();
  report.passed = report.failures.length === 0;
  fs.writeFileSync(path.join(resultsDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({ passed: report.passed, screens: report.screens.length, failures: report.failures, warnings: report.warnings }, null, 2));
  if (!report.passed) process.exitCode = 1;
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});

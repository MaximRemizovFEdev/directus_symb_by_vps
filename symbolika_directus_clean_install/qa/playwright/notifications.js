const crypto = require('node:crypto');
const { chromium } = require('playwright');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

async function api(endpoint, options = {}) {
  const requestToken = Object.prototype.hasOwnProperty.call(options, 'token') ? options.token : adminToken;
  const { token: _token, ...requestOptions } = options;
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...requestOptions,
    headers: {
      ...(requestToken ? { authorization: `Bearer ${requestToken}` } : {}),
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || ''}`);
  return payload?.data ?? payload;
}

async function login(page, credentials) {
  await page.goto(`${baseUrl}/admin/login`, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.locator('input[type="email"]').fill(credentials.email);
  await page.locator('input[type="password"]').fill(credentials.password);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.endsWith('/login'), { timeout: 30_000 });
}

async function inspectViewport(browser, credentials, viewport) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const failures = [];
  page.on('pageerror', (error) => failures.push(`page: ${error.message}`));
  page.on('response', (response) => {
    if (response.status() >= 500) failures.push(`${response.status()} ${response.url()}`);
  });
  await login(page, credentials);
  if (viewport.width > 760) {
    await page.goto(`${baseUrl}/admin/symbolika-orders`, { waitUntil: 'networkidle', timeout: 60_000 });
    const notificationButton = page.locator('.module-bar button:has([data-icon="notifications"])');
    await notificationButton.waitFor({ state: 'attached', timeout: 30_000 });
    if (await notificationButton.getAttribute('aria-label') !== 'Центр уведомлений') failures.push('native notification button was not converted to notification center shortcut');
    await notificationButton.evaluate((button) => button.click());
    await page.waitForURL((url) => url.pathname === '/admin/symbolika-notifications', { timeout: 30_000 });
  } else {
    await page.goto(`${baseUrl}/admin/symbolika-notifications`, { waitUntil: 'networkidle', timeout: 60_000 });
  }
  await page.waitForLoadState('networkidle');
  const root = page.locator('.symbolika-notification-page:visible').last();
  await root.waitFor({ state: 'visible', timeout: 30_000 });
  const overlays = page.locator('#dialog-outlet .overlay:visible');
  for (let index = (await overlays.count()) - 1; index >= 0; index -= 1) {
    await overlays.nth(index).evaluate((element) => element.click()).catch(() => {});
  }
  await page.waitForTimeout(250);
  await page.getByText('QA: центр уведомлений', { exact: true }).waitFor({ state: 'visible' });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 2);
  if (overflow) failures.push(`horizontal overflow at ${viewport.width}px`);
  await root.locator('.symbolika-notification-view-tabs button').nth(1).evaluate((button) => button.click());
  await page.waitForTimeout(500);
  const channelCount = await root.locator('.symbolika-notification-channel').count();
  if (channelCount !== 4) {
    const tabClasses = await root.locator('.symbolika-notification-view-tabs button').evaluateAll((buttons) => buttons.map((button) => ({ text: button.textContent.trim(), className: button.className })));
    failures.push(`expected 4 channels, got ${channelCount}; tabs=${JSON.stringify(tabClasses)}`);
  }
  if (viewport.width <= 760 && channelCount === 4) {
    const columns = await root.locator('.symbolika-notification-channel-grid').evaluate((element) => getComputedStyle(element).gridTemplateColumns);
    if (columns.trim().split(/\s+/).length !== 1) failures.push(`mobile channel grid is not single-column: ${columns}`);
  }
  const topicCount = await root.locator('.symbolika-notification-topic').count();
  if (topicCount !== 8) failures.push(`expected 8 notification topics, got ${topicCount}`);
  if (viewport.width <= 760 && topicCount === 8) {
    const columns = await root.locator('.symbolika-notification-topic-grid').evaluate((element) => getComputedStyle(element).gridTemplateColumns);
    if (columns.trim().split(/\s+/).length !== 1) failures.push(`mobile topic grid is not single-column: ${columns}`);
  }
  if (viewport.width > 760 && topicCount === 8) {
    const mailToggle = root.locator('.symbolika-notification-topic').nth(6).locator('input[type="checkbox"]');
    if (!await mailToggle.isChecked()) await mailToggle.evaluate((input) => input.click());
    await root.getByRole('button', { name: 'Сохранить настройки' }).click();
    await root.getByText('Настройки уведомлений сохранены', { exact: true }).waitFor({ state: 'visible', timeout: 10_000 });
  }
  await context.close();
  return failures;
}

async function run() {
  const suffix = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const credentials = { email: `qa-notifications-${suffix}@example.com`, password: `Qa!${crypto.randomBytes(18).toString('hex')}` };
  let userId;
  let employeeId;
  let notificationId;
  const taskIds = [];
  const taskNotificationIds = [];
  const browser = await chromium.launch({ headless: true });
  try {
    const roles = await api('/roles?filter[name][_eq]=Administrator&fields=id&limit=1');
    const user = await api('/users', {
      method: 'POST',
      body: JSON.stringify({ ...credentials, role: roles[0].id, status: 'active', first_name: 'QA', last_name: 'Notifications' }),
    });
    userId = user.id;
    const employee = await api('/items/employees', {
      method: 'POST',
      body: JSON.stringify({ full_name: `QA Notifications ${suffix}`, is_active: true, directus_user: userId }),
    });
    employeeId = employee.id;
    await api(`/users/${userId}`, { method: 'PATCH', body: JSON.stringify({ employee: employeeId }) });
    const session = await api('/auth/login', {
      token: null,
      method: 'POST',
      body: JSON.stringify(credentials),
    });
    await api('/symbolika-profile/notifications/settings', {
      token: session.access_token,
      method: 'PATCH',
      body: JSON.stringify({ topics: { new_tasks: false } }),
    });
    const mutedTask = await api('/items/symbolika_tasks', {
      method: 'POST',
      body: JSON.stringify({ title: `QA muted task ${suffix}`, assigned_to: employeeId }),
    });
    taskIds.push(mutedTask.id);
    const mutedNotifications = await api(`/notifications?filter[recipient][_eq]=${userId}&filter[collection][_eq]=symbolika_tasks&filter[item][_eq]=${mutedTask.id}&fields=id&limit=-1`);
    if (mutedNotifications.length) throw new Error('disabled new_tasks topic still created a notification');
    await api('/symbolika-profile/notifications/settings', {
      token: session.access_token,
      method: 'PATCH',
      body: JSON.stringify({ topics: { new_tasks: true } }),
    });
    const enabledTask = await api('/items/symbolika_tasks', {
      method: 'POST',
      body: JSON.stringify({ title: `QA enabled task ${suffix}`, assigned_to: employeeId }),
    });
    taskIds.push(enabledTask.id);
    const enabledNotifications = await api(`/notifications?filter[recipient][_eq]=${userId}&filter[collection][_eq]=symbolika_tasks&filter[item][_eq]=${enabledTask.id}&fields=id&limit=-1`);
    if (enabledNotifications.length !== 1) throw new Error(`enabled new_tasks topic created ${enabledNotifications.length} notifications`);
    taskNotificationIds.push(...enabledNotifications.map((item) => item.id));
    const notification = await api('/notifications', {
      method: 'POST',
      body: JSON.stringify({ status: 'inbox', recipient: userId, subject: 'QA: центр уведомлений', message: 'Проверка адаптивной ленты', collection: 'orders', item: '999999' }),
    });
    notificationId = notification.id;
    const failures = [
      ...await inspectViewport(browser, credentials, { width: 1440, height: 900 }),
      ...await inspectViewport(browser, credentials, { width: 390, height: 844 }),
    ];
    if (failures.length) throw new Error(failures.join('\n'));
    console.log('PASS notification preferences, desktop and mobile');
  } finally {
    await browser.close();
    if (notificationId) await api(`/notifications/${notificationId}`, { method: 'DELETE' }).catch(() => {});
    for (const id of taskNotificationIds) await api(`/notifications/${id}`, { method: 'DELETE' }).catch(() => {});
    for (const id of taskIds.reverse()) await api(`/items/symbolika_tasks/${id}`, { method: 'DELETE' }).catch(() => {});
    if (employeeId) await api(`/items/employees/${employeeId}`, { method: 'DELETE' }).catch(() => {});
    if (userId) await api(`/users/${userId}`, { method: 'DELETE' }).catch(() => {});
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

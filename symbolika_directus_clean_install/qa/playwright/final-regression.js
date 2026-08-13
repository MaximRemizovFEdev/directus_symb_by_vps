const crypto = require('node:crypto');

const baseUrl = (process.env.SYMBOLIKA_QA_BASE_URL || 'http://localhost:8057').replace(/\/$/, '');
const adminToken = process.env.SYMBOLIKA_QA_ADMIN_TOKEN;
if (!adminToken) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN. Real tokens must never be committed.');

const suffix = `final-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
const password = `Qa!${crypto.randomBytes(18).toString('hex')}`;
const created = { users: [], employees: [], customers: [], companies: [], orders: [], items: [], payments: [], allocations: [], inventory: [], procurement: [], batches: [], tasks: [], comments: [], checklist: [] };
const checks = [];

function record(name, ok, detail = '') {
  checks.push({ name, ok: !!ok, detail: detail || '' });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`);
}

async function request(endpoint, { token = adminToken, expected, ...options } = {}) {
  const response = await fetch(`${baseUrl}${endpoint}`, {
    ...options,
    headers: {
      authorization: token ? `Bearer ${token}` : undefined,
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (expected && expected.includes(response.status)) return { status: response.status, data: payload?.data ?? payload };
  if (!response.ok) {
    throw new Error(`${options.method || 'GET'} ${endpoint}: ${response.status} ${payload?.errors?.[0]?.message || payload?.message || ''}`.trim());
  }
  return payload?.data ?? payload;
}

async function login(email) {
  const auth = await request('/auth/login', {
    token: null,
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  return auth.access_token;
}

async function waitFor(check, timeout = 12_000, interval = 300) {
  const until = Date.now() + timeout;
  let value;
  while (Date.now() < until) {
    value = await check();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
  return value;
}

async function list(collection, params = '', token = adminToken) {
  return request(`/items/${collection}${params ? `?${params}` : ''}`, { token });
}

async function createUser(roleName, positionId = null, key = 'user') {
  const roles = await request(`/roles?filter[name][_eq]=${encodeURIComponent(roleName)}&fields=id,name&limit=10`);
  const role = roles.find((row) => row.id !== '8d096ec4-c189-44a5-ae91-28e7a3c12857') || roles[0];
  if (!role) throw new Error(`Role not found: ${roleName}`);
  const email = `qa-${suffix}-${key}@example.com`;
  const user = await request('/users', {
    method: 'POST',
    body: JSON.stringify({ email, password, role: role.id, status: 'active', first_name: 'QA', last_name: roleName }),
  });
  created.users.push(user.id);
  const employee = await request('/items/employees', {
    method: 'POST',
    body: JSON.stringify({ full_name: `QA ${roleName} ${suffix}`, position: positionId, is_active: true, directus_user: user.id }),
  });
  created.employees.push(employee.id);
  await request(`/users/${user.id}`, { method: 'PATCH', body: JSON.stringify({ employee: employee.id }) });
  return { ...user, email, employee: employee.id, token: await login(email) };
}

async function cleanupCollection(collection, ids) {
  for (const id of [...ids].reverse()) {
    await request(`/items/${collection}/${id}`, { method: 'DELETE' }).catch(() => {});
  }
}

async function cleanup() {
  await cleanupCollection('symbolika_task_comments', created.comments);
  await cleanupCollection('symbolika_task_checklist', created.checklist);
  await cleanupCollection('symbolika_tasks', created.tasks);
  await cleanupCollection('procurement_requests', created.procurement);
  await cleanupCollection('procurement_batches', created.batches);
  await cleanupCollection('inventory_items', created.inventory);
  await cleanupCollection('payment_allocations', created.allocations);
  await cleanupCollection('order_payments', created.payments);
  await cleanupCollection('orders_items', created.items);
  await cleanupCollection('orders', created.orders);
  await cleanupCollection('customers', created.customers);
  await cleanupCollection('customer_companies', created.companies);
  await cleanupCollection('employees', created.employees);
  for (const id of [...created.users].reverse()) await request(`/users/${id}`, { method: 'DELETE' }).catch(() => {});
}

async function run() {
  const positions = await list('employee_positions', 'fields=id,name&limit=-1');
  const position = (name) => positions.find((row) => row.name === name)?.id || null;
  const users = {};
  users.managerA = await createUser('Менеджер', position('Менеджер'), 'manager-a');
  users.managerB = await createUser('Менеджер', position('Менеджер'), 'manager-b');
  users.office = await createUser('Менеджер', position('Офис-менеджер'), 'office');
  users.production = await createUser('Производство', position('Производство'), 'production');
  users.screen = await createUser('Шелкография', null, 'screen');
  users.designer = await createUser('Дизайнер', null, 'designer');
  users.management = await createUser('Управляющий', position('Управляющий'), 'management');
  record('Создание и авторизация семи ролевых пользователей', Object.values(users).every((user) => user.token));

  const company = await request('/items/customer_companies', {
    token: users.managerA.token,
    method: 'POST',
    body: JSON.stringify({ name: `QA Компания ${suffix}`, manager: users.managerA.employee }),
  });
  created.companies.push(company.id);
  const customer = await request('/items/customers', {
    token: users.managerA.token,
    method: 'POST',
    body: JSON.stringify({ name: `QA Клиент ${suffix}`, company: company.id, manager: users.managerA.employee }),
  });
  created.customers.push(customer.id);
  const today = new Date().toISOString().slice(0, 10);
  const deadline = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
  const order = await request('/items/orders', {
    token: users.managerA.token,
    method: 'POST',
    body: JSON.stringify({
      date: today, deadline, customer: customer.id, customer_company: company.id, payment_type: 1,
      manager_employee: users.managerA.employee, order_status: 1, office_status: 'not_in_office', shipping_method: 'office_pickup',
    }),
  });
  created.orders.push(order.id);
  record('Менеджер создаёт собственных клиента, компанию и заказ', !!order.id);

  const otherRead = await request(`/items/orders/${order.id}?fields=id`, { token: users.managerB.token, expected: [403] });
  record('Изоляция заказов между менеджерами', otherRead.status === 403, `HTTP ${otherRead.status}`);

  const minimalOrder = await request('/items/orders', {
    token: users.managerA.token, method: 'POST',
    body: JSON.stringify({ date: today, customer: customer.id, customer_company: company.id, manager_employee: users.managerA.employee, order_status: 1, office_status: 'not_in_office', shipping_method: 'office_pickup' }),
  });
  created.orders.push(minimalOrder.id);
  const minimalItem = await request('/items/orders_items', {
    token: users.managerA.token, method: 'POST',
    body: JSON.stringify({ order: minimalOrder.id, product_name: `QA Минимальный ${suffix}`, quantity: 2, price_per_unit: 0, technical_task_text: 'QA ТЗ', url: 'https://example.test/minimal.pdf', item_status: 'new', office_status: 'not_in_office', blank_source: 'none' }),
  });
  created.items.push(minimalItem.id);
  const minimalLaunch = await request(`/items/orders/${minimalOrder.id}`, {
    token: users.managerA.token, method: 'PATCH', body: JSON.stringify({ order_status: 3 }), expected: [200, 500],
  });
  record('Запуск допускает только название, количество, ТЗ и макет; цена может быть позже', minimalLaunch.status === 200, `HTTP ${minimalLaunch.status}`);

  const categories = await list('product_categories', 'fields=id,name&limit=-1');
  const category = categories.find((row) => row.name === 'Полиграфия') || categories[0];
  const subcategories = await list('product_subcategories', `fields=id,name,category&filter[category][_eq]=${category.id}&limit=-1`);
  const subcategory = subcategories.find((row) => row.name === 'Блокноты') || subcategories[0];
  const item = await request('/items/orders_items', {
    token: users.managerA.token,
    method: 'POST',
    body: JSON.stringify({
      order: order.id, product_name: `QA Блокноты ${suffix}`, quantity: 7, price_per_unit: 125,
      product_category: category.id, product_subcategory: subcategory?.id || null,
      technical_task_text: 'QA техническое задание', url: 'https://example.test/layout.pdf', deadline,
      item_status: 'new', office_status: 'not_in_office', blank_source: 'none', shipping_method: 'office_pickup',
    }),
  });
  created.items.push(item.id);
  record('Создание полностью заполненной позиции', !!item.id);

  await request(`/items/orders/${order.id}`, { token: users.managerA.token, method: 'PATCH', body: JSON.stringify({ order_status: 3 }) });
  const started = await waitFor(async () => {
    const rows = await list('orders_items', `fields=id,item_status,production_status,contractor_1,contractor_2&filter[id][_eq]=${item.id}`);
    return rows[0]?.item_status === 'in_work' ? rows[0] : null;
  });
  record('Кнопка/статус «В работу» синхронизирует позицию', !!started, JSON.stringify(started));

  const freshOrder = await request(`/items/orders/${order.id}?fields=id,order_sum,paid_amount,payment_due,manager_employee,commission_manager_employee`);
  record('Сумма заказа пересчитана из позиций', Number(freshOrder.order_sum) === 875, `order_sum=${freshOrder.order_sum}`);
  record('Менеджер и получатель процента закреплены', Number(freshOrder.manager_employee) === users.managerA.employee && Number(freshOrder.commission_manager_employee) === users.managerA.employee);

  const payment = await request('/items/order_payments', {
    token: users.managerA.token, method: 'POST',
    body: JSON.stringify({ order: order.id, customer: customer.id, customer_company: company.id, amount: 300, payment_date: today, payment_type: 1, payment_direction: 'incoming', allocation_mode: 'to_order', comment: `QA ${suffix}` }),
  });
  created.payments.push(payment.id);
  const allocation = await waitFor(async () => {
    const rows = await list('payment_allocations', `fields=id,amount,order,payment&filter[payment][_eq]=${payment.id}&limit=-1`);
    return rows[0] || null;
  });
  if (allocation) created.allocations.push(allocation.id);
  const paidOrder = await request(`/items/orders/${order.id}?fields=paid_amount,payment_due`);
  record('Частичная оплата компании распределяется в заказ', !!allocation && Number(allocation.amount) === 300 && Number(paidOrder.paid_amount) === 300 && Number(paidOrder.payment_due) === 575, JSON.stringify({ allocation, paidOrder }));

  const productionRows = await list('production_work', `fields=id,product_name&filter[id][_eq]=${item.id}&limit=-1`, users.production.token).catch(() => []);
  const screenRows = await list('screen_printing_work', `fields=id,product_name&filter[id][_eq]=${item.id}&limit=-1`, users.screen.token).catch(() => []);
  record('Маршрутизация позиции видна хотя бы назначенному внутреннему участку', productionRows.length + screenRows.length > 0, `production=${productionRows.length}, screen=${screenRows.length}`);

  const routedCollection = productionRows.length ? 'production_work' : 'screen_printing_work';
  const routedUser = productionRows.length ? users.production : users.screen;
  await request(`/items/${routedCollection}/${item.id}`, {
    token: routedUser.token, method: 'PATCH', body: JSON.stringify({ production_status: 5 }),
  });
  const ready = await waitFor(async () => {
    const row = await request(`/items/orders_items/${item.id}?fields=id,item_status,production_status`);
    return row.item_status === 'ready' && Number(row.production_status) === 5 ? row : null;
  });
  record('Готовность участка синхронизируется с позицией и заказом', !!ready, JSON.stringify(ready));

  await request(`/items/office_issue/${order.id}`, { token: users.office.token, method: 'PATCH', body: JSON.stringify({ office_status: 'in_office' }) });
  const inOffice = await waitFor(async () => {
    const row = await request(`/items/orders_items/${item.id}?fields=item_status,production_status,office_status`);
    return row.office_status === 'in_office' && row.item_status === 'ready' && Number(row.production_status) === 5 ? row : null;
  });
  record('Статус «В офисе» принудительно фиксирует готовность производства', !!inOffice, JSON.stringify(inOffice));
  await request(`/items/office_issue/${order.id}`, { token: users.office.token, method: 'PATCH', body: JSON.stringify({ office_status: 'issued' }) });
  const issued = await waitFor(async () => {
    const [orderRow, itemRow] = await Promise.all([
      request(`/items/orders/${order.id}?fields=order_status,office_status`),
      request(`/items/orders_items/${item.id}?fields=item_status,office_status`),
    ]);
    return itemRow.item_status === 'delivered' && itemRow.office_status === 'issued' && Number(orderRow.order_status) === 5 && orderRow.office_status === 'issued'
      ? { orderRow, itemRow } : null;
  });
  record('Выдача позиции взаимно переводит весь заказ в «Доставлен»', !!issued, JSON.stringify(issued));

  const designOrder = await request('/items/orders', {
    token: users.managerA.token, method: 'POST',
    body: JSON.stringify({ date: new Date().toISOString().slice(0, 10), customer: customer.id, customer_company: company.id, manager_employee: users.managerA.employee, order_status: 1, office_status: 'not_in_office' }),
  });
  created.orders.push(designOrder.id);
  const designItem = await request('/items/orders_items', {
    token: users.managerA.token, method: 'POST',
    body: JSON.stringify({ order: designOrder.id, product_name: `QA Дизайн ${suffix}`, quantity: 1, technical_task_text: 'Нарисовать макет', needs_designer_help: true, item_status: 'new', office_status: 'not_in_office', blank_source: 'none' }),
  });
  created.items.push(designItem.id);
  let designTask = await waitFor(async () => {
    const rows = await list('symbolika_tasks', `fields=id,status,assigned_to,related_order_item,task_type&filter[related_order_item][_eq]=${designItem.id}&limit=-1`);
    return rows[0] || null;
  });
  if (designTask) created.tasks.push(designTask.id);
  record('Флаг помощи дизайнера автоматически создаёт связанную задачу', !!designTask, JSON.stringify(designTask));
  if (!designTask) {
    designTask = await request('/items/symbolika_tasks', {
      method: 'POST', body: JSON.stringify({ title: `QA дизайн ${suffix}`, status: 'new', priority: 'normal', assigned_to: users.designer.employee, created_by_employee: users.managerA.employee, related_order: designOrder.id, related_order_item: designItem.id, task_type: 'design' }),
    });
    created.tasks.push(designTask.id);
  }
  await request(`/items/symbolika_tasks/${designTask.id}`, {
    method: 'PATCH', body: JSON.stringify({ assigned_to: users.designer.employee }),
  });
  const designerCanRead = await request(`/items/symbolika_tasks/${designTask.id}?fields=id,title,status,result_url`, { token: users.designer.token });
  record('Дизайнер видит назначенную задачу', Number(designerCanRead.id) === Number(designTask.id));
  const taskCommentResult = await request('/items/symbolika_task_comments', {
    token: users.designer.token, method: 'POST', body: JSON.stringify({ task: designTask.id, employee: users.designer.employee, comment: `QA комментарий ${suffix}` }), expected: [200, 403],
  });
  if (taskCommentResult.status === 200 && taskCommentResult.data?.id) created.comments.push(taskCommentResult.data.id);
  const checklistResult = await request('/items/symbolika_task_checklist', {
    token: users.designer.token, method: 'POST', body: JSON.stringify({ task: designTask.id, title: `QA пункт ${suffix}`, is_done: false, sort: 1 }), expected: [200, 403],
  });
  if (checklistResult.status === 200 && checklistResult.data?.id) {
    created.checklist.push(checklistResult.data.id);
    await request(`/items/symbolika_task_checklist/${checklistResult.data.id}`, { token: users.designer.token, method: 'PATCH', body: JSON.stringify({ is_done: true }) });
  }
  record('Исполнитель ведёт обсуждение и чек-лист задачи', taskCommentResult.status === 200 && checklistResult.status === 200, `comment=${taskCommentResult.status}, checklist=${checklistResult.status}`);
  await request(`/items/symbolika_tasks/${designTask.id}`, {
    token: users.designer.token, method: 'PATCH', body: JSON.stringify({ status: 'waiting' }),
  });
  const waitingTask = await request(`/items/symbolika_tasks/${designTask.id}?fields=status`, { token: users.designer.token });
  record('Исполнитель отмечает задачу «Жду ответа»', waitingTask.status === 'waiting', `status=${waitingTask.status}`);
  await request(`/items/symbolika_tasks/${designTask.id}`, {
    token: users.designer.token, method: 'PATCH', body: JSON.stringify({ result_url: 'https://example.test/designer-result.pdf', status: 'done' }),
  });
  const designDone = await waitFor(async () => {
    const row = await request(`/items/orders_items/${designItem.id}?fields=url`);
    return row.url === 'https://example.test/designer-result.pdf' ? row : null;
  });
  record('Результат выполненной задачи дизайнера переносится в макет позиции', !!designDone);

  const inventory = await request('/items/inventory_items', {
    token: users.management.token, method: 'POST',
    body: JSON.stringify({ name: `QA Бумага ${suffix}`, section: 'production', item_type: 'material', unit: 'шт.', current_qty: 1, min_qty: 5, is_active: true }),
  });
  created.inventory.push(inventory.id);
  const autoProcurement = await waitFor(async () => {
    const rows = await list('procurement_requests', `fields=id,status,inventory_item,quantity,auto_generated,request_source&filter[inventory_item][_eq]=${inventory.id}&limit=-1`);
    return rows[0] || null;
  });
  if (autoProcurement) created.procurement.push(autoProcurement.id);
  record('Остаток ниже минимума создаёт одну автоматическую заявку', !!autoProcurement && autoProcurement.auto_generated === true, JSON.stringify(autoProcurement));
  const duplicates = await list('procurement_requests', `fields=id&filter[inventory_item][_eq]=${inventory.id}&filter[status][_nin]=received,cancelled&limit=-1`);
  record('Автозакупка не дублируется для одной складской позиции', duplicates.length === 1, `active=${duplicates.length}`);

  const managementProcurement = await list('procurement_requests', `fields=id,status,product_name&filter[id][_eq]=${autoProcurement.id}`, users.management.token);
  record('Управляющий видит и может редактировать все закупки', managementProcurement.length === 1);
  const procurementWithTask = await waitFor(async () => {
    const row = await request(`/items/procurement_requests/${autoProcurement.id}?fields=id,status,task_order_id,procurement_batch`);
    if (row.task_order_id) return { ...row, effective_task_id: row.task_order_id };
    if (row.procurement_batch) {
      if (!created.batches.includes(row.procurement_batch)) created.batches.push(row.procurement_batch);
      const batch = await request(`/items/procurement_batches/${row.procurement_batch}?fields=id,status,task_order_id,management_task_id`);
      for (const taskId of [batch.task_order_id, batch.management_task_id].filter(Boolean)) {
        if (!created.tasks.includes(taskId)) created.tasks.push(taskId);
      }
      const effectiveTaskId = batch.task_order_id || batch.management_task_id;
      if (effectiveTaskId) return { ...row, batch, effective_task_id: effectiveTaskId };
    }
    return null;
  });
  record('Закупочная заявка создаёт связанную задачу', !!procurementWithTask?.effective_task_id, JSON.stringify(procurementWithTask));
  if (procurementWithTask?.effective_task_id) {
    created.tasks.push(procurementWithTask.effective_task_id);
    await request(`/items/symbolika_tasks/${procurementWithTask.effective_task_id}`, { token: users.management.token, method: 'PATCH', body: JSON.stringify({ status: 'done' }) });
  }
  const ordered = await waitFor(async () => {
    const row = await request(`/items/procurement_requests/${autoProcurement.id}?fields=status`);
    return row.status === 'ordered' ? row : null;
  });
  record('Готовая задача автоматически переводит закупку в «Заказано»', !!ordered, JSON.stringify(ordered));

  const officeCertificates = await request('/items/gift_certificates?fields=id,code,nominal_amount,remaining_amount,created_at,valid_until,status,comment&limit=1', {
    token: users.office.token, expected: [200, 403],
  });
  record('Офисный запрос сертификатов соответствует полевым правам UI', officeCertificates.status === 200, `HTTP ${officeCertificates.status}`);

  const automationHealthManagement = await request('/symbolika-support/automation-health', { token: users.management.token, expected: [200, 403] });
  const automationHealthManager = await request('/symbolika-support/automation-health', { token: users.managerA.token, expected: [200, 403] });
  record('Здоровье автоматизаций доступно управляющему', automationHealthManagement.status === 200, `HTTP ${automationHealthManagement.status}`);
  record('Здоровье автоматизаций закрыто обычному менеджеру', automationHealthManager.status === 403, `HTTP ${automationHealthManager.status}`);

  const publicToken = (await request(`/items/orders_items/${designItem.id}?fields=public_token`)).public_token;
  const publicItem = await request(`/symbolika-public-item/${publicToken}`, { token: null, expected: [200, 404] });
  record('Публичная ссылка позиции открывается без авторизации', publicItem.status === 200, `HTTP ${publicItem.status}`);
  const invalidPublicItem = await request('/symbolika-public-item/not-a-real-token', { token: null, expected: [200, 404] });
  record('Неверный публичный токен не раскрывает позицию', invalidPublicItem.status === 404);
}

(async () => {
  try {
    await run();
    if (checks.some((check) => !check.ok)) process.exitCode = 1;
  } finally {
    await cleanup();
    console.log(`CLEANUP ${suffix}`);
    console.log(JSON.stringify({ suffix, checks }, null, 2));
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

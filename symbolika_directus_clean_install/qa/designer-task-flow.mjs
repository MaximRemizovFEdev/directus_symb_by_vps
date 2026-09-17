const baseUrl = String(process.env.DIRECTUS_URL || 'http://localhost:8057').replace(/\/$/, '');
const token = String(process.env.SYMBOLIKA_QA_ADMIN_TOKEN || '').trim();
if (!token) throw new Error('Set SYMBOLIKA_QA_ADMIN_TOKEN.');

async function api(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers || {}),
    },
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${path}: ${payload?.errors?.[0]?.message || response.status}`);
  return payload;
}

let customerId;
let orderId;
let itemId;
let taskId;

try {
  customerId = (await api('/items/customers', {
    method: 'POST',
    body: JSON.stringify({ name: 'QA Дизайнер' }),
  })).data.id;
  orderId = (await api('/items/orders', {
    method: 'POST',
    body: JSON.stringify({ date: '2026-08-10', customer: customerId }),
  })).data.id;
  itemId = (await api('/items/orders_items', {
    method: 'POST',
    body: JSON.stringify({
      order: orderId,
      product_name: 'QA макет',
      quantity: 1,
      price_per_unit: 0,
      technical_task_text: 'ТЗ для проверки',
      needs_designer_help: true,
      designer_comment: 'Комментарий менеджера для дизайнера',
      designer_source_url: 'https://example.test/source.pdf',
    }),
  })).data.id;

  const tasks = await api(`/items/symbolika_tasks?filter[related_order_item][_eq]=${itemId}&filter[task_type][_eq]=design&limit=1`);
  const task = tasks.data?.[0];
  if (!task) throw new Error('Дизайнерская задача не создана.');
  taskId = task.id;
  if (task.description !== 'Комментарий менеджера для дизайнера') throw new Error('Комментарий не перенесён в задачу.');
  if (task.source_url !== 'https://example.test/source.pdf') throw new Error('Исходная ссылка не перенесена в задачу.');
  if (task.result_url) throw new Error('Исходная ссылка ошибочно записана как готовый макет.');

  const readyUrl = 'https://example.test/ready.pdf';
  await api(`/items/symbolika_tasks/${taskId}`, {
    method: 'PATCH',
    body: JSON.stringify({ status: 'done', completed_at: new Date().toISOString(), result_url: readyUrl }),
  });

  let itemUrl = '';
  for (let attempt = 0; attempt < 20; attempt += 1) {
    itemUrl = (await api(`/items/orders_items/${itemId}?fields=url`)).data?.url || '';
    if (itemUrl === readyUrl) break;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  if (itemUrl !== readyUrl) throw new Error('Готовый макет не перенесён в позицию.');

  console.log(JSON.stringify({ taskCreated: true, commentAndSourceCopied: true, resultReplacedItemLayout: true }));
} finally {
  if (taskId) await api(`/items/symbolika_tasks/${taskId}`, { method: 'DELETE' }).catch(() => {});
  if (itemId) await api(`/items/orders_items/${itemId}`, { method: 'DELETE' }).catch(() => {});
  if (orderId) await api(`/items/orders/${orderId}`, { method: 'DELETE' }).catch(() => {});
  if (customerId) await api(`/items/customers/${customerId}`, { method: 'DELETE' }).catch(() => {});
}

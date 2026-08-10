const escapeHtml = (value) => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;')
  .replaceAll("'", '&#039;');

const formatDate = (value) => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('ru-RU').format(date);
};

const formatQuantity = (value) => new Intl.NumberFormat('ru-RU', {
  maximumFractionDigits: 2,
}).format(Number(value || 0));

const publicStatus = (row) => {
  if (row.office_status === 'issued') return 'Выдан';
  if (row.office_status === 'in_office') return 'Готов к выдаче';
  const value = String(row.item_status || '').toLowerCase();
  if (value === 'ready') return 'Готов';
  if (value === 'layout_revision') return 'Уточнение макета';
  if (['sent_to_work', 'in_work'].includes(value)) return 'В работе';
  if (value === 'cancelled') return 'Отменён';
  return row.order_status_name || 'Заказ принят';
};

export default {
  id: 'symbolika-public-item',

  handler: (router, { database, env, logger, services, getSchema }) => {
    const externalBaseUrl = (req) => {
      const configured = env?.SYMBOLIKA_PUBLIC_URL || env?.PUBLIC_URL || env?.DIRECTUS_PUBLIC_URL || '';
      if (/^https?:\/\//i.test(configured)) return configured.replace(/\/$/, '');
      const protocol = String(req.headers['x-forwarded-proto'] || req.protocol || 'http').split(',')[0].trim();
      return `${protocol}://${req.get('host')}`;
    };

    const itemLink = (req, token) => `${externalBaseUrl(req)}/symbolika-public-item/${token}`;

    router.post('/links', async (req, res) => {
      try {
        const userId = req.accountability?.user;
        if (!userId) return res.status(401).json({ errors: [{ message: 'Требуется авторизация.' }] });

        const ids = [...new Set((req.body?.ids || []).map(Number).filter(Number.isInteger))].slice(0, 5000);
        if (!ids.length) return res.json({ data: [] });

        const user = await database('directus_users as u')
          .leftJoin('directus_roles as r', 'r.id', 'u.role')
          .where('u.id', userId)
          .select('r.name as role_name')
          .first();
        const roleName = user?.role_name || '';

        let allowedIds = ids;
        if (roleName === 'Производство') {
          allowedIds = (await database('production_work').whereIn('id', ids).pluck('id')).map(Number);
        } else if (roleName === 'Шелкография') {
          allowedIds = (await database('screen_printing_work').whereIn('id', ids).pluck('id')).map(Number);
        } else if (!['Administrator', 'Управляющий'].includes(roleName)) {
          try {
            const { ItemsService } = services;
            const itemService = new ItemsService('orders_items', {
              schema: await getSchema(),
              accountability: req.accountability,
            });
            const readableRows = await itemService.readByQuery({
              fields: ['id'],
              filter: { id: { _in: ids } },
              limit: ids.length,
            });
            allowedIds = readableRows.map((row) => Number(row.id));
          } catch {
            allowedIds = [];
          }
        }

        const rows = await database('orders_items')
          .whereIn('id', allowedIds)
          .select('id', 'public_token');
        return res.json({
          data: rows.map((row) => ({
            id: row.id,
            token: row.public_token,
            url: itemLink(req, row.public_token),
          })),
        });
      } catch (error) {
        logger.error(error);
        return res.status(500).json({ errors: [{ message: 'Не удалось сформировать публичные ссылки.' }] });
      }
    });

    router.get('/:token', async (req, res) => {
      try {
        const token = String(req.params.token || '').trim();
        if (!/^[0-9a-f-]{36}$/i.test(token)) return res.status(404).send('Страница не найдена');

        const row = await database('orders_items as oi')
          .join('orders as o', 'o.id', 'oi.order')
          .leftJoin('order_statuses as os', 'os.id', 'o.order_status')
          .leftJoin('employees as e', 'e.id', 'o.manager_employee')
          .where('oi.public_token', token)
          .select(
            'oi.id', 'oi.product_name', 'oi.quantity', 'oi.deadline', 'oi.item_status', 'oi.office_status',
            'o.id as order_id', 'o.order_number', 'os.name as order_status_name',
            'e.full_name as manager_name', 'e.phone as manager_phone',
          )
          .first();

        if (!row) return res.status(404).send('Страница не найдена');

        if (req.accountability?.user) {
          return res.redirect(`/admin/symbolika-orders?item=${encodeURIComponent(row.id)}`);
        }

        const settings = await database('symbolika_customer_notification_settings').where({ id: 1 }).first().catch(() => null);
        const managerPhone = row.manager_phone
          ? `<a href="tel:${escapeHtml(String(row.manager_phone).replace(/[^+\d]/g, ''))}">${escapeHtml(row.manager_phone)}</a>`
          : '<span>Телефон уточняется</span>';
        const website = settings?.website_url
          ? `<a class="button secondary" href="${escapeHtml(settings.website_url)}" target="_blank" rel="noreferrer">Наш сайт</a>`
          : '';
        const vk = settings?.vk_group_url
          ? `<a class="button secondary" href="${escapeHtml(settings.vk_group_url)}" target="_blank" rel="noreferrer">Группа ВКонтакте</a>`
          : '';

        res.type('html').send(`<!doctype html>
          <html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>${escapeHtml(row.order_number)} · ${escapeHtml(row.product_name)}</title>
          <style>
            :root{color-scheme:dark;font-family:Inter,Arial,sans-serif}*{box-sizing:border-box}body{margin:0;background:#0d1117;color:#f0f3f6;padding:20px}.page{max-width:680px;margin:0 auto}.brand{color:#ff8738;font-weight:900;letter-spacing:.08em;text-transform:uppercase}.card{margin-top:18px;background:#171c24;border:1px solid #30363d;border-radius:20px;padding:22px;box-shadow:0 18px 45px #0005}h1{margin:8px 0 4px;font-size:28px}.muted{color:#8b949e}.status{display:inline-flex;margin:18px 0 6px;padding:8px 12px;border-radius:999px;background:#173c2b;color:#6ee7b7;font-weight:800}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:18px}.field{background:#0f141a;border-radius:13px;padding:13px}.field span{display:block;color:#8b949e;font-size:12px}.field strong{display:block;margin-top:5px}.manager{margin-top:18px;padding-top:18px;border-top:1px solid #30363d}.manager a{color:#ffab70}.actions{display:flex;flex-wrap:wrap;gap:9px;margin-top:18px}.button{display:inline-flex;text-decoration:none;border-radius:12px;padding:11px 14px;font-weight:800;background:#ff8738;color:#111}.button.secondary{background:#242b35;color:#f0f3f6}@media(max-width:520px){body{padding:12px}.card{padding:17px}.grid{grid-template-columns:1fr}h1{font-size:24px}}
          </style></head><body><main class="page"><div class="brand">Символика</div><section class="card">
          <div class="muted">Заказ ${escapeHtml(row.order_number || `#${row.order_id}`)}</div><h1>${escapeHtml(row.product_name || 'Позиция заказа')}</h1>
          <div class="status">${escapeHtml(publicStatus(row))}</div><div class="grid">
          <div class="field"><span>Количество</span><strong>${escapeHtml(formatQuantity(row.quantity))} шт.</strong></div>
          <div class="field"><span>Ориентировочный срок</span><strong>${escapeHtml(formatDate(row.deadline) || 'Уточняется')}</strong></div></div>
          <div class="manager"><div class="muted">Ваш менеджер</div><strong>${escapeHtml(row.manager_name || 'Менеджер не указан')}</strong><div>${managerPhone}</div></div>
          <div class="actions">${website}${vk}</div></section></main></body></html>`);
      } catch (error) {
        logger.error(error);
        res.status(500).send('Не удалось открыть информацию о позиции');
      }
    });
  },
};

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPEARANCE_THEMES = new Set(['graphite', 'espresso', 'pearl', 'frost']);
const NOTIFICATION_TOPICS = ['order_status', 'item_status', 'new_tasks', 'task_updates', 'production', 'procurement', 'mail', 'finance', 'birthdays'];
const DEFAULT_NOTIFICATION_TOPICS = {
  order_status: true,
  item_status: true,
  new_tasks: true,
  task_updates: true,
  production: true,
  procurement: true,
  mail: false,
  finance: true,
  birthdays: true,
};

function cleanText(value, maxLength) {
  return String(value ?? '').trim().slice(0, maxLength);
}

function publicUser(row) {
  return {
    id: row.id,
    email: row.email || '',
    first_name: row.first_name || '',
    last_name: row.last_name || '',
    phone: row.profile_phone || row.employee_phone || row.contractor_phone || '',
    avatar: row.avatar || null,
    role_name: row.role_name || '',
    symbolika_theme: APPEARANCE_THEMES.has(row.symbolika_theme) ? row.symbolika_theme : 'graphite',
  };
}

function monthRange(value) {
  const match = String(value || '').match(/^(\d{4})-(0[1-9]|1[0-2])$/);
  const now = new Date();
  const year = match ? Number(match[1]) : now.getFullYear();
  const month = match ? Number(match[2]) : now.getMonth() + 1;
  const start = `${year}-${String(month).padStart(2, '0')}-01`;
  const nextYear = month === 12 ? year + 1 : year;
  const nextMonth = month === 12 ? 1 : month + 1;
  return {
    key: `${year}-${String(month).padStart(2, '0')}`,
    start,
    end: `${nextYear}-${String(nextMonth).padStart(2, '0')}-01`,
  };
}

function notificationLink(collection, item) {
  const id = item == null ? '' : String(item);
  const query = (name) => id ? `?${name}=${encodeURIComponent(id)}` : '';
  if (collection === 'orders') return `/admin/symbolika-orders${query('order')}`;
  if (collection === 'orders_items') return `/admin/symbolika-orders${query('item')}`;
  if (collection === 'symbolika_tasks') return `/admin/symbolika-tasks${query('task')}`;
  if (collection === 'symbolika_mail_threads') return `/admin/symbolika-mail-module${query('thread')}`;
  if (collection === 'procurement_requests') return `/admin/symbolika-procurement${query('request')}`;
  if (collection === 'production_work' || collection === 'screen_printing_work') return `/admin/symbolika-production${query('item')}`;
  if (collection === 'customers' || collection === 'customer_companies') return '/admin/symbolika-orders';
  if (collection === 'employees') return '/admin/symbolika-notifications-module';
  return '/admin/symbolika-orders';
}

function notificationKind(collection) {
  if (collection === 'orders') return 'order';
  if (collection === 'orders_items' || collection === 'production_work' || collection === 'screen_printing_work') return 'item';
  if (collection === 'symbolika_tasks') return 'task';
  if (collection === 'symbolika_mail_threads') return 'mail';
  if (collection === 'procurement_requests') return 'procurement';
  if (collection === 'employees') return 'birthday';
  return 'system';
}

function booleanValue(value, fallback = false) {
  if (value === undefined) return fallback;
  return value === true || value === 1 || value === '1' || value === 'true';
}

export default {
  id: 'symbolika-profile',
  handler: (router, { database }) => {
    const requireUser = (req, res) => {
      const userId = req.accountability?.user;
      if (!userId) {
        res.status(401).json({ errors: [{ message: 'Требуется авторизация.' }] });
        return null;
      }
      return userId;
    };

    const loadProfile = async (userId) => {
      const row = await database('directus_users as u')
        .leftJoin('directus_roles as r', 'r.id', 'u.role')
        .leftJoin('employees as e', 'e.directus_user', 'u.id')
        .leftJoin('employee_positions as ep', 'ep.id', 'e.position')
        .leftJoin('contractors as c', 'c.directus_user', 'u.id')
        .where('u.id', userId)
        .select(
          'u.id', 'u.email', 'u.first_name', 'u.last_name', 'u.avatar',
          'u.phone as profile_phone', 'u.symbolika_theme', 'r.name as role_name',
          'e.id as employee_id', 'e.full_name as employee_name', 'e.phone as employee_phone', 'e.birthday as employee_birthday',
          'ep.name as position_name',
          'c.id as contractor_id', 'c.name as contractor_name', 'c.phone as contractor_phone',
        )
        .first();

      if (!row) return null;

      let salary = null;
      let salaryHistory = [];
      if (row.employee_id) {
        salary = await database('employee_salary_summary')
          .where('employee', row.employee_id)
          .first();
        salaryHistory = await database('employee_salary_monthly')
          .where('employee', row.employee_id)
          .orderBy('month_start', 'desc')
          .limit(12);
      }

      return {
        user: publicUser(row),
        person: {
          employee_id: row.employee_id || null,
          contractor_id: row.contractor_id || null,
          name: row.employee_name || row.contractor_name || [row.first_name, row.last_name].filter(Boolean).join(' ') || row.email,
          position: row.position_name || (row.contractor_id ? 'Контрагент' : row.role_name) || '',
          birthday: row.employee_birthday || null,
        },
        salary,
        salary_history: salaryHistory,
      };
    };

    const actorContext = async (userId) => database('directus_users as u')
      .leftJoin('directus_roles as r', 'r.id', 'u.role')
      .leftJoin('employees as e', 'e.directus_user', 'u.id')
      .where('u.id', userId)
      .select('u.id', 'r.name as role_name', 'e.id as employee_id')
      .first();

    const canViewAllPayroll = (actor) => ['Administrator', 'Управляющий'].includes(actor?.role_name);

    const loadNotificationSettings = async (userId) => {
      const user = await database('directus_users').where('id', userId).select('email').first();
      const settings = await database('symbolika_employee_notification_settings').where('user', userId).first();
      const pushSubscriptions = await database('symbolika_push_subscriptions').where('user', userId).count('* as count').first();
      return {
        push_enabled: settings?.push_enabled !== false,
        email_enabled: Boolean(settings?.email_enabled),
        vk_enabled: Boolean(settings?.vk_enabled),
        telegram_enabled: Boolean(settings?.telegram_enabled),
        email_address: settings?.email_address || user?.email || '',
        vk_peer_id: settings?.vk_peer_id || '',
        telegram_chat_id: settings?.telegram_chat_id || '',
        push_subscriptions: Number(pushSubscriptions?.count || 0),
        topics: { ...DEFAULT_NOTIFICATION_TOPICS, ...(settings?.topics || {}) },
      };
    };

    router.get('/notifications', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const limit = Math.min(200, Math.max(20, Number(req.query?.limit || 100)));
        const rows = await database('directus_notifications')
          .where('recipient', userId)
          .select('id', 'status', 'subject', 'message', 'collection', 'item', 'timestamp')
          .orderBy('timestamp', 'desc')
          .limit(limit);
        const unread = await database('directus_notifications')
          .where({ recipient: userId, status: 'inbox' })
          .count('* as count')
          .first();
        const ids = rows.map((row) => row.id);
        const deliveries = ids.length
          ? await database('symbolika_employee_notification_deliveries')
            .where('user', userId)
            .whereIn('notification', ids)
            .select('notification', 'channel', 'status', 'last_error', 'sent_at', 'updated_at')
          : [];
        const deliveryMap = deliveries.reduce((map, row) => {
          const key = String(row.notification);
          if (!map[key]) map[key] = [];
          map[key].push(row);
          return map;
        }, {});
        const settings = await loadNotificationSettings(userId);
        return res.json({
          data: {
            notifications: rows.map((row) => ({
              ...row,
              kind: notificationKind(row.collection),
              link: notificationLink(row.collection, row.item),
              unread: row.status === 'inbox',
              deliveries: deliveryMap[String(row.id)] || [],
            })),
            unread_count: Number(unread?.count || 0),
            settings,
          },
        });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/notifications/settings', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const current = await loadNotificationSettings(userId);
        const settings = {
          push_enabled: booleanValue(req.body?.push_enabled, current.push_enabled),
          email_enabled: booleanValue(req.body?.email_enabled, current.email_enabled),
          vk_enabled: booleanValue(req.body?.vk_enabled, current.vk_enabled),
          telegram_enabled: booleanValue(req.body?.telegram_enabled, current.telegram_enabled),
          email_address: cleanText(req.body?.email_address ?? current.email_address, 255).toLowerCase() || null,
          vk_peer_id: cleanText(req.body?.vk_peer_id ?? current.vk_peer_id, 100) || null,
          telegram_chat_id: cleanText(req.body?.telegram_chat_id ?? current.telegram_chat_id, 100) || null,
          topics: NOTIFICATION_TOPICS.reduce((topics, key) => {
            topics[key] = booleanValue(req.body?.topics?.[key], current.topics?.[key] ?? DEFAULT_NOTIFICATION_TOPICS[key]);
            return topics;
          }, {}),
          updated_at: database.fn.now(),
        };
        if (settings.email_enabled && !EMAIL_PATTERN.test(settings.email_address || '')) {
          return res.status(400).json({ errors: [{ message: 'Укажите корректный e-mail для уведомлений.' }] });
        }
        if (settings.vk_enabled && !settings.vk_peer_id) {
          return res.status(400).json({ errors: [{ message: 'Укажите VK peer ID для уведомлений.' }] });
        }
        if (settings.telegram_enabled && !settings.telegram_chat_id) {
          return res.status(400).json({ errors: [{ message: 'Укажите Telegram chat ID для уведомлений.' }] });
        }
        await database('symbolika_employee_notification_settings')
          .insert({ user: userId, ...settings, created_at: database.fn.now() })
          .onConflict('user')
          .merge(settings);
        return res.json({ data: await loadNotificationSettings(userId) });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/notifications/:id/read', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const updated = await database('directus_notifications')
          .where({ id: req.params.id, recipient: userId })
          .update({ status: 'archived' });
        if (!updated) return res.status(404).json({ errors: [{ message: 'Уведомление не найдено.' }] });
        return res.json({ data: { id: req.params.id, status: 'archived' } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/notifications/read-all', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const updated = await database('directus_notifications')
          .where({ recipient: userId, status: 'inbox' })
          .update({ status: 'archived' });
        return res.json({ data: { updated: Number(updated || 0) } });
      } catch (error) {
        return next(error);
      }
    });

    const buildPayslip = async (employeeId, period) => {
      const employee = await database('employees as e')
        .leftJoin('employee_positions as ep', 'ep.id', 'e.position')
        .where('e.id', employeeId)
        .select('e.id', 'e.full_name', 'e.salary_fixed', 'e.order_percent', 'ep.name as position_name')
        .first();
      if (!employee) return null;

      const orderTotals = await database('orders as o')
        .whereRaw('COALESCE(o.commission_manager_employee, o.manager_employee) = ?', [employeeId])
        .where('o.date', '>=', period.start)
        .where('o.date', '<', period.end)
        .select(database.raw(`
          COUNT(o.id)::integer AS orders_count,
          ROUND(COALESCE(SUM(o.order_sum), 0), 2) AS orders_sum,
          ROUND(COALESCE(SUM(o.paid_amount), 0), 2) AS paid_orders_sum,
          ROUND(COALESCE(SUM(GREATEST(o.payment_due, 0)), 0), 2) AS unpaid_orders_sum
        `))
        .first();

      const payouts = await database('business_expenses as be')
        .leftJoin('payment_types as pt', 'pt.id', 'be.payment_type')
        .where('be.employee', employeeId)
        .whereRaw("COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = ?::date", [period.start])
        .whereIn('be.expense_type', ['salary_payment', 'employee_advance', 'employee_bonus'])
        .select('be.id', 'be.expense_date', 'be.accounting_month', 'be.expense_type', 'be.amount', 'be.comment', 'pt.name as payment_type_name')
        .orderBy('be.expense_date', 'asc')
        .orderBy('be.id', 'asc');

      const sumType = (type) => payouts
        .filter((row) => row.expense_type === type)
        .reduce((sum, row) => sum + Number(row.amount || 0), 0);
      const salaryFixed = Number(employee.salary_fixed || 0);
      const orderPercent = Number(employee.order_percent || 0);
      const paidOrders = Number(orderTotals?.paid_orders_sum || 0);
      const commissionAccrued = Math.round(paidOrders * orderPercent) / 100;
      const salaryPaid = sumType('salary_payment');
      const advancesPaid = sumType('employee_advance');
      const bonusAccrued = sumType('employee_bonus');
      const totalAccrued = salaryFixed + commissionAccrued + bonusAccrued;
      const totalPaid = salaryPaid + advancesPaid;

      return {
        month: period.key,
        employee: {
          id: employee.id,
          name: employee.full_name,
          position: employee.position_name || '',
        },
        salary_fixed: salaryFixed,
        order_percent: orderPercent,
        orders_count: Number(orderTotals?.orders_count || 0),
        orders_sum: Number(orderTotals?.orders_sum || 0),
        paid_orders_sum: paidOrders,
        unpaid_orders_sum: Number(orderTotals?.unpaid_orders_sum || 0),
        commission_accrued: commissionAccrued,
        bonus_paid: bonusAccrued,
        bonus_accrued: bonusAccrued,
        salary_paid: salaryPaid,
        advances_paid: advancesPaid,
        total_accrued: totalAccrued,
        total_paid: totalPaid,
        salary_due: totalAccrued - totalPaid,
        bonuses: payouts.filter((row) => row.expense_type === 'employee_bonus'),
        payouts,
      };
    };

    router.get('/payslip', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const actor = await actorContext(userId);
        const requestedEmployee = Number(req.query?.employee || actor?.employee_id || 0);
        if (!requestedEmployee) return res.status(404).json({ errors: [{ message: 'К аккаунту не привязан сотрудник.' }] });
        if (!canViewAllPayroll(actor) && Number(actor?.employee_id) !== requestedEmployee) {
          return res.status(403).json({ errors: [{ message: 'Можно сформировать только собственный расчётный лист.' }] });
        }
        const payslip = await buildPayslip(requestedEmployee, monthRange(req.query?.month));
        if (!payslip) return res.status(404).json({ errors: [{ message: 'Сотрудник не найден.' }] });
        return res.json({ data: payslip });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/manager-summary', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const actor = await actorContext(userId);
        if (!canViewAllPayroll(actor)) {
          return res.status(403).json({ errors: [{ message: 'Сводка менеджеров доступна администратору и управляющему.' }] });
        }
        const period = monthRange(req.query?.month);
        const result = await database.raw(`
          SELECT
            e.id AS employee,
            e.full_name AS employee_name,
            COALESCE(e.order_percent, 0)::numeric AS order_percent,
            COUNT(o.id)::integer AS orders_count,
            ROUND(COALESCE(SUM(o.order_sum), 0), 2) AS orders_sum,
            ROUND(COALESCE(SUM(o.paid_amount), 0), 2) AS paid_orders_sum,
            ROUND(COALESCE(SUM(GREATEST(o.payment_due, 0)), 0), 2) AS unpaid_orders_sum,
            ROUND(CASE WHEN COUNT(o.id) > 0 THEN COALESCE(SUM(o.order_sum), 0) / COUNT(o.id) ELSE 0 END, 2) AS average_order_sum,
            ROUND(CASE WHEN COALESCE(SUM(o.order_sum), 0) > 0 THEN COALESCE(SUM(o.paid_amount), 0) * 100 / SUM(o.order_sum) ELSE 0 END, 2) AS payment_rate,
            ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2) AS commission_accrued
          FROM employees e
          LEFT JOIN orders o
            ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
           AND o.date >= ?::date
           AND o.date < ?::date
          WHERE COALESCE(e.is_active, true) = true
            AND (COALESCE(e.order_percent, 0) > 0 OR o.id IS NOT NULL)
          GROUP BY e.id, e.full_name, e.order_percent
          ORDER BY orders_sum DESC, employee_name
        `, [period.start, period.end]);
        return res.json({ data: { month: period.key, rows: result.rows || result } });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/theme', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const row = await database('directus_users').where('id', userId).select('symbolika_theme').first();
        if (!row) return res.status(404).json({ errors: [{ message: 'Профиль не найден.' }] });
        const theme = APPEARANCE_THEMES.has(row.symbolika_theme) ? row.symbolika_theme : 'graphite';
        return res.json({ data: { theme } });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/theme', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const theme = cleanText(req.body?.theme, 32);
        if (!APPEARANCE_THEMES.has(theme)) {
          return res.status(400).json({ errors: [{ message: 'Неизвестная тема оформления.' }] });
        }
        const updated = await database('directus_users').where('id', userId).update({ symbolika_theme: theme });
        if (!updated) return res.status(404).json({ errors: [{ message: 'Профиль не найден.' }] });
        return res.json({ data: { theme } });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const profile = await loadProfile(userId);
        if (!profile) return res.status(404).json({ errors: [{ message: 'Профиль не найден.' }] });
        return res.json({ data: profile });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;

        const current = await database('directus_users').where('id', userId).select('id', 'email', 'avatar').first();
        if (!current) return res.status(404).json({ errors: [{ message: 'Профиль не найден.' }] });

        const update = {};
        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'email')) {
          const email = cleanText(req.body.email, 255).toLowerCase();
          if (!EMAIL_PATTERN.test(email)) {
            return res.status(400).json({ errors: [{ message: 'Укажите корректный email.' }] });
          }
          const duplicate = await database('directus_users').whereRaw('lower(email) = lower(?)', [email]).whereNot('id', userId).first('id');
          if (duplicate) return res.status(409).json({ errors: [{ message: 'Этот email уже используется.' }] });
          update.email = email;
        }

        let phone;
        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'phone')) {
          phone = cleanText(req.body.phone, 64);
          update.phone = phone || null;
        }

        let birthday;
        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'birthday')) {
          const value = cleanText(req.body.birthday, 10);
          if (value) {
            const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
            const date = match ? new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))) : null;
            const valid = date
              && date.getUTCFullYear() === Number(match[1])
              && date.getUTCMonth() === Number(match[2]) - 1
              && date.getUTCDate() === Number(match[3])
              && Number(match[1]) >= 1900
              && date <= new Date();
            if (!valid) return res.status(400).json({ errors: [{ message: 'Укажите корректную дату рождения.' }] });
          }
          birthday = value || null;
        }

        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'avatar')) {
          const avatar = req.body.avatar || null;
          if (avatar !== null && !UUID_PATTERN.test(String(avatar))) {
            return res.status(400).json({ errors: [{ message: 'Некорректный файл аватара.' }] });
          }
          if (avatar) {
            const file = await database('directus_files').where('id', avatar).select('id', 'type').first();
            if (!file || !String(file.type || '').toLowerCase().startsWith('image/')) {
              return res.status(400).json({ errors: [{ message: 'Для аватара можно выбрать только изображение.' }] });
            }
          }
          update.avatar = avatar;
        }

        await database.transaction(async (trx) => {
          if (Object.keys(update).length) await trx('directus_users').where('id', userId).update(update);
          if (phone !== undefined) {
            await trx('employees').where('directus_user', userId).update({ phone: phone || null });
            await trx('contractors').where('directus_user', userId).update({ phone: phone || null });
          }
          if (birthday !== undefined) {
            await trx('employees').where('directus_user', userId).update({ birthday });
          }
          if (update.email) {
            await trx('contractors').where('directus_user', userId).update({ email: update.email });
          }
        });

        const profile = await loadProfile(userId);
        return res.json({ data: profile });
      } catch (error) {
        return next(error);
      }
    });
  },
};

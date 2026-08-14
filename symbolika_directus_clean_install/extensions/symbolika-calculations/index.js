import webPush from 'web-push';
import nodemailer from 'nodemailer';

export default ({ filter, action }, { database, logger, env }) => {
  const num = (v) => Number.isFinite(Number(v)) ? Number(v) : 0;
  const round = (v) => Math.round(num(v) * 100) / 100;
  const isEmpty = (v) => v === null || v === undefined || v === '';
  const toDateOnly = (v) => {
    if (isEmpty(v)) return null;
    if (v instanceof Date) return v.toISOString().slice(0, 10);
    return String(v).slice(0, 10);
  };

  const OFFICE_PICKUP = 'office_pickup';
  const NOT_IN_OFFICE = 'not_in_office';
  const IN_OFFICE = 'in_office';
  const ISSUED = 'issued';
  const DEFAULT_NOTIFICATION_TOPICS = {
    order_status: true,
    item_status: true,
    new_tasks: true,
    task_updates: true,
    production: true,
    procurement: true,
    mail: false,
    finance: true,
  };

  const prevOrders = new Map();
  const prevItems = new Map();
  const prevTasks = new Map();
  const prevPayments = new Map();
  const prevContractorPayments = new Map();
  let pushConfigured = false;
  let pushTableReady = false;
  let workNotificationTableReady = false;
  let customerMailTransport = null;

  async function recordAutomationRun(handlerKey, title, status, context = {}, error = null) {
    try {
      const now = database.fn.now();
      const row = {
        handler_key: handlerKey,
        title,
        status,
        last_attempt_at: now,
        last_context: JSON.stringify(context || {}),
        updated_at: now,
      };
      if (status === 'ok') {
        row.last_success_at = now;
        row.last_error = null;
      }
      if (status === 'error') {
        row.last_error_at = now;
        row.last_error = String(error?.message || error || 'Неизвестная ошибка').slice(0, 1000);
      }
      await database('symbolika_automation_runs')
        .insert(row)
        .onConflict('handler_key')
        .merge(row);
    } catch (healthError) {
      logger.warn(`[Symbolika automation health] ${healthError.message}`);
    }
  }

  const formatCustomerMoney = (value) => `${new Intl.NumberFormat('ru-RU', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(num(value))} ₽`;

  const formatCustomerQuantity = (value) => new Intl.NumberFormat('ru-RU', {
    maximumFractionDigits: 2,
  }).format(num(value));

  async function storeEventBeforeDelta(collection, itemId, previousRow, userId = null) {
    if (!collection || !itemId || !previousRow) return;

    try {
      const query = database('symbolika_event_feed')
        .where({ source_collection: collection, source_id: Number(itemId), action: 'update' })
        .whereNull('before_delta');
      if (userId) query.andWhere({ actor_user: userId });

      const event = await query.orderBy('event_id', 'desc').first('event_id', 'delta');
      if (!event?.event_id) return;

      const delta = typeof event.delta === 'string' ? JSON.parse(event.delta || '{}') : (event.delta || {});
      const beforeDelta = {};
      Object.keys(delta).forEach((field) => {
        beforeDelta[field] = Object.prototype.hasOwnProperty.call(previousRow, field)
          ? previousRow[field]
          : null;
      });

      if (Object.keys(beforeDelta).length) {
        await database('symbolika_event_feed')
          .where({ event_id: event.event_id })
          .update({ before_delta: beforeDelta });
      }
    } catch (error) {
      logger.warn(`Could not store rollback snapshot for ${collection}:${itemId}: ${error.message}`);
    }
  }

  async function generateOrderNumber() {
    const last = await database('orders')
      .whereNotNull('order_number')
      .orderBy('id', 'desc')
      .first();

    let next = 1;

    if (last?.order_number) {
      const match = String(last.order_number).match(/(\d+)$/);
      if (match) next = Number(match[1]) + 1;
    }

    return `SO-${String(next).padStart(5, '0')}`;
  }

  async function getEmployeeByUser(userId) {
    if (!userId) return null;

    return await database('employees')
      .where({ directus_user: userId })
      .first();
  }

  async function getEmployeeActorByUser(userId) {
    if (!userId) return null;

    return await database('employees as e')
      .join('directus_users as u', 'u.id', 'e.directus_user')
      .leftJoin('directus_roles as r', 'r.id', 'u.role')
      .where('e.directus_user', userId)
      .whereNot('e.is_active', false)
      .select('e.id', 'r.name as role_name')
      .first();
  }

  async function getCommissionManagerByUser(userId) {
    return getEmployeeActorByUser(userId);
  }

  async function getDeliveredStatusId() {
    const status = await database('order_statuses')
      .whereILike('name', '\u0414\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d')
      .first();

    return status?.id || null;
  }

  async function getReadyStatusId() {
    const status = await database('order_statuses')
      .whereILike('name', '\u0413\u043e\u0442\u043e\u0432')
      .first();

    return status?.id || null;
  }

  async function getReadyProductionStatusId() {
    const status = await database('production_statuses')
      .whereILike('name', '\u0413\u043e\u0442\u043e\u0432')
      .first();

    return status?.id || null;
  }

  async function normalizedContractorCost(contractorId, value) {
    if (!contractorId) return num(value);

    const contractor = await database('contractors')
      .where({ id: contractorId })
      .select('is_internal_production')
      .first();

    return contractor?.is_internal_production ? 0 : num(value);
  }

  async function getRoleUserIds(roleName) {
    if (!roleName) return [];

    const role = await database('directus_roles')
      .where({ name: roleName })
      .first();

    if (!role?.id) return [];

    const users = await database('directus_users')
      .where({ role: role.id, status: 'active' })
      .select('id');

    return users.map((user) => user.id).filter(Boolean);
  }

  async function getEmployeeUserId(employeeId) {
    if (!employeeId) return null;

    const employee = await database('employees')
      .where({ id: employeeId })
      .first();

    return employee?.directus_user || null;
  }

  async function getOrderLabel(orderId) {
    if (!orderId) return '\u0437\u0430\u043a\u0430\u0437';

    const order = await database('orders')
      .where({ id: orderId })
      .first();

    return order?.order_number || `#${orderId}`;
  }

  async function getOrderStatusName(statusId) {
    if (!statusId) return '\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d';

    const status = await database('order_statuses')
      .where({ id: statusId })
      .first();

    return status?.name || String(statusId);
  }

  async function getProductionStatusName(statusId) {
    if (!statusId) return '\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d';

    const status = await database('production_statuses')
      .where({ id: statusId })
      .first();

    return status?.name || String(statusId);
  }

  async function ensurePushTable() {
    if (pushTableReady) return true;

    try {
      const exists = await database.schema.hasTable('symbolika_push_subscriptions');
      if (!exists) {
        await database.schema.createTable('symbolika_push_subscriptions', (table) => {
        table.increments('id').primary();
        table.uuid('user').notNullable();
        table.text('endpoint').notNullable().unique();
        table.jsonb('subscription').notNullable();
        table.text('user_agent');
        table.text('last_error');
        table.timestamp('created_at', { useTz: true }).defaultTo(database.fn.now());
        table.timestamp('updated_at', { useTz: true }).defaultTo(database.fn.now());
        });
      }
      pushTableReady = true;
      return true;
    } catch (error) {
      logger.warn(error);
      return false;
    }
  }

  async function ensureWorkNotificationTable() {
    if (workNotificationTableReady) return true;

    try {
      const exists = await database.schema.hasTable('symbolika_work_assignment_notifications');
      if (!exists) {
        await database.schema.createTable('symbolika_work_assignment_notifications', (table) => {
          table.increments('id').primary();
          table.integer('item').notNullable();
          table.text('channel').notNullable();
          table.timestamp('created_at', { useTz: true }).defaultTo(database.fn.now());
          table.unique(['item', 'channel']);
        });
      }
      workNotificationTableReady = true;
      return true;
    } catch (error) {
      logger.warn(error);
      return false;
    }
  }

  function configurePush() {
    if (pushConfigured) return true;

    const publicKey = env?.SYMBOLIKA_PUSH_PUBLIC_KEY;
    const privateKey = env?.SYMBOLIKA_PUSH_PRIVATE_KEY;
    if (!publicKey || !privateKey) return false;

    webPush.setVapidDetails(
      env?.SYMBOLIKA_PUSH_SUBJECT || 'mailto:admin@symbcorp.ru',
      publicKey,
      privateKey
    );

    pushConfigured = true;
    return true;
  }

  function getNotificationUrl(collection, item) {
    if (!collection || item == null) return '/admin/symbolika-orders';
    if (collection === 'orders') return `/admin/symbolika-orders?order=${encodeURIComponent(item)}`;
    if (collection === 'orders_items') return `/admin/symbolika-orders?item=${encodeURIComponent(item)}`;
    if (collection === 'symbolika_tasks') return `/admin/symbolika-tasks?task=${encodeURIComponent(item)}`;
    if (collection === 'symbolika_mail_threads') return `/admin/symbolika-mail-module?thread=${encodeURIComponent(item)}`;
    if (collection === 'procurement_requests') return `/admin/symbolika-procurement?request=${encodeURIComponent(item)}`;
    if (collection === 'production_work') return `/admin/symbolika-production?item=${encodeURIComponent(item)}`;
    if (collection === 'screen_printing_work') return `/admin/symbolika-production?item=${encodeURIComponent(item)}`;
    if (collection === 'office_issue' || collection === 'office_items_in_office') return `/admin/symbolika-orders?order=${encodeURIComponent(item)}`;
    if (collection === 'customers' || collection === 'customer_companies') return '/admin/symbolika-orders';
    return '/admin/symbolika-orders';
  }

  function getPublicUrl(path = '/admin') {
    const baseUrl = env?.SYMBOLIKA_PUBLIC_URL || env?.PUBLIC_URL || env?.DIRECTUS_PUBLIC_URL || '';
    if (!baseUrl || !/^https?:\/\//i.test(baseUrl)) return path;

    try {
      return new URL(path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`).href;
    } catch {
      return path;
    }
  }

  function getVkPeerId(channel) {
    if (channel === 'production') return env?.SYMBOLIKA_VK_PRODUCTION_PEER_ID || null;
    if (channel === 'screen_printing') return env?.SYMBOLIKA_VK_SCREEN_PRINTING_PEER_ID || null;
    return null;
  }

  async function sendVkMessage(channel, message) {
    const token = env?.SYMBOLIKA_VK_TOKEN;
    const peerId = getVkPeerId(channel);
    if (!token || !peerId || !message) {
      logger.warn({
        channel,
        tokenConfigured: Boolean(token),
        peerConfigured: Boolean(peerId),
        messageConfigured: Boolean(message),
      }, '[Symbolika VK] send skipped: incomplete configuration');
      return false;
    }

    try {
      const body = new URLSearchParams({
        access_token: token,
        v: env?.SYMBOLIKA_VK_API_VERSION || '5.199',
        peer_id: String(peerId),
        random_id: String(Date.now() * 1000 + Math.floor(Math.random() * 1000)),
        message,
      });

      const response = await fetch('https://api.vk.com/method/messages.send', {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body,
      });

      const payload = await response.json().catch(() => null);
      if (!response.ok || payload?.error) {
        logger.warn({
          channel,
          error: payload?.error || response.statusText,
        }, '[Symbolika VK] send failed');
        return false;
      }

      return true;
    } catch (error) {
      logger.warn({ channel, error: error?.message || error }, '[Symbolika VK] send failed');
      return false;
    }
  }

  function customerMailSender() {
    if (customerMailTransport) return customerMailTransport;
    const host = env?.SYMBOLIKA_SMTP_HOST || env?.EMAIL_SMTP_HOST;
    const port = Number(env?.SYMBOLIKA_SMTP_PORT || env?.EMAIL_SMTP_PORT || 465);
    const user = env?.SYMBOLIKA_SMTP_USER || env?.EMAIL_SMTP_USER;
    const pass = env?.SYMBOLIKA_SMTP_PASSWORD || env?.EMAIL_SMTP_PASSWORD;
    if (!host || !user || !pass) return null;
    customerMailTransport = nodemailer.createTransport({
      host,
      port,
      secure: String(env?.SYMBOLIKA_SMTP_SECURE || '').toLowerCase() === 'true' || port === 465,
      auth: { user, pass },
    });
    return customerMailTransport;
  }

  async function sendCustomerEmail(recipient, subject, message) {
    const transport = customerMailSender();
    const from = env?.SYMBOLIKA_EMAIL_FROM || env?.EMAIL_FROM || env?.SYMBOLIKA_SMTP_USER || env?.EMAIL_SMTP_USER;
    if (!transport || !from) throw new Error('Не настроена отправка email.');
    const result = await transport.sendMail({ from, to: recipient, subject, text: message });
    return result?.messageId || null;
  }

  async function sendCustomerTelegram(recipient, message) {
    const token = env?.SYMBOLIKA_TELEGRAM_BOT_TOKEN;
    if (!token) throw new Error('Не настроен Telegram-бот.');
    const apiBase = String(env?.SYMBOLIKA_TELEGRAM_API_BASE || 'https://api.telegram.org').replace(/\/$/, '');
    let response;
    try {
      response = await fetch(`${apiBase}/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ chat_id: recipient, text: message, disable_web_page_preview: true }),
        signal: AbortSignal.timeout(15000),
      });
    } catch (error) {
      const reason = error?.cause?.code || error?.cause?.message || error?.name || error?.message || 'ошибка сети';
      throw new Error(`Telegram API недоступен (${reason}). Проверьте исходящее соединение VPS или SYMBOLIKA_TELEGRAM_API_BASE.`);
    }
    const payload = await response.json().catch(() => null);
    if (!response.ok || !payload?.ok) throw new Error(payload?.description || `Telegram HTTP ${response.status}`);
    return payload?.result?.message_id ? String(payload.result.message_id) : null;
  }

  async function sendCustomerVk(recipient, message) {
    const token = env?.SYMBOLIKA_VK_TOKEN;
    if (!token) throw new Error('Не настроена отправка ВКонтакте.');
    const body = new URLSearchParams({
      access_token: token,
      v: env?.SYMBOLIKA_VK_API_VERSION || '5.199',
      peer_id: String(recipient),
      random_id: String(Date.now() * 1000 + Math.floor(Math.random() * 1000)),
      message,
    });
    const response = await fetch('https://api.vk.com/method/messages.send', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || payload?.error) throw new Error(payload?.error?.error_msg || `VK HTTP ${response.status}`);
    return payload?.response != null ? String(payload.response) : null;
  }

  async function sendCustomerSms(recipient, message) {
    const apiId = env?.SYMBOLIKA_SMS_RU_API_ID;
    if (!apiId) throw new Error('Не настроена отправка SMS.');
    const body = new URLSearchParams({
      api_id: apiId,
      to: String(recipient).replace(/\D/g, ''),
      msg: message,
      json: '1',
    });
    const sender = env?.SYMBOLIKA_SMS_RU_FROM;
    if (sender) body.set('from', sender);
    const response = await fetch('https://sms.ru/sms/send', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    });
    const payload = await response.json().catch(() => null);
    const smsResult = payload?.sms?.[String(recipient).replace(/\D/g, '')];
    if (!response.ok || payload?.status !== 'OK' || smsResult?.status !== 'OK') {
      throw new Error(smsResult?.status_text || payload?.status_text || `SMS HTTP ${response.status}`);
    }
    return smsResult?.sms_id || null;
  }

  function customerNotificationRecipient(contact) {
    const channel = contact?.notification_channel || 'none';
    if (channel === 'email') return contact?.email || null;
    if (channel === 'sms') return contact?.phone || null;
    if (channel === 'telegram') return contact?.telegram_chat_id || null;
    if (channel === 'vk') return contact?.vk_peer_id || null;
    return null;
  }

  async function dispatchCustomerNotification(channel, recipient, subject, message) {
    if (channel === 'email') return await sendCustomerEmail(recipient, subject, message);
    if (channel === 'telegram') return await sendCustomerTelegram(recipient, message);
    if (channel === 'vk') return await sendCustomerVk(recipient, message);
    if (channel === 'sms') return await sendCustomerSms(recipient, message);
    throw new Error('Основной канал уведомлений не выбран.');
  }

  async function customerReadyNotificationContext(orderId) {
    if (!orderId) return null;
    const order = await database('orders as o')
      .leftJoin('order_statuses as os', 'os.id', 'o.order_status')
      .leftJoin('customers as customer', 'customer.id', 'o.customer')
      .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
      .where('o.id', orderId)
      .select(
        'o.*', 'os.name as order_status_name',
        'customer.id as customer_contact_id', 'customer.name as customer_contact_name',
        'customer.phone as customer_phone', 'customer.email as customer_email',
        'customer.notification_channel as customer_notification_channel',
        'customer.telegram_chat_id as customer_telegram_chat_id', 'customer.vk_peer_id as customer_vk_peer_id',
        'company.id as company_contact_id', 'company.name as company_contact_name',
        'company.phone as company_phone', 'company.email as company_email',
        'company.notification_channel as company_notification_channel',
        'company.telegram_chat_id as company_telegram_chat_id', 'company.vk_peer_id as company_vk_peer_id',
      )
      .first();
    if (!order) return null;
    if (order.shipping_method !== OFFICE_PICKUP || order.office_status !== IN_OFFICE) return null;
    if (String(order.order_status_name || '').trim() !== 'Готов') return null;

    const items = await database('orders_items')
      .where({ order: orderId })
      .orderBy('id')
      .select('id', 'product_name', 'quantity', 'price_per_unit', 'order_sum', 'office_status');
    if (!items.length || items.some((item) => item.office_status !== IN_OFFICE)) return null;

    const customerContact = order.customer_contact_id ? {
      id: order.customer_contact_id,
      name: order.customer_contact_name,
      phone: order.customer_phone,
      email: order.customer_email,
      notification_channel: order.customer_notification_channel,
      telegram_chat_id: order.customer_telegram_chat_id,
      vk_peer_id: order.customer_vk_peer_id,
    } : null;
    const companyContact = order.company_contact_id ? {
      id: order.company_contact_id,
      name: order.company_contact_name,
      phone: order.company_phone,
      email: order.company_email,
      notification_channel: order.company_notification_channel,
      telegram_chat_id: order.company_telegram_chat_id,
      vk_peer_id: order.company_vk_peer_id,
    } : null;
    const contact = customerContact?.notification_channel && customerContact.notification_channel !== 'none'
      ? customerContact
      : companyContact;
    if (!contact || !contact.notification_channel || contact.notification_channel === 'none') return null;

    return { order, items, contact };
  }

  async function buildCustomerReadyMessage(context) {
    const { order, items } = context;
    const settings = await database('symbolika_customer_notification_settings').where({ id: 1 }).first().catch(() => null);
    const lines = [
      `Заказ ${order.order_number || `#${order.id}`} готов и находится в офисе.`,
      '',
      'Позиции:',
      ...items.map((item) => `• ${item.product_name || `Позиция #${item.id}`} — ${formatCustomerQuantity(item.quantity)} шт. × ${formatCustomerMoney(item.price_per_unit)} = ${formatCustomerMoney(item.order_sum)}`),
      '',
      `Сумма заказа: ${formatCustomerMoney(order.order_sum)}`,
      `Оплачено: ${formatCustomerMoney(order.paid_amount)}`,
      `Остаток к оплате: ${formatCustomerMoney(order.payment_due)}`,
    ];
    if (settings?.office_address) lines.push('', `Адрес офиса: ${settings.office_address}`);
    if (settings?.office_hours) lines.push(`Время работы: ${settings.office_hours}`);
    if (settings?.website_url) lines.push(`Сайт: ${settings.website_url}`);
    if (settings?.vk_group_url) lines.push(`ВКонтакте: ${settings.vk_group_url}`);
    return lines.join('\n');
  }

  async function notifyCustomerOrderReady(orderId) {
    const context = await customerReadyNotificationContext(orderId);
    if (!context) return false;
    const existing = await database('symbolika_customer_notifications')
      .where({ order: orderId, event_key: 'ready_in_office' })
      .first();
    if (existing?.status === 'sent') return false;
    if (existing?.status === 'sending' && Date.now() - new Date(existing.updated_at).getTime() < 5 * 60 * 1000) return false;

    await recordAutomationRun('customer_notifications', 'Уведомления клиентам', 'running', { order_id: orderId });

    const channel = context.contact.notification_channel;
    const recipient = customerNotificationRecipient(context.contact);
    const subject = `Заказ ${context.order.order_number || `#${orderId}`} готов`;
    const message = await buildCustomerReadyMessage(context);
    const base = {
      customer: context.order.customer || null,
      customer_company: context.order.customer_company || null,
      channel,
      recipient,
      subject,
      message,
      status: 'sending',
      attempts: Number(existing?.attempts || 0) + 1,
      last_error: null,
      updated_at: database.fn.now(),
    };
    if (existing) await database('symbolika_customer_notifications').where({ id: existing.id }).update(base);
    else await database('symbolika_customer_notifications').insert({ order: orderId, event_key: 'ready_in_office', ...base });

    try {
      if (!recipient) throw new Error('Для выбранного канала не указан получатель.');
      const providerMessageId = await dispatchCustomerNotification(channel, recipient, subject, message);
      await database('symbolika_customer_notifications')
        .where({ order: orderId, event_key: 'ready_in_office' })
        .update({
          status: 'sent',
          provider_message_id: providerMessageId,
          sent_at: database.fn.now(),
          updated_at: database.fn.now(),
        });
      await recordAutomationRun('customer_notifications', 'Уведомления клиентам', 'ok', {
        order_id: orderId,
        channel,
      });
      return true;
    } catch (error) {
      await database('symbolika_customer_notifications')
        .where({ order: orderId, event_key: 'ready_in_office' })
        .update({ status: 'failed', last_error: String(error?.message || error).slice(0, 1000), updated_at: database.fn.now() });
      logger.warn({ orderId, channel, error: error?.message || error }, '[Symbolika customer notification] send failed');
      await recordAutomationRun('customer_notifications', 'Уведомления клиентам', 'error', {
        order_id: orderId,
        channel,
      }, error);
      return false;
    }
  }

  async function sendBrowserPush(recipient, subject, message, collection = null, item = null) {
    if (!recipient || !configurePush()) return { status: 'skipped', sent: 0, failed: 0, error: 'Push не настроен на сервере.' };
    if (!await ensurePushTable()) return { status: 'failed', sent: 0, failed: 1, error: 'Таблица push-подписок недоступна.' };

    const subscriptions = await database('symbolika_push_subscriptions')
      .where({ user: recipient })
      .select('id', 'subscription');

    if (!subscriptions.length) return { status: 'skipped', sent: 0, failed: 0, error: 'На устройствах пользователя push не подключён.' };

    const payload = JSON.stringify({
      title: subject,
      body: message || '',
      url: getNotificationUrl(collection, item),
      tag: collection && item != null ? `${collection}:${item}` : undefined,
    });

    let sent = 0;
    let failed = 0;
    let lastError = '';
    for (const row of subscriptions) {
      try {
        await webPush.sendNotification(row.subscription, payload);
        sent += 1;
        await database('symbolika_push_subscriptions')
          .where({ id: row.id })
          .update({ last_error: null, updated_at: database.fn.now() });
      } catch (error) {
        if (error?.statusCode === 404 || error?.statusCode === 410) {
          await database('symbolika_push_subscriptions').where({ id: row.id }).delete();
          failed += 1;
          lastError = 'Push-подписка устройства устарела.';
          continue;
        }

        failed += 1;
        lastError = String(error?.message || error).slice(0, 500);

        await database('symbolika_push_subscriptions')
          .where({ id: row.id })
          .update({
            last_error: String(error?.message || error).slice(0, 500),
            updated_at: database.fn.now(),
          });
        logger.warn(error);
      }
    }
    return {
      status: sent > 0 ? 'sent' : 'failed',
      sent,
      failed,
      error: sent > 0 ? null : lastError || 'Не удалось доставить push.',
    };
  }

  async function saveEmployeeDelivery(notification, user, channel, recipient, result = {}) {
    const status = result.status || 'failed';
    const values = {
      user,
      channel,
      recipient: recipient || null,
      status,
      attempts: 1,
      provider_message_id: result.provider_message_id || null,
      last_error: result.error ? String(result.error).slice(0, 1000) : null,
      sent_at: status === 'sent' ? database.fn.now() : null,
      updated_at: database.fn.now(),
    };
    await database('symbolika_employee_notification_deliveries')
      .insert({ notification, ...values, created_at: database.fn.now() })
      .onConflict(['notification', 'channel'])
      .merge({
        ...values,
        attempts: database.raw('symbolika_employee_notification_deliveries.attempts + 1'),
      });
  }

  async function deliverEmployeeNotification(notification, recipient, subject, message, collection, item) {
    let settings;
    try {
      settings = await database('symbolika_employee_notification_settings as s')
        .rightJoin('directus_users as u', 'u.id', 's.user')
        .where('u.id', recipient)
        .select(
          'u.email as user_email',
          's.push_enabled', 's.email_enabled', 's.vk_enabled', 's.telegram_enabled',
          's.email_address', 's.vk_peer_id', 's.telegram_chat_id',
        )
        .first();
    } catch (error) {
      logger.warn({ recipient, error: error?.message || error }, '[Symbolika employee notification] settings unavailable');
      return;
    }
    if (!settings) return;

    if (settings.push_enabled !== false) {
      try {
        const result = await sendBrowserPush(recipient, subject, message, collection, item);
        await saveEmployeeDelivery(notification, recipient, 'push', null, result);
      } catch (error) {
        await saveEmployeeDelivery(notification, recipient, 'push', null, { status: 'failed', error: error?.message || error });
      }
    }

    const channels = [
      { id: 'email', enabled: settings.email_enabled, target: settings.email_address || settings.user_email },
      { id: 'vk', enabled: settings.vk_enabled, target: settings.vk_peer_id },
      { id: 'telegram', enabled: settings.telegram_enabled, target: settings.telegram_chat_id },
    ];
    const link = getPublicUrl(getNotificationUrl(collection, item));
    const externalMessage = [message, link].filter(Boolean).join('\n\n');
    for (const channel of channels) {
      if (!channel.enabled) continue;
      if (!channel.target) {
        await saveEmployeeDelivery(notification, recipient, channel.id, null, { status: 'failed', error: 'Не указан получатель.' });
        continue;
      }
      try {
        const providerMessageId = await dispatchCustomerNotification(channel.id, channel.target, subject, externalMessage);
        await saveEmployeeDelivery(notification, recipient, channel.id, channel.target, { status: 'sent', provider_message_id: providerMessageId });
      } catch (error) {
        logger.warn({ recipient, channel: channel.id, error: error?.message || error }, '[Symbolika employee notification] send failed');
        await saveEmployeeDelivery(notification, recipient, channel.id, channel.target, { status: 'failed', error: error?.message || error });
      }
    }
  }

  async function employeeTopicEnabled(recipient, topic) {
    if (!recipient || !topic || topic === 'system') return true;
    try {
      const row = await database('symbolika_employee_notification_settings').where('user', recipient).select('topics').first();
      const topics = { ...DEFAULT_NOTIFICATION_TOPICS, ...(row?.topics || {}) };
      return topics[topic] !== false;
    } catch (error) {
      logger.warn({ recipient, topic, error: error?.message || error }, '[Symbolika employee notification] topic settings unavailable');
      return true;
    }
  }

  async function notifyUser(recipient, subject, message, collection = null, item = null, topic = 'system') {
    if (!recipient || !subject) return;
    if (!await employeeTopicEnabled(recipient, topic)) return;

    const inserted = await database('directus_notifications').insert({
      status: 'inbox',
      recipient,
      subject,
      message,
      collection,
      item: item == null ? null : String(item),
    }).returning('id');
    const notificationId = inserted?.[0]?.id ?? inserted?.[0];
    if (notificationId != null) {
      try {
        await deliverEmployeeNotification(notificationId, recipient, subject, message, collection, item);
      } catch (error) {
        logger.warn({ recipient, notificationId, error: error?.message || error }, '[Symbolika employee notification] delivery pipeline failed');
      }
    }
  }

  async function notifyUsers(recipients, subject, message, collection = null, item = null, topic = 'system') {
    const uniqueRecipients = Array.from(new Set((recipients || []).filter(Boolean)));

    for (const recipient of uniqueRecipients) {
      await notifyUser(recipient, subject, message, collection, item, topic);
    }
  }

  async function notifyManager(employeeId, subject, message, collection = null, item = null, topic = 'system') {
    const userId = await getEmployeeUserId(employeeId);
    await notifyUser(userId, subject, message, collection, item, topic);
  }

  async function notifyTaskParticipants(task, prevTask = null) {
    if (!task?.id) return;
    const title = task.title || `Задача #${task.id}`;
    const assigneeChanged = !prevTask || Number(task.assigned_to || 0) !== Number(prevTask.assigned_to || 0);
    if (task.assigned_to && assigneeChanged) {
      await notifyManager(
        task.assigned_to,
        `Новая задача: ${title}`,
        [task.description, task.due_date ? `Срок: ${toDateOnly(task.due_date)}` : ''].filter(Boolean).join('\n'),
        'symbolika_tasks',
        task.id,
        'new_tasks',
      );
    }
    if (prevTask && task.status !== prevTask.status && task.created_by_employee) {
      await notifyManager(
        task.created_by_employee,
        `Изменился статус задачи: ${title}`,
        `Статус: ${prevTask.status || '-'} → ${task.status || '-'}.`,
        'symbolika_tasks',
        task.id,
        'task_updates',
      );
    }
  }

  async function getDesignerEmployeeId() {
    const row = await database('employees as e')
      .join('directus_users as u', 'u.id', 'e.directus_user')
      .join('directus_roles as r', 'r.id', 'u.role')
      .where('r.name', 'Дизайнер')
      .whereNotNull('e.directus_user')
      .orderBy('e.id')
      .select('e.id')
      .first();
    return row?.id || null;
  }

  async function syncDesignerTask(item, prevItem = null) {
    if (!item?.id) return;
    const existing = await database('symbolika_tasks')
      .where({ task_type: 'design', related_order_item: item.id })
      .whereNot({ status: 'cancelled' })
      .orderBy('id', 'desc')
      .first();

    if (!item.needs_designer_help) {
      if (existing && prevItem?.needs_designer_help) {
        await database('symbolika_tasks').where({ id: existing.id }).update({
          status: 'cancelled',
          date_updated: database.fn.now(),
        });
      }
      return;
    }

    const order = await database('orders').where({ id: item.order }).first();
    if (existing) {
      await database('symbolika_tasks').where({ id: existing.id }).update({
        related_order: item.order || null,
        related_customer: order?.customer || null,
        related_company: order?.customer_company || null,
        due_date: item.deadline || order?.deadline || null,
        description: item.designer_comment || null,
        source_url: item.designer_source_url || item.url || null,
        date_updated: database.fn.now(),
      });
      return;
    }

    const [createdTask] = await database('symbolika_tasks').insert({
      title: `Подготовить макет: ${item.product_name || `позиция #${item.id}`}`,
      description: item.designer_comment || null,
      task_type: 'design',
      status: 'new',
      priority: 'normal',
      due_date: item.deadline || order?.deadline || null,
      assigned_to: await getDesignerEmployeeId(),
      created_by_employee: order?.manager_employee || null,
      related_order: item.order || null,
      related_order_item: item.id,
      related_customer: order?.customer || null,
      related_company: order?.customer_company || null,
      source_url: item.designer_source_url || item.url || null,
      result_url: null,
    }).returning('*');
    await notifyTaskParticipants(createdTask);
  }

  async function completeDesignerTask(task, prevTask = null) {
    if (!task || task.task_type !== 'design' || task.status !== 'done' || prevTask?.status === 'done') return;
    const item = task.related_order_item
      ? await database('orders_items').where({ id: task.related_order_item }).first()
      : null;
    if (!item) return;

    if (task.result_url) {
      await database('orders_items').where({ id: item.id }).update({ url: task.result_url });
    }

    const order = await database('orders').where({ id: item.order }).first();
    if (!order?.manager_employee) return;
    const orderLabel = order.order_number || `#${order.id}`;
    await notifyManager(
      order.manager_employee,
      'Макет готов',
      `Дизайнер завершил макет для заказа ${orderLabel}, позиция «${item.product_name || item.id}». Заказ можно запускать в работу.`,
      'orders_items',
      item.id,
      'item_status'
    );
  }

  async function notifyOrderStatusChanged(order, prevOrder) {
    if (!order || !prevOrder) return;
    if (order.order_status === prevOrder.order_status) return;

    const managerUserId = await getEmployeeUserId(order.manager_employee);
    if (!managerUserId) return;

    const orderLabel = order.order_number || `#${order.id}`;
    const prevStatus = await getOrderStatusName(prevOrder.order_status);
    const nextStatus = await getOrderStatusName(order.order_status);

    await notifyUser(
      managerUserId,
      `\u0418\u0437\u043c\u0435\u043d\u0438\u043b\u0441\u044f \u0441\u0442\u0430\u0442\u0443\u0441 \u0437\u0430\u043a\u0430\u0437\u0430 ${orderLabel}`,
      `\u0421\u0442\u0430\u0442\u0443\u0441: ${prevStatus} \u2192 ${nextStatus}.`,
      'orders',
      order.id,
      'order_status'
    );
  }

  async function notifyManagerItemSentToWork(item, prevItem = null) {
    if (!item?.id || !isItemVisibleForWork(item) || isItemVisibleForWork(prevItem)) return;

    const order = item.order
      ? await database('orders').where({ id: item.order }).select('id', 'order_number', 'manager_employee').first()
      : null;
    const managerEmployee = item.manager_employee || order?.manager_employee;
    if (!managerEmployee) return;

    const orderLabel = order?.order_number || (order?.id ? `#${order.id}` : await getOrderLabel(item.order));
    const productName = item.product_name || `#${item.id}`;
    await notifyManager(
      managerEmployee,
      `\u041f\u043e\u0437\u0438\u0446\u0438\u044f \u0437\u0430\u043f\u0443\u0449\u0435\u043d\u0430 \u0432 \u0440\u0430\u0431\u043e\u0442\u0443: ${orderLabel}`,
      `\u041f\u043e\u0437\u0438\u0446\u0438\u044f \u00ab${productName}\u00bb \u043f\u0435\u0440\u0435\u0434\u0430\u043d\u0430 \u0432 \u0440\u0430\u0431\u043e\u0442\u0443.`,
      'orders_items',
      item.id,
      'item_status'
    );
  }

  function contractorMatches(contractorName, pattern) {
    return String(contractorName || '').toLowerCase().includes(pattern);
  }

  function getWorkNotificationTarget(contractorName) {
    if (contractorMatches(contractorName, '\u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432')) {
      return {
        roleName: '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e',
        collection: 'production_work',
        vkChannel: 'production',
      };
    }

    if (contractorMatches(contractorName, '\u0448\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444')) {
      return {
        roleName: '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f',
        collection: 'screen_printing_work',
        vkChannel: 'screen_printing',
      };
    }

    return null;
  }

  async function isOrderVisibleForWork(orderId) {
    if (!orderId) return false;

    const order = await database('orders as o')
      .leftJoin('order_statuses as os', 'os.id', 'o.order_status')
      .where('o.id', orderId)
      .select('os.name as status_name')
      .first();

    return [
      '\u041e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u0432 \u0440\u0430\u0431\u043e\u0442\u0443',
      '\u0412 \u0440\u0430\u0431\u043e\u0442\u0435',
      '\u0413\u043e\u0442\u043e\u0432',
    ].includes(order?.status_name);
  }

  function isItemVisibleForWork(item) {
    const status = String(item?.item_status || '');
    return ['sent_to_work', 'in_work', 'ready'].includes(status);
  }

  async function buildWorkAssignmentMessage(item, target) {
    const orderLabel = await getOrderLabel(item.order);
    const productName = item.product_name || '\u041f\u043e\u0437\u0438\u0446\u0438\u044f';
    const quantity = item.quantity || '-';
    const techTask = item.technical_task_text || '-';
    const layoutUrl = item.url || '-';
    const adminUrl = getPublicUrl(getNotificationUrl(target.collection, item.id));

    return [
      `\u0417\u0430\u043a\u0430\u0437: ${orderLabel}`,
      `\u041f\u043e\u0437\u0438\u0446\u0438\u044f: ${productName}`,
      `\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e: ${quantity}`,
      `\u0422\u0417: ${techTask}`,
      `\u0421\u0441\u044b\u043b\u043a\u0430 \u043d\u0430 \u043c\u0430\u043a\u0435\u0442: ${layoutUrl}`,
      `\u0412 \u0441\u0438\u0441\u0442\u0435\u043c\u0435: ${adminUrl}`,
    ].join('\n');
  }

  async function getItemContractors(item) {
    const ids = [item?.contractor_1, item?.contractor_2].filter(Boolean);
    if (!ids.length) return [];

    return await database('contractors')
      .whereIn('id', ids)
      .select('id', 'name');
  }

  async function markWorkAssignmentNotified(itemId, channel) {
    if (!itemId || !channel) return false;
    if (!await ensureWorkNotificationTable()) return false;

    try {
      await database('symbolika_work_assignment_notifications')
        .insert({ item: itemId, channel });
      return true;
    } catch (error) {
      if (error?.code === '23505') return false;
      logger.warn(error);
      return false;
    }
  }

  async function notifyWorkAssignment(item, target) {
    if (!item?.id || !target) return;
    if (!isItemVisibleForWork(item) && !await isOrderVisibleForWork(item.order)) return;

    const shouldNotify = await markWorkAssignmentNotified(item.id, target.vkChannel);
    if (!shouldNotify) return;

    const recipients = await getRoleUserIds(target.roleName);
    const orderLabel = await getOrderLabel(item.order);
    const message = await buildWorkAssignmentMessage(item, target);
    const subject = `\u041d\u043e\u0432\u044b\u0439 \u0437\u0430\u043a\u0430\u0437 \u0434\u043b\u044f ${target.roleName}: ${orderLabel}`;

    await notifyUsers(
      recipients,
      subject,
      message,
      target.collection,
      item.id,
      'production'
    );

    const vkSent = await sendVkMessage(
      target.vkChannel,
      `${subject}\n\n${message}`
    );

    // The marker is a delivery lock. If VK rejected the message, remove it so
    // the next synchronization can retry instead of silently losing the task.
    if (!vkSent) {
      await database('symbolika_work_assignment_notifications')
        .where({ item: item.id, channel: target.vkChannel })
        .delete();
    }
  }

  async function notifyNewProductionAssignments(item, prevItem = null) {
    if (!item?.id) return;

    const contractors = await getItemContractors(item);
    if (!contractors.length) return;

    for (const contractor of contractors) {
      const target = getWorkNotificationTarget(contractor.name);
      if (!target) continue;

      await notifyWorkAssignment(item, target);
    }
  }

  async function notifyWorkAssignmentsForOrder(orderId) {
    if (!orderId || !await isOrderVisibleForWork(orderId)) return;

    const items = await database('orders_items')
      .where({ order: orderId })
      .select('*');

    for (const item of items) {
      await syncDesignerTask(item);
      await notifyNewProductionAssignments(item);
    }
  }

  async function notifyWorkAssignmentFromCollection(collection, key) {
    const targets = {
      production_work: {
        roleName: '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e',
        collection: 'production_work',
        vkChannel: 'production',
      },
      screen_printing_work: {
        roleName: '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f',
        collection: 'screen_printing_work',
        vkChannel: 'screen_printing',
      },
    };

    const target = targets[collection];
    if (!target || !key) return;

    const item = await database('orders_items').where({ id: key }).first();
    await notifyWorkAssignment(item, target);
  }

  async function notifyLayoutRevisionIfNeeded(item, prevItem = null) {
    if (!item?.id || !item.manager_employee) return;
    if (item.production_status === prevItem?.production_status) return;

    const nextStatus = await getProductionStatusName(item.production_status);
    if (nextStatus !== '\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430') return;

    const orderLabel = await getOrderLabel(item.order);
    const productName = item.product_name || '\u041f\u043e\u0437\u0438\u0446\u0438\u044f';

    await notifyManager(
      item.manager_employee,
      `\u041d\u0443\u0436\u043d\u0430 \u0434\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430`,
      `${orderLabel}: ${productName}. \u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e \u043f\u043e\u043c\u0435\u0442\u0438\u043b\u043e \u0441\u0442\u0430\u0442\u0443\u0441 "\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430".`,
      'orders_items',
      item.id,
      'item_status'
    );
  }

  async function getManagerPercent(orderId) {
    if (!orderId) return 0;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order?.commission_manager_employee) return 0;

    const emp = await database('employees').where({ id: order.commission_manager_employee }).first();
    return num(emp?.order_percent);
  }

  async function getTaxPercent(orderId) {
    if (!orderId) return 0;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order?.payment_type) return 0;

    const pt = await database('payment_types').where({ id: order.payment_type }).first();
    return num(pt?.tax_percent);
  }

  async function assignManagerToCustomerAndCompany(order) {
    if (!order?.manager_employee) return;

    if (order.customer) {
      const customer = await database('customers').where({ id: order.customer }).first();

      if (customer && !customer.manager) {
        await database('customers').where({ id: order.customer }).update({
          manager: order.manager_employee,
        });
      }
    }

    if (order.customer_company) {
      const company = await database('customer_companies').where({ id: order.customer_company }).first();

      if (company && !company.manager) {
        await database('customer_companies').where({ id: order.customer_company }).update({
          manager: order.manager_employee,
        });
      }
    }
  }

  async function ensureCustomerCompanyLink(order) {
    if (!order?.customer || !order?.customer_company) return;

    const exists = await database('customer_company_links')
      .where({
        customer: order.customer,
        customer_companies: order.customer_company,
      })
      .first();

    if (exists) return;

    const defaultLink = await database('customer_company_links')
      .where({
        customer: order.customer,
        is_default: true,
      })
      .first();

    await database('customer_company_links').insert({
      customer: order.customer,
      customer_companies: order.customer_company,
      is_default: defaultLink ? false : true,
    });

    const customer = await database('customers').where({ id: order.customer }).first();
    if (customer && !customer.company) {
      await database('customers').where({ id: order.customer }).update({
        company: order.customer_company,
      });
    }
  }

  async function recalcCustomerBalance(customerId) {
    if (!customerId) return;

    const orders = await database('orders')
      .where({ customer: customerId })
      .whereNull('customer_company');

    const payments = await database('order_payments')
      .where({ customer: customerId })
      .whereNull('customer_company');

    const orders_total_sum = round(orders.reduce((s, x) => s + num(x.order_sum), 0));

    const payments_total_in = round(
      payments
        .filter((x) => x.payment_direction !== 'outgoing_refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const refunds_total_out = round(
      payments
        .filter((x) => x.payment_direction === 'outgoing_refund' || x.allocation_mode === 'refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const operations = await database('customer_operations')
      .where({ customer: customerId, status: 'confirmed' })
      .whereNull('customer_company');

    const operation_charges = round(
      operations
        .filter((x) => x.direction === 'customer_owes_us')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const operation_credits = round(
      operations
        .filter((x) => x.direction === 'we_owe_customer')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_in - refunds_total_out - orders_total_sum - operation_charges + operation_credits);

    await database('customers').where({ id: customerId }).update({
      orders_total_sum,
      payments_total_in,
      refunds_total_out,
      balance,
      debt_to_us: balance < 0 ? Math.abs(balance) : 0,
      our_debt_to_customer: balance > 0 ? balance : 0,
    });
  }

  async function recalcCompanyBalance(companyId) {
    if (!companyId) return;

    const orders = await database('orders')
      .where({ customer_company: companyId });

    const payments = await database('order_payments')
      .where({ customer_company: companyId });

    const orders_total_sum = round(orders.reduce((s, x) => s + num(x.order_sum), 0));

    const payments_total_in = round(
      payments
        .filter((x) => x.payment_direction !== 'outgoing_refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const refunds_total_out = round(
      payments
        .filter((x) => x.payment_direction === 'outgoing_refund' || x.allocation_mode === 'refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const operations = await database('customer_operations')
      .where({ customer_company: companyId, status: 'confirmed' });

    const operation_charges = round(
      operations
        .filter((x) => x.direction === 'customer_owes_us')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const operation_credits = round(
      operations
        .filter((x) => x.direction === 'we_owe_customer')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_in - refunds_total_out - orders_total_sum - operation_charges + operation_credits);

    await database('customer_companies').where({ id: companyId }).update({
      orders_total_sum,
      payments_total_in,
      refunds_total_out,
      balance,
      debt_to_us: balance < 0 ? Math.abs(balance) : 0,
      our_debt_to_customer: balance > 0 ? balance : 0,
    });
  }

  async function recalcOrderParties(order, prevOrder = null) {
    if (prevOrder) {
      await recalcCustomerBalance(prevOrder.customer);
      await recalcCompanyBalance(prevOrder.customer_company);
    }

    if (order) {
      await recalcCustomerBalance(order.customer);
      await recalcCompanyBalance(order.customer_company);
    }
  }

  async function syncPaymentsFromOrder(orderId) {
    if (!orderId) return;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order) return;

    await database('order_payments')
      .where({ order: orderId })
      .update({
        customer: order.customer || null,
        customer_company: order.customer_company || null,
      });
  }

  async function recalcContractorBalance(contractorId) {
    if (!contractorId) return;

    const itemsAsFirst = await database('orders_items')
      .where({ contractor_1: contractorId });

    const itemsAsSecond = await database('orders_items')
      .where({ contractor_2: contractorId });

    const contractor1Cost = itemsAsFirst.reduce((s, x) => {
      return s + num(x.contractor_1_cost) * num(x.quantity);
    }, 0);

    const contractor2Cost = itemsAsSecond.reduce((s, x) => {
      return s + num(x.contractor_2_cost) * num(x.quantity);
    }, 0);

    const items_total_cost = round(contractor1Cost + contractor2Cost);

    const payments = await database('contractor_payments')
      .where({ contractor: contractorId });

    const payments_total_out = round(
      payments.reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_out - items_total_cost);

    await database('contractors').where({ id: contractorId }).update({
      items_total_cost,
      payments_total_out,
      balance,
      debt_to_contractor: balance < 0 ? Math.abs(balance) : 0,
      contractor_debt_to_us: balance > 0 ? balance : 0,
    });
  }

  async function recalcContractorsFromItem(item, prevItem = null) {
    const ids = new Set();

    if (item?.contractor_1) ids.add(item.contractor_1);
    if (item?.contractor_2) ids.add(item.contractor_2);
    if (prevItem?.contractor_1) ids.add(prevItem.contractor_1);
    if (prevItem?.contractor_2) ids.add(prevItem.contractor_2);

    for (const id of ids) {
      await recalcContractorBalance(id);
    }
  }

  async function syncItemsShippingFromOrder(orderId) {
    if (!orderId) return;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order) return;

    await database('orders_items')
      .where({ order: orderId })
      .update({
        shipping_method: order.shipping_method || null,
        office_status: NOT_IN_OFFICE,
      });
  }

  async function syncItemDeadlinesFromOrder(orderId, prevDeadline, nextDeadline) {
    if (!orderId) return;

    const nextDate = toDateOnly(nextDeadline);
    const prevDate = toDateOnly(prevDeadline);

    if (nextDate === prevDate) return;

    const query = database('orders_items').where({ order: orderId });

    if (prevDate) {
      query.andWhere((builder) => {
        builder.whereNull('deadline').orWhereRaw('deadline::date = ?', [prevDate]);
      });
    } else {
      query.whereNull('deadline');
    }

    await query.update({ deadline: nextDate });
  }

  async function setAllItemsOfficeStatus(orderId, officeStatus) {
    if (!orderId || !officeStatus) return;

    const readyProductionStatus = ['in_office', 'issued'].includes(officeStatus)
      ? await getReadyProductionStatusId()
      : null;

    await database('orders_items')
      .where({ order: orderId })
      .update({
        office_status: officeStatus,
        shipping_method: officeStatus === NOT_IN_OFFICE ? null : OFFICE_PICKUP,
        ...(readyProductionStatus ? { production_status: readyProductionStatus } : {}),
        ...(officeStatus === ISSUED ? { item_status: 'delivered' } : {}),
        ...(officeStatus === IN_OFFICE ? { item_status: 'ready' } : {}),
      });
  }

  async function recalcOfficeStatus(orderId) {
    if (!orderId) return;

    const items = await database('orders_items').where({ order: orderId });
    if (!items.length) return;

    const allIssued = items.every((item) => item.office_status === ISSUED);
    const allInOffice = items.every((item) => item.office_status === IN_OFFICE || item.office_status === ISSUED);
    const hasNotInOffice = items.some((item) => !item.office_status || item.office_status === NOT_IN_OFFICE);

    const update = {};

    if (allIssued) {
      update.office_status = ISSUED;

      const deliveredId = await getDeliveredStatusId();
      if (deliveredId) update.order_status = deliveredId;
    } else if (hasNotInOffice) {
      update.office_status = NOT_IN_OFFICE;
    } else if (allInOffice) {
      update.office_status = IN_OFFICE;
    } else {
      update.office_status = NOT_IN_OFFICE;
    }

    const order = await database('orders').where({ id: orderId }).first();
    const deliveredId = await getDeliveredStatusId();

    if (update.office_status !== ISSUED && deliveredId && order?.order_status === deliveredId) {
      const readyId = await getReadyStatusId();
      if (readyId) update.order_status = readyId;
    }

    await database('orders').where({ id: orderId }).update(update);
  }

  async function recalcItem(id, prevItem = null) {
    const item = await database('orders_items').where({ id }).first();
    if (!item) return null;

    const order = item.order
      ? await database('orders').where({ id: item.order }).first()
      : null;

    const manager_employee = order?.manager_employee || null;
    const commission_manager_employee = order?.commission_manager_employee || null;

    let manager_percent = await getManagerPercent(item.order);
    let tax_percent = item.tax_percent;

    if (isEmpty(tax_percent) || num(tax_percent) === 0) {
      tax_percent = await getTaxPercent(item.order);
    }

    let shipping_method = item.shipping_method;
    let office_status = item.office_status;

    if (!shipping_method && order?.shipping_method) {
      shipping_method = order.shipping_method;
    }

    if (!office_status) {
      office_status = NOT_IN_OFFICE;
    }

    const quantity = num(item.quantity);
    const price = num(item.price_per_unit);

    const contractor_1_cost = await normalizedContractorCost(item.contractor_1, item.contractor_1_cost);
    const contractor_2_cost = await normalizedContractorCost(item.contractor_2, item.contractor_2_cost);

    const unit_cost = round(contractor_1_cost + contractor_2_cost);
    const total_cost = round(unit_cost * quantity);

    const order_sum = round(quantity * price);
    const manager_commission_sum = round(order_sum * num(manager_percent) / 100);
    const tax_sum = round(order_sum * num(tax_percent) / 100);

    const profit_sum = round(order_sum - total_cost - manager_commission_sum - tax_sum);
    const margin_percent = order_sum > 0 ? round(profit_sum / order_sum * 100) : 0;

    await database('orders_items').where({ id }).update({
      manager_employee,
      commission_manager_employee,
      manager_percent,
      tax_percent,
      shipping_method,
      office_status,
      contractor_1_cost,
      contractor_2_cost,
      unit_cost,
      order_sum,
      total_cost,
      manager_commission_sum,
      tax_sum,
      profit_sum,
      margin_percent,
    });

    const updatedItem = await database('orders_items').where({ id }).first();
    await recalcContractorsFromItem(updatedItem, prevItem);

    return item.order;
  }

  async function recalcOrder(orderId, prevOrder = null) {
    if (!orderId) return;

    const items = await database('orders_items').where({ order: orderId });

    const order_sum = round(items.reduce((s, x) => s + num(x.order_sum), 0));
    const items_total_cost = round(items.reduce((s, x) => s + num(x.total_cost), 0));
    const items_manager_commission_sum = round(items.reduce((s, x) => s + num(x.manager_commission_sum), 0));
    const items_tax_sum = round(items.reduce((s, x) => s + num(x.tax_sum), 0));

    const profit_sum = round(order_sum - items_total_cost - items_manager_commission_sum - items_tax_sum);
    const margin_percent = order_sum > 0 ? round(profit_sum / order_sum * 100) : 0;

    const allocations = await database('payment_allocations').where({ order: orderId });
    const paid_amount = round(allocations.reduce((s, x) => s + num(x.amount), 0));
    const payment_due = round(order_sum - paid_amount);

    const order = await database('orders').where({ id: orderId }).first();

    await database('orders').where({ id: orderId }).update({
      order_sum,
      items_total_cost,
      items_manager_commission_sum,
      items_tax_sum,
      profit_sum,
      margin_percent,
      paid_amount,
      payment_due,
      office_payment_due: order?.payment_on_receipt ? payment_due : 0,
    });

    const updatedOrder = await database('orders').where({ id: orderId }).first();

    await recalcOfficeStatus(orderId);
    await syncPaymentsFromOrder(orderId);
    await recalcOrderParties(updatedOrder, prevOrder);
  }

  async function recalcPayment(paymentId, prevPayment = null) {
    if (!paymentId) return;

    const payment = await database('order_payments').where({ id: paymentId }).first();
    if (!payment) return;

    const rows = await database('payment_allocations').where({ payment: paymentId });
    const allocated_amount = round(rows.reduce((s, x) => s + num(x.amount), 0));

    await database('order_payments').where({ id: paymentId }).update({
      allocated_amount,
      unallocated_amount: round(num(payment.amount) - allocated_amount),
    });

    const updatedPayment = await database('order_payments').where({ id: paymentId }).first();

    if (prevPayment) {
      await recalcCustomerBalance(prevPayment.customer);
      await recalcCompanyBalance(prevPayment.customer_company);
    }

    await recalcCustomerBalance(updatedPayment.customer);
    await recalcCompanyBalance(updatedPayment.customer_company);
  }

  // BEFORE CREATE CUSTOMER / COMPANY
  filter('items.create', async (payload, meta, context) => {
    if (!['customers', 'customer_companies'].includes(meta.collection)) return payload;

    const next = { ...payload };
    const userId = context?.accountability?.user || meta?.accountability?.user;

    if (userId) {
      const actor = await getEmployeeActorByUser(userId);
      const canAssignAnotherManager = ['Administrator', '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439'].includes(actor?.role_name);
      if (actor?.id && (!canAssignAnotherManager || !next.manager)) next.manager = actor.id;
    }

    return next;
  });

  // BEFORE CREATE ORDER
  filter('items.create', async (payload, meta, context) => {
    if (meta.collection !== 'orders') return payload;

    const next = { ...payload };
    const userId = context?.accountability?.user || meta?.accountability?.user;

    if (!next.order_number) {
      next.order_number = await generateOrderNumber();
    }

    if (userId) {
      const actor = await getEmployeeActorByUser(userId);
      const canAssignAnotherManager = ['Administrator', '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439'].includes(actor?.role_name);
      if (actor?.id && (!canAssignAnotherManager || !next.manager_employee)) {
        next.manager_employee = actor.id;
      }
    }

    if (!next.office_status) {
      next.office_status = NOT_IN_OFFICE;
    }

    return next;
  });

  // BEFORE CREATE ORDER ITEM
  filter('items.create', async (payload, meta, context) => {
    if (meta.collection === 'customer_operations') {
      const next = { ...payload };
      if (!next.manager_employee) {
        const employee = await getEmployeeByUser(meta?.accountability?.user);
        if (employee?.id) next.manager_employee = employee.id;
      }
      return next;
    }

    if (meta.collection !== 'orders_items') return payload;

    const next = { ...payload };
    const userId = context?.accountability?.user || meta?.accountability?.user;

    if (next.order && userId) {
      const actor = await getEmployeeActorByUser(userId);
      const canCreateForAnotherManager = ['Administrator', '\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0449\u0438\u0439'].includes(actor?.role_name);
      if (actor?.id && !canCreateForAnotherManager) {
        const targetOrder = await database('orders').where({ id: next.order }).select('manager_employee').first();
        if (!targetOrder || Number(targetOrder.manager_employee) !== Number(actor.id)) {
          throw new Error('\u041f\u043e\u0437\u0438\u0446\u0438\u044e \u043c\u043e\u0436\u043d\u043e \u0434\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0442\u043e\u043b\u044c\u043a\u043e \u0432 \u0441\u0432\u043e\u0439 \u0437\u0430\u043a\u0430\u0437.');
        }
      }
    }

    if (isEmpty(next.deadline) && next.order) {
      const order = await database('orders')
        .where({ id: next.order })
        .first();

      if (!isEmpty(order?.deadline)) {
        next.deadline = toDateOnly(order.deadline);
      }
    }

    return next;
  });

  // CAPTURE OLD VALUES BEFORE UPDATE
  filter('items.update', async (payload, meta) => {
    const keys = meta?.keys || [];

    if (meta.collection === 'orders') {
      for (const id of keys) {
        const row = await database('orders').where({ id }).first();
        if (row) prevOrders.set(String(id), row);
      }
    }

    if (['orders_items', 'contractor_costing'].includes(meta.collection)) {
      for (const id of keys) {
        const row = await database('orders_items').where({ id }).first();
        if (row) prevItems.set(String(id), row);
      }
    }

    if (meta.collection === 'order_payments') {
      for (const id of keys) {
        const row = await database('order_payments').where({ id }).first();
        if (row) prevPayments.set(String(id), row);
      }
    }

    if (meta.collection === 'contractor_payments') {
      for (const id of keys) {
        const row = await database('contractor_payments').where({ id }).first();
        if (row) prevContractorPayments.set(String(id), row);
      }
    }

    if (meta.collection === 'symbolika_tasks') {
      for (const id of keys) {
        const row = await database('symbolika_tasks').where({ id }).first();
        if (row) prevTasks.set(String(id), row);
      }
    }

    return payload;
  });

  // AFTER CREATE ORDER
  action('items.create', async (meta, context) => {
    try {
      const { collection, key } = meta;
      if (collection !== 'orders') return;

      const order = await database('orders').where({ id: key }).first();
      if (!order) return;

      const userId = context?.accountability?.user || meta?.accountability?.user;
      const update = {};

      if (!order.order_number) {
        update.order_number = await generateOrderNumber();
      }

      if (!order.manager_employee && userId) {
        const emp = await getEmployeeByUser(userId);
        if (emp?.id) update.manager_employee = emp.id;
      }

      if (!order.office_status) {
        update.office_status = NOT_IN_OFFICE;
      }

      if (Object.keys(update).length) {
        await database('orders').where({ id: key }).update(update);
      }

      let updatedOrder = await database('orders').where({ id: key }).first();
      const commissionManager = await getCommissionManagerByUser(userId);

      if (
        !updatedOrder.commission_manager_employee
        && commissionManager?.id
        && Number(updatedOrder.manager_employee) === Number(commissionManager.id)
      ) {
        await database('orders').where({ id: key }).update({
          commission_manager_employee: commissionManager.id,
        });
        updatedOrder = await database('orders').where({ id: key }).first();
      }

      await assignManagerToCustomerAndCompany(updatedOrder);
      await ensureCustomerCompanyLink(updatedOrder);
      await syncItemsShippingFromOrder(key);
      await syncPaymentsFromOrder(key);
      await recalcOrder(key);
      await notifyCustomerOrderReady(key);
    } catch (error) {
      logger.error(error);
    }
  });

  // UPDATE ORDER
  action('items.update', async ({ collection, keys, payload }, context) => {
    try {
      if (collection !== 'orders') return;

      for (const orderId of keys) {
        const prevOrder = prevOrders.get(String(orderId)) || null;
        prevOrders.delete(String(orderId));
        await storeEventBeforeDelta(collection, orderId, prevOrder, context?.accountability?.user);

        const order = await database('orders').where({ id: orderId }).first();

        await assignManagerToCustomerAndCompany(order);
        await ensureCustomerCompanyLink(order);

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'shipping_method')) {
          await syncItemsShippingFromOrder(orderId);
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'deadline')) {
          await syncItemDeadlinesFromOrder(orderId, prevOrder?.deadline, order?.deadline);
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'office_status')) {
          if (payload.office_status === IN_OFFICE) {
            await setAllItemsOfficeStatus(orderId, IN_OFFICE);
          }

          if (payload.office_status === ISSUED) {
            await setAllItemsOfficeStatus(orderId, ISSUED);

            const deliveredId = await getDeliveredStatusId();
            if (deliveredId) {
              await database('orders').where({ id: orderId }).update({
                order_status: deliveredId,
              });
            }
          }

          if (payload.office_status === NOT_IN_OFFICE) {
            await setAllItemsOfficeStatus(orderId, NOT_IN_OFFICE);
          }
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'order_status')) {
          const deliveredId = await getDeliveredStatusId();

          if (deliveredId && Number(payload.order_status) === Number(deliveredId)) {
            await setAllItemsOfficeStatus(orderId, ISSUED);
            await database('orders').where({ id: orderId }).update({
              office_status: ISSUED,
            });
          }
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'payment_type')) {
          const items = await database('orders_items').where({ order: orderId });

          for (const item of items) {
            await database('orders_items').where({ id: item.id }).update({
              tax_percent: null,
            });

            await recalcItem(item.id);
          }
        }

      await syncPaymentsFromOrder(orderId);
      await recalcOrder(orderId, prevOrder);

      const updatedOrder = await database('orders').where({ id: orderId }).first();
      await notifyOrderStatusChanged(updatedOrder, prevOrder);
      await notifyWorkAssignmentsForOrder(orderId);
      await recalcOrderParties(updatedOrder, prevOrder);
      await notifyCustomerOrderReady(orderId);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER ITEMS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'orders_items') return;

      const orderId = await recalcItem(key);
      const item = await database('orders_items').where({ id: key }).first();
      const orderBeforeRecalc = orderId
        ? await database('orders').where({ id: orderId }).first()
        : null;
      await syncDesignerTask(item);
      await notifyNewProductionAssignments(item);
      await notifyLayoutRevisionIfNeeded(item);
      await recalcOrder(orderId);
      const orderAfterRecalc = orderId
        ? await database('orders').where({ id: orderId }).first()
        : null;
      const orderStatusChanged = String(orderBeforeRecalc?.order_status || '') !== String(orderAfterRecalc?.order_status || '');
      await notifyOrderStatusChanged(orderAfterRecalc, orderBeforeRecalc);
      if (!orderStatusChanged) await notifyManagerItemSentToWork(item);
      await notifyCustomerOrderReady(orderId);
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER ITEMS UPDATE
  action('items.update', async ({ collection, keys }, context) => {
    try {
      if (!['orders_items', 'contractor_costing'].includes(collection)) return;

      for (const key of keys) {
        const prevItem = prevItems.get(String(key)) || null;
        prevItems.delete(String(key));
        if (collection === 'orders_items') {
          await storeEventBeforeDelta(collection, key, prevItem, context?.accountability?.user);
        }

        const orderId = await recalcItem(key, prevItem);
        const item = await database('orders_items').where({ id: key }).first();
        const orderBeforeRecalc = orderId
          ? await database('orders').where({ id: orderId }).first()
          : null;
        await syncDesignerTask(item, prevItem);
        await notifyNewProductionAssignments(item, prevItem);
        await notifyLayoutRevisionIfNeeded(item, prevItem);
        await recalcOrder(orderId);
        const orderAfterRecalc = orderId
          ? await database('orders').where({ id: orderId }).first()
          : null;
        const orderStatusChanged = String(orderBeforeRecalc?.order_status || '') !== String(orderAfterRecalc?.order_status || '');
        await notifyOrderStatusChanged(orderAfterRecalc, orderBeforeRecalc);
        if (!orderStatusChanged) await notifyManagerItemSentToWork(item, prevItem);
        await notifyCustomerOrderReady(orderId);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // OFFICE WORKING TABLES UPDATE
  // These collections synchronize the underlying order through PostgreSQL triggers,
  // so their updates do not always emit a separate Directus `orders` action.
  action('items.update', async ({ collection, keys }) => {
    try {
      if (!['office_issue', 'office_issue_items', 'office_items_in_office'].includes(collection)) return;

      const orderIds = new Set();
      for (const key of keys) {
        if (collection === 'office_issue') {
          orderIds.add(Number(key));
          continue;
        }

        const row = await database(collection).where({ id: key }).first();
        const orderId = row?.order || row?.office_issue;
        if (orderId) orderIds.add(Number(orderId));
      }

      for (const orderId of orderIds) {
        await notifyCustomerOrderReady(orderId);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // If the preferred channel is configured after the order has already reached
  // the office, retry the one permitted customer notification immediately.
  action('items.update', async ({ collection, keys, payload }) => {
    try {
      if (!['customers', 'customer_companies'].includes(collection)) return;
      const notificationFields = ['notification_channel', 'email', 'phone', 'telegram_chat_id', 'vk_peer_id'];
      if (!notificationFields.some((field) => Object.prototype.hasOwnProperty.call(payload || {}, field))) return;

      for (const key of keys) {
        const query = database('orders')
          .where(collection === 'customers' ? { customer: key } : { customer_company: key })
          .select('id');
        const orders = await query;
        for (const order of orders) {
          await notifyCustomerOrderReady(order.id);
        }
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // TASK NOTIFICATIONS
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'symbolika_tasks') return;
      const task = await database('symbolika_tasks').where({ id: key }).first();
      await notifyTaskParticipants(task);
    } catch (error) {
      logger.error(error);
    }
  });

  // DESIGN TASKS UPDATE
  action('items.update', async ({ collection, keys }, context) => {
    try {
      if (collection !== 'symbolika_tasks') return;
      for (const key of keys) {
        const prevTask = prevTasks.get(String(key)) || null;
        prevTasks.delete(String(key));
        await storeEventBeforeDelta(collection, key, prevTask, context?.accountability?.user);
        const task = await database('symbolika_tasks').where({ id: key }).first();
        await notifyTaskParticipants(task, prevTask);
        await completeDesignerTask(task, prevTask);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // WORK VIEW ASSIGNMENTS
  action('items.create', async ({ collection, key }) => {
    try {
      if (!['production_work', 'screen_printing_work'].includes(collection)) return;
      await notifyWorkAssignmentFromCollection(collection, key);
    } catch (error) {
      logger.error(error);
    }
  });

  action('items.update', async ({ collection, keys }) => {
    try {
      if (!['production_work', 'screen_printing_work'].includes(collection)) return;

      for (const key of keys) {
        await notifyWorkAssignmentFromCollection(collection, key);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER PAYMENTS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'order_payments') return;

      const payment = await database('order_payments').where({ id: key }).first();
      if (!payment) return;

      if (payment.order) {
        const order = await database('orders').where({ id: payment.order }).first();

        await database('order_payments').where({ id: key }).update({
          customer: payment.customer || order?.customer || null,
          customer_company: payment.customer_company || order?.customer_company || null,
        });
      }

      const updatedPayment = await database('order_payments').where({ id: key }).first();

      if (updatedPayment.order && updatedPayment.allocation_mode === 'to_order' && num(updatedPayment.amount) > 0) {
        const exists = await database('payment_allocations')
          .where({ payment: key, order: updatedPayment.order })
          .first();

        if (!exists) {
          await database('payment_allocations').insert({
            payment: key,
            order: updatedPayment.order,
            amount: updatedPayment.amount,
            comment: '\u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u043e\u0435 \u0440\u0430\u0441\u043f\u0440\u0435\u0434\u0435\u043b\u0435\u043d\u0438\u0435',
          });
        }

        await recalcPayment(key);
        await recalcOrder(updatedPayment.order);
      } else {
        await recalcPayment(key);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER PAYMENTS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection === 'symbolika_customer_notifications') {
        for (const key of keys) {
          const notification = await database('symbolika_customer_notifications').where({ id: key }).first();
          if (notification?.status === 'retry_requested' && notification.order) {
            await notifyCustomerOrderReady(notification.order);
          }
        }
        return;
      }

      if (collection !== 'order_payments') return;

      for (const key of keys) {
        const prevPayment = prevPayments.get(String(key)) || null;
        prevPayments.delete(String(key));

        const payment = await database('order_payments').where({ id: key }).first();

        if (payment?.order) {
          const order = await database('orders').where({ id: payment.order }).first();

          await database('order_payments').where({ id: key }).update({
            customer: order?.customer || null,
            customer_company: order?.customer_company || null,
          });
        }

        await recalcPayment(key, prevPayment);

        const updatedPayment = await database('order_payments').where({ id: key }).first();
        if (updatedPayment?.order) {
          await recalcOrder(updatedPayment.order);
        }

        if (prevPayment?.order && prevPayment.order !== updatedPayment?.order) {
          await recalcOrder(prevPayment.order);
        }
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // PAYMENT ALLOCATIONS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'payment_allocations') return;

      const allocation = await database('payment_allocations').where({ id: key }).first();
      if (!allocation) return;

      await recalcPayment(allocation.payment);
      await recalcOrder(allocation.order);
    } catch (error) {
      logger.error(error);
    }
  });

  // PAYMENT ALLOCATIONS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'payment_allocations') return;

      for (const key of keys) {
        const allocation = await database('payment_allocations').where({ id: key }).first();
        if (!allocation) continue;

        await recalcPayment(allocation.payment);
        await recalcOrder(allocation.order);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // CONTRACTOR PAYMENTS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'contractor_payments') return;

      const payment = await database('contractor_payments').where({ id: key }).first();
      if (!payment) return;

      await recalcContractorBalance(payment.contractor);
    } catch (error) {
      logger.error(error);
    }
  });

  // CONTRACTOR PAYMENTS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'contractor_payments') return;

      for (const key of keys) {
        const prevPayment = prevContractorPayments.get(String(key)) || null;
        prevContractorPayments.delete(String(key));

        const payment = await database('contractor_payments').where({ id: key }).first();

        if (prevPayment?.contractor) {
          await recalcContractorBalance(prevPayment.contractor);
        }

        if (payment?.contractor) {
          await recalcContractorBalance(payment.contractor);
        }
      }
    } catch (error) {
      logger.error(error);
    }
  });
};


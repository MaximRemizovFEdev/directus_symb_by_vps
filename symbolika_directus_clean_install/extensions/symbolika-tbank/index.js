import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { request as httpsRequest } from 'node:https';
import { rootCertificates } from 'node:tls';

const INIT_API_URL = 'https://securepay.tinkoff.ru/v2/Init';
const GET_QR_API_URL = 'https://securepay.tinkoff.ru/v2/GetQr';
const RUSSIAN_TRUSTED_CA = readFileSync(new URL('../../setup/certs/russian-trusted-ca-bundle.pem', import.meta.url), 'utf8');

function apiError(message, status = 500) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function numberValue(value) {
  const number = Number(String(value ?? '').replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(number) ? number : 0;
}

function roundMoney(value) {
  return Math.round((numberValue(value) + Number.EPSILON) * 100) / 100;
}

function receiptContact(order) {
  const customer = order?.customer || {};
  const email = String(customer.email || '').trim().toLowerCase();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 64) return { Email: email };
  const digits = String(customer.phone || '').replace(/\D/g, '');
  const normalizedDigits = digits.length === 11 && digits.startsWith('8') ? `7${digits.slice(1)}` : digits;
  if (normalizedDigits.length >= 10 && normalizedDigits.length <= 15) return { Phone: `+${normalizedDigits}` };
  return null;
}

function receiptContactFromInput(type, value) {
  const normalizedType = String(type || '').trim().toLowerCase();
  const rawValue = String(value || '').trim();
  if (!rawValue) return null;
  if (normalizedType === 'email') {
    const email = rawValue.toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 64 ? { Email: email } : null;
  }
  if (normalizedType === 'phone') {
    const digits = rawValue.replace(/\D/g, '');
    const normalizedDigits = digits.length === 11 && digits.startsWith('8') ? `7${digits.slice(1)}` : digits;
    return normalizedDigits.length >= 10 && normalizedDigits.length <= 15 ? { Phone: `+${normalizedDigits}` } : null;
  }
  return null;
}

function buildReceipt(preview, contact) {
  const Items = preview.items.map((item) => ({
    Name: item.name.slice(0, 128),
    Price: Math.round(item.price * 100),
    Quantity: item.amount,
    Amount: Math.round(item.price * item.amount * 100),
    Tax: 'none',
    PaymentMethod: 'full_payment',
    PaymentObject: 'commodity',
  }));
  return { ...contact, Taxation: 'usn_income', Items };
}

function dateOnly(value) {
  const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function moscowDate(offsetDays = 0) {
  const now = new Date(Date.now() + offsetDays * 86400000);
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Moscow',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

function invoiceNumber(value, fallback = Date.now()) {
  const preferred = String(value || '').replace(/\D/g, '').slice(0, 15);
  if (preferred) return preferred;
  const fallbackDigits = String(fallback || '').replace(/\D/g, '').slice(0, 15);
  return fallbackDigits || String(Date.now()).slice(-15);
}

function activeInvoiceItems(items = []) {
  return items
    .filter((item) => String(item?.item_status || '').trim().toLowerCase() !== 'cancelled')
    .map((item) => ({
      id: Number(item.id),
      name: String(item.product_name || '').trim().slice(0, 1000),
      price: roundMoney(item.price_per_unit),
      amount: numberValue(item.quantity),
      unit: 'шт',
      vat: 'None',
    }))
    .filter((item) => item.name && item.price >= 0 && item.amount > 0);
}

export function buildInvoicePreview(order, items, options = {}) {
  const invoiceItems = activeInvoiceItems(items);
  const today = options.today || moscowDate();
  const defaultDueDate = options.defaultDueDate || moscowDate(7);
  const orderDeadline = dateOnly(order?.deadline);
  const company = order?.customer_company || {};
  const customer = order?.customer || {};
  const dueDate = orderDeadline && orderDeadline >= today ? orderDeadline : defaultDueDate;
  const total = roundMoney(invoiceItems.reduce((sum, item) => sum + item.price * item.amount, 0));
  const contact = receiptContact(order);

  return {
    orderId: Number(order?.id),
    orderNumber: String(order?.order_number || `#${order?.id || ''}`),
    invoiceNumber: invoiceNumber(order?.invoice_number_1c, options.fallbackInvoiceNumber),
    invoiceDate: today,
    dueDate,
    payerName: String(company.name || customer.name || '').trim(),
    receiptContactType: contact?.Email ? 'email' : 'phone',
    receiptContactValue: contact?.Email || contact?.Phone || '',
    items: invoiceItems,
    total,
  };
}

function paymentErrorMessage(payload, fallback) {
  const message = String(payload?.Details || payload?.details || payload?.error?.message || payload?.errorMessage || payload?.message || payload?.Message || fallback);
  if (/неподходящие скопы|required scopes|opensme\/inn\//i.test(message)) {
    return 'Текущему API-токену Т-Банка не выдан доступ «Выставление ссылок через СБП». Создайте или обновите токен с разрешением на создание и получение QR-кода для вашей компании.';
  }
  return message;
}

export function createPaymentToken(payload, password) {
  const values = Object.entries({ ...payload, Password: password })
    .filter(([key, value]) => key !== 'Token' && value !== undefined && value !== null && typeof value !== 'object')
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, value]) => String(value))
    .join('');
  return createHash('sha256').update(values, 'utf8').digest('hex');
}

function tbankTransport(url, body, extraHeaders = {}) {
  const target = new URL(url);
  if (target.protocol !== 'https:' || target.hostname !== 'securepay.tinkoff.ru') {
    throw apiError('Некорректный адрес API Т-Банка.', 500);
  }
  const serialized = JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const request = httpsRequest({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port || 443,
      path: `${target.pathname}${target.search}`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(serialized),
        ...extraHeaders,
      },
      ca: [...rootCertificates, RUSSIAN_TRUSTED_CA],
      servername: target.hostname,
      timeout: 30000,
    }, (response) => {
      let raw = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { raw += chunk; });
      response.on('end', () => {
        let payload = {};
        try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = {}; }
        resolve({ ok: response.statusCode >= 200 && response.statusCode < 300, status: response.statusCode || 500, payload });
      });
    });
    request.on('timeout', () => request.destroy(new Error('Превышено время ожидания ответа Т-Банка.')));
    request.on('error', reject);
    request.end(serialized);
  });
}

async function createAcquiringPaymentLink(payload, password, transport = tbankTransport) {
  const body = { ...payload, Token: createPaymentToken(payload, password) };
  const response = await transport(INIT_API_URL, body);
  const result = response.payload || {};
  if (!response.ok || result?.Success === false) {
    throw apiError(paymentErrorMessage(result, `Т-Банк вернул ошибку HTTP ${response.status}.`), response.status >= 500 ? 502 : 400);
  }
  return result;
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

export default {
  id: 'symbolika-tbank',
  handler: (router, { services, getSchema, env, logger, database, tbankTransport: injectedTransport }) => {
    const terminalKey = String(env.SYMBOLIKA_TBANK_TERMINAL_KEY || process.env.SYMBOLIKA_TBANK_TERMINAL_KEY || '').trim();
    const terminalPassword = String(env.SYMBOLIKA_TBANK_TERMINAL_PASSWORD || process.env.SYMBOLIKA_TBANK_TERMINAL_PASSWORD || '').trim();

    const requireUser = (req, res) => {
      if (req.accountability?.user) return true;
      res.status(401).json({ errors: [{ message: 'Требуется авторизация.' }] });
      return false;
    };

    const loadOrder = async (orderId, accountability) => {
      const schema = await getSchema();
      const orderService = new services.ItemsService('orders', { schema, accountability });
      const itemService = new services.ItemsService('orders_items', { schema, accountability });
      const order = await orderService.readOne(orderId, {
        fields: [
          'id', 'order_number', 'invoice_number_1c', 'deadline',
          'customer.id', 'customer.name', 'customer.phone', 'customer.email',
          'customer_company.id', 'customer_company.name',
        ],
      });
      const items = await itemService.readByQuery({
        filter: { order: { _eq: orderId } },
        fields: ['id', 'product_name', 'quantity', 'price_per_unit', 'item_status'],
        sort: ['id'],
        limit: -1,
      });
      return { order, items };
    };

    router.get('/pay/:token', async (req, res) => {
      const token = String(req.params.token || '');
      const tracked = database && /^[0-9a-f-]{36}$/i.test(token)
        ? await database('symbolika_tbank_payments as tp').join('orders as o', 'o.id', 'tp.order_id').where('tp.public_token', token).first('tp.*', 'o.order_number')
        : null;
      if (!tracked) return res.status(404).send('Ссылка на оплату не найдена.');
      const items = await database('orders_items').where({ order: tracked.order_id }).where((query) => query.whereNull('item_status').orWhereNot('item_status', 'cancelled')).orderBy('id').select('product_name', 'quantity', 'price_per_unit');
      const paid = tracked.status === 'CONFIRMED';
      const rows = items.map((item) => `<div class="item"><span>${escapeHtml(item.product_name)}</span><span>${escapeHtml(item.quantity)} шт. × ${Number(item.price_per_unit).toLocaleString('ru-RU')} ₽</span></div>`).join('');
      return res.type('html').send(`<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Оплата ${escapeHtml(tracked.order_number)}</title><style>*{box-sizing:border-box}body{margin:0;background:#0b1015;color:#f5f7fa;font:16px system-ui,-apple-system,sans-serif;display:grid;min-height:100vh;place-items:center;padding:20px}.card{width:min(620px,100%);background:#151b22;border:1px solid #303945;border-radius:24px;padding:28px;box-shadow:0 24px 70px #0008}.brand{color:#ff7a21;font-weight:800}.muted{color:#98a4b3}.item{display:flex;justify-content:space-between;gap:20px;padding:14px 0;border-bottom:1px solid #2a333e}.total{font-size:32px;font-weight:900;margin:28px 0}.pay{display:block;text-align:center;background:#ff7a21;color:#101419;text-decoration:none;font-weight:800;padding:17px;border-radius:14px}.paid{color:#63e6b1;font-size:22px;font-weight:800}@media(max-width:520px){.card{padding:20px}.item{display:block}.item span{display:block;margin-top:5px}.total{font-size:27px}}</style></head><body><main class="card"><div class="brand">СИМВОЛИКА</div><p class="muted">Оплата заказа</p><h1>${escapeHtml(tracked.order_number)}</h1><section>${rows}</section><div class="total">${Number(tracked.amount).toLocaleString('ru-RU',{minimumFractionDigits:2})} ₽</div>${paid ? '<div class="paid">Оплата принята</div>' : `<a class="pay" href="${escapeHtml(tracked.sbp_url)}">Оплатить через СБП</a>`}<p class="muted">Безопасная оплата через Т‑Банк</p></main></body></html>`);
    });

    router.post('/notification', async (req, res) => {
      try {
        const payload = req.body || {};
        const receivedToken = String(payload.Token || '');
        if (!terminalPassword || !receivedToken || createPaymentToken(payload, terminalPassword) !== receivedToken) {
          return res.status(403).send('INVALID TOKEN');
        }
        const paymentId = String(payload.PaymentId || payload.PaymentID || '').trim();
        const status = String(payload.Status || '').trim().toUpperCase();
        if (!paymentId || !database) return res.status(400).send('INVALID PAYMENT');
        await database.transaction(async (trx) => {
          const tracked = await trx('symbolika_tbank_payments').where({ payment_id: paymentId }).forUpdate().first();
          if (!tracked) return;
          await trx('symbolika_tbank_payments').where({ id: tracked.id }).update({ status, date_updated: trx.fn.now() });
          if (status !== 'CONFIRMED' || tracked.order_payment_id) return;
          const order = await trx('orders').where({ id: tracked.order_id }).first('id', 'customer', 'customer_company', 'payment_type');
          if (!order) return;
          let paymentType = order.payment_type;
          if (!paymentType) {
            const type = await trx('payment_types').whereRaw("lower(name) like '%безнал%'").orderBy('id').first('id');
            paymentType = type?.id || null;
          }
          const inserted = await trx('order_payments').insert({
            order: order.id,
            customer: order.customer,
            customer_company: order.customer_company,
            amount: tracked.amount,
            payment_date: new Date().toISOString().slice(0, 10),
            payment_type: paymentType,
            payment_direction: 'incoming',
            allocation_mode: 'auto',
            comment: `Оплата через Т-Банк, PaymentId ${paymentId}`,
          }).returning('id');
          const orderPaymentId = Number(inserted?.[0]?.id ?? inserted?.[0]);
          await trx('symbolika_tbank_payments').where({ id: tracked.id }).update({ order_payment_id: orderPaymentId, date_updated: trx.fn.now() });
        });
        return res.send('OK');
      } catch (error) {
        logger.error({ error }, '[Symbolika TBank] Notification failed');
        return res.status(500).send('ERROR');
      }
    });

    router.get('/orders/:id/preview', async (req, res) => {
      if (!requireUser(req, res)) return;
      try {
        const orderId = Number(req.params.id);
        if (!Number.isInteger(orderId) || orderId <= 0) throw apiError('Некорректный заказ.', 400);
        const { order, items } = await loadOrder(orderId, req.accountability);
        const preview = buildInvoicePreview(order, items);
        if (!preview.items.length) throw apiError('В заказе нет позиций для выставления счёта.', 400);
        const tracked = database ? await database('symbolika_tbank_payments').where({ order_id: orderId }).orderBy('date_created', 'desc').first() : null;
        res.json({ data: { ...preview, paymentLinkStatus: tracked?.status || '', paymentLinkUrl: tracked?.payment_url || '', paymentLinkAmount: tracked?.amount || 0 } });
      } catch (error) {
        res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось подготовить счёт.' }] });
      }
    });

    router.post('/orders/:id/payment-link', async (req, res) => {
      if (!requireUser(req, res)) return;
      try {
        if (!terminalKey || !terminalPassword) throw apiError('Не настроены TerminalKey и пароль интернет-эквайринга Т-Банка.', 503);
        const orderId = Number(req.params.id);
        if (!Number.isInteger(orderId) || orderId <= 0) throw apiError('Некорректный заказ.', 400);
        const { order, items } = await loadOrder(orderId, req.accountability);
        const preview = buildInvoicePreview(order, items);
        if (!preview.items.length) throw apiError('В заказе нет позиций для выставления счёта.', 400);
        if (preview.items.some((item) => item.price <= 0)) throw apiError('У всех позиций должна быть указана цена больше нуля.', 400);
        if (preview.total <= 0) throw apiError('Сумма оплаты должна быть больше нуля.', 400);
        const requestedContactType = String(req.body?.contactType || '').trim().toLowerCase();
        const requestedContactValue = String(req.body?.contactValue || '').trim();
        const contact = requestedContactValue
          ? receiptContactFromInput(requestedContactType, requestedContactValue)
          : receiptContact(order);
        if (!contact) throw apiError(requestedContactValue
          ? 'Проверьте правильность телефона или email для кассового чека.'
          : 'Укажите телефон или email для отправки кассового чека.', 400);
        const receipt = buildReceipt(preview, contact);
        const amount = receipt.Items.reduce((sum, item) => sum + item.Amount, 0);
        const operationId = `${preview.orderNumber}-${Date.now()}`.replace(/[^a-zA-Z0-9_-]/g, '').slice(-50);
        const requestBody = {
          TerminalKey: terminalKey,
          Amount: amount,
          OrderId: operationId,
          Description: `Оплата по заказу ${preview.orderNumber}`.slice(0, 140),
          PayType: 'O',
          Language: 'ru',
          NotificationURL: 'https://symbcorp.ru/symbolika-tbank/notification',
          Receipt: receipt,
        };
        const bankResult = await createAcquiringPaymentLink(requestBody, terminalPassword, injectedTransport || tbankTransport);
        const paymentId = String(bankResult?.PaymentId || bankResult?.PaymentID || '').trim();
        if (!paymentId) throw apiError('Т-Банк инициировал платёж без PaymentId.', 502);
        const qrPayload = { TerminalKey: terminalKey, PaymentId: paymentId, DataType: 'PAYLOAD', PaymentMethod: 'SBP' };
        const qrResult = await createAcquiringPaymentLink.call(null, qrPayload, terminalPassword, async (url, body) => (injectedTransport || tbankTransport)(GET_QR_API_URL, body));
        const sbpUrl = String(qrResult?.Data || qrResult?.data || '').trim();
        if (!sbpUrl) throw apiError('Т-Банк не вернул ссылку СБП.', 502);
        const publicToken = randomUUID();
        const paymentUrl = `https://symbcorp.ru/symbolika-tbank/pay/${publicToken}`;
        if (database) await database('symbolika_tbank_payments').insert({
          order_id: orderId,
          payment_id: paymentId,
          payment_url: paymentUrl,
          public_token: publicToken,
          sbp_url: sbpUrl,
          amount: amount / 100,
          status: String(bankResult?.Status || 'NEW'),
        });
        res.json({ data: { paymentId, paymentUrl, total: preview.total, operationId } });
      } catch (error) {
        logger.error({ error, orderId: Number(req.params.id) || null }, '[Symbolika TBank] Payment link request failed');
        res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось создать ссылку на оплату в Т-Банке.' }] });
      }
    });
  },
};

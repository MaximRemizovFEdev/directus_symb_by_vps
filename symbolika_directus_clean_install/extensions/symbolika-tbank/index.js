import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { request as httpsRequest } from 'node:https';
import { rootCertificates } from 'node:tls';

const INIT_API_URL = 'https://securepay.tinkoff.ru/v2/Init';
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

  return {
    orderId: Number(order?.id),
    orderNumber: String(order?.order_number || `#${order?.id || ''}`),
    invoiceNumber: invoiceNumber(order?.invoice_number_1c, options.fallbackInvoiceNumber),
    invoiceDate: today,
    dueDate,
    payerName: String(company.name || customer.name || '').trim(),
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

export default {
  id: 'symbolika-tbank',
  handler: (router, { services, getSchema, env, logger, tbankTransport: injectedTransport }) => {
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
          'customer.id', 'customer.name',
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

    router.get('/orders/:id/preview', async (req, res) => {
      if (!requireUser(req, res)) return;
      try {
        const orderId = Number(req.params.id);
        if (!Number.isInteger(orderId) || orderId <= 0) throw apiError('Некорректный заказ.', 400);
        const { order, items } = await loadOrder(orderId, req.accountability);
        const preview = buildInvoicePreview(order, items);
        if (!preview.items.length) throw apiError('В заказе нет позиций для выставления счёта.', 400);
        res.json({ data: preview });
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
        const operationId = `${preview.orderNumber}-${Date.now()}`.replace(/[^a-zA-Z0-9_-]/g, '').slice(-50);
        const requestBody = {
          TerminalKey: terminalKey,
          Amount: Math.round(preview.total * 100),
          OrderId: operationId,
          Description: `Оплата по заказу ${preview.orderNumber}`.slice(0, 140),
          PayType: 'O',
          Language: 'ru',
        };
        const bankResult = await createAcquiringPaymentLink(requestBody, terminalPassword, injectedTransport || tbankTransport);
        const paymentUrl = String(bankResult?.PaymentURL || bankResult?.PaymentUrl || bankResult?.paymentUrl || '').trim();
        const paymentId = String(bankResult?.PaymentId || bankResult?.PaymentID || '').trim();
        if (!paymentUrl) throw apiError('Т-Банк инициировал платёж, но не вернул ссылку PaymentURL.', 502);
        res.json({ data: { paymentId, paymentUrl, total: preview.total, operationId } });
      } catch (error) {
        logger.error({ error, orderId: Number(req.params.id) || null }, '[Symbolika TBank] Payment link request failed');
        res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось создать ссылку на оплату в Т-Банке.' }] });
      }
    });
  },
};

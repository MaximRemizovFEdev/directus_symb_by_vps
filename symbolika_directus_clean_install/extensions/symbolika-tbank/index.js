import { randomUUID } from 'node:crypto';

const API_URL = 'https://business.tbank.ru/openapi/api/v1/invoice/send';

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

function tbankErrorMessage(payload, status) {
  return String(
    payload?.errorMessage
      || payload?.message
      || payload?.error?.message
      || payload?.errors?.[0]?.message
      || `Т-Банк вернул ошибку HTTP ${status}.`,
  );
}

function invoiceResult(payload = {}) {
  return {
    invoiceId: payload.invoiceId || payload.InvoiceId || payload.id || null,
    paymentUrl: payload.paymentUrl || payload.PaymentUrl || payload.pdfUrl || payload.PdfUrl || payload.url || null,
  };
}

export default {
  id: 'symbolika-tbank',
  handler: (router, { services, getSchema, env, logger }) => {
    const token = String(env.SYMBOLIKA_TBANK_TOKEN || process.env.SYMBOLIKA_TBANK_TOKEN || '').trim();
    const accountNumber = String(env.SYMBOLIKA_TBANK_ACCOUNT_NUMBER || process.env.SYMBOLIKA_TBANK_ACCOUNT_NUMBER || '').trim();

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

    router.post('/orders/:id/invoice', async (req, res) => {
      if (!requireUser(req, res)) return;
      try {
        if (!token) throw apiError('Интеграция с Т-Банком не настроена.', 503);
        const orderId = Number(req.params.id);
        if (!Number.isInteger(orderId) || orderId <= 0) throw apiError('Некорректный заказ.', 400);
        const { order, items } = await loadOrder(orderId, req.accountability);
        const preview = buildInvoicePreview(order, items);
        if (!preview.items.length) throw apiError('В заказе нет позиций для выставления счёта.', 400);
        if (preview.items.length > 100) throw apiError('Т-Банк принимает не более 100 позиций в одном счёте.', 400);
        if (preview.items.some((item) => item.price <= 0)) throw apiError('У всех позиций должна быть указана цена больше нуля.', 400);

        const requestedInvoiceNumber = invoiceNumber(req.body?.invoiceNumber, preview.invoiceNumber);
        const requestedDueDate = dateOnly(req.body?.dueDate) || preview.dueDate;
        if (requestedDueDate < preview.invoiceDate) throw apiError('Срок оплаты не может быть раньше текущей даты.', 400);
        const body = {
          invoiceNumber: requestedInvoiceNumber,
          invoiceDate: preview.invoiceDate,
          dueDate: requestedDueDate,
          items: preview.items.map(({ name, price, amount, unit, vat }) => ({ name, price, amount, unit, vat })),
          customPaymentPurpose: `Оплата по заказу ${preview.orderNumber}`.slice(0, 512),
        };
        if (accountNumber) body.accountNumber = accountNumber;

        const response = await fetch(API_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            'X-Request-Id': randomUUID(),
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(30000),
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw apiError(tbankErrorMessage(payload, response.status), response.status >= 500 ? 502 : 400);
        const result = invoiceResult(payload);
        if (!result.paymentUrl) {
          logger.warn({ orderId, invoiceId: result.invoiceId }, '[Symbolika TBank] Invoice created without a returned URL');
          throw apiError('Счёт создан, но Т-Банк не вернул ссылку. Проверьте его в личном кабинете Т-Бизнеса.', 502);
        }
        res.json({ data: { ...result, invoiceNumber: requestedInvoiceNumber, total: preview.total } });
      } catch (error) {
        logger.error({ error, orderId: Number(req.params.id) || null }, '[Symbolika TBank] Invoice request failed');
        res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось создать счёт в Т-Банке.' }] });
      }
    });
  },
};

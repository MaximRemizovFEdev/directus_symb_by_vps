import assert from 'node:assert/strict';
import test from 'node:test';
import endpoint, { buildInvoicePreview } from '../index.js';

test('builds an invoice preview from active order positions without requiring contacts', () => {
  const preview = buildInvoicePreview({
    id: 114,
    order_number: 'SO-00109',
    invoice_number_1c: '',
    deadline: '2026-09-18',
    customer: { name: 'Клиент', phone: '8 900 000-00-00', email: 'person@example.com' },
    customer_company: { name: 'Компания', phone: '+7 (999) 111-22-33', email: 'office@example.com' },
  }, [
    { id: 1, product_name: 'Футболка', quantity: '2', price_per_unit: '1250.50', item_status: 'ready' },
    { id: 2, product_name: 'Отменено', quantity: 1, price_per_unit: 500, item_status: 'cancelled' },
  ], { today: '2026-09-17', defaultDueDate: '2026-09-24', fallbackInvoiceNumber: '260917114001' });

  assert.equal(preview.invoiceNumber, '260917114001');
  assert.equal(preview.dueDate, '2026-09-18');
  assert.equal('contactPhone' in preview, false);
  assert.equal('email' in preview, false);
  assert.equal(preview.payerName, 'Компания');
  assert.deepEqual(preview.items, [{ id: 1, name: 'Футболка', price: 1250.5, amount: 2, unit: 'шт', vat: 'None' }]);
  assert.equal(preview.total, 2501);
});

test('uses a future fallback deadline and configured 1C invoice number when company is absent', () => {
  const preview = buildInvoicePreview({
    id: 7,
    order_number: 'SO-00007',
    deadline: '2026-09-01',
    invoice_number_1c: 'Счёт № 731',
    customer: { name: 'Клиент', phone: '9000000000', email: 'CLIENT@EXAMPLE.COM' },
  }, [{ id: 3, product_name: 'Печать', quantity: 1, price_per_unit: 100, item_status: 'new' }], {
    today: '2026-09-17',
    defaultDueDate: '2026-09-24',
  });

  assert.equal(preview.dueDate, '2026-09-24');
  assert.equal(preview.invoiceNumber, '731');
});

test('creates a one-time B2B SBP payment link', async () => {
  const routes = {};
  const router = {
    get(path, handler) { routes[`GET ${path}`] = handler; },
    post(path, handler) { routes[`POST ${path}`] = handler; },
  };
  const order = {
    id: 114,
    order_number: 'SO-00109',
    deadline: '2099-09-24',
    customer: { name: 'Клиент', phone: '+79990000000', email: 'client@example.com' },
    customer_company: null,
  };
  const items = [{ id: 257, product_name: 'Брошюра', quantity: 2, price_per_unit: 1060, item_status: 'ready' }];
  class ItemsService {
    constructor(collection) { this.collection = collection; }
    async readOne() { return order; }
    async readByQuery() { return items; }
  }
  const bankRequests = [];
  const tbankTransport = async (url, body, headers) => {
    bankRequests.push({ url, body, headers });
    return { ok: true, status: 200, payload: { qrId: '0d557f3e-5986-4fa3-9b83-13e7978f01cc', payload: 'https://qr.nspk.ru/payment-1' } };
  };
  const response = {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };

  endpoint.handler(router, {
    services: { ItemsService },
    getSchema: async () => ({}),
    env: {
      SYMBOLIKA_TBANK_TOKEN: 'api-token-test',
      SYMBOLIKA_TBANK_ACCOUNT_NUMBER: '40702810900000000001',
    },
    logger: { warn() {}, error() {} },
    tbankTransport,
  });

  await routes['POST /orders/:id/payment-link']({
    params: { id: '114' },
    body: {},
    accountability: { user: 'user-1' },
  }, response);

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.data.paymentUrl, 'https://qr.nspk.ru/payment-1');
  assert.equal(response.body.data.qrId, '0d557f3e-5986-4fa3-9b83-13e7978f01cc');
  assert.equal(bankRequests.length, 1);
  assert.equal(bankRequests[0].url, 'https://business.tbank.ru/openapi/api/v1/b2b/qr/onetime');
  assert.deepEqual(bankRequests[0].body, {
    purpose: 'Оплата по заказу SO-00109',
    ttl: 7,
    sum: 2120,
    accountNumber: '40702810900000000001',
  });
  assert.equal(bankRequests[0].headers.Authorization, 'Bearer api-token-test');
  assert.match(bankRequests[0].headers['X-Request-Id'], /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
});

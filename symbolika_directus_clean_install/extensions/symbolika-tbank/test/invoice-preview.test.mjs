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

test('creates an invoice with the server token and canonical order items', async () => {
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
  endpoint.handler(router, {
    services: { ItemsService },
    getSchema: async () => ({}),
    env: { SYMBOLIKA_TBANK_TOKEN: 'server-only-test-token' },
    logger: { warn() {}, error() {} },
  });

  const originalFetch = globalThis.fetch;
  let bankRequest;
  globalThis.fetch = async (url, options) => {
    bankRequest = { url, options };
    return { ok: true, status: 200, json: async () => ({ invoiceId: 'invoice-1', PdfUrl: 'https://example.test/invoice-1' }) };
  };
  const response = {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };

  try {
    await routes['POST /orders/:id/invoice']({
      params: { id: '114' },
      body: { invoiceNumber: '109', dueDate: '2099-09-24' },
      accountability: { user: 'user-1' },
    }, response);
  } finally {
    globalThis.fetch = originalFetch;
  }

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.data.paymentUrl, 'https://example.test/invoice-1');
  assert.equal(bankRequest.options.headers.Authorization, 'Bearer server-only-test-token');
  const sent = JSON.parse(bankRequest.options.body);
  assert.equal(sent.invoiceNumber, '109');
  assert.deepEqual(sent.items, [{ name: 'Брошюра', price: 1060, amount: 2, unit: 'шт', vat: 'None' }]);
  assert.equal('contactPhone' in sent, false);
  assert.equal('contacts' in sent, false);
});

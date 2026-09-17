import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sourceUrl = new URL('../index.js', import.meta.url);

function methodSource(source, name, nextName) {
  const start = source.indexOf(`    async ${name}(`);
  const end = source.indexOf(`    ${nextName}(`, start);
  assert.notEqual(start, -1, `${name} method must exist`);
  assert.notEqual(end, -1, `${nextName} method boundary must exist`);
  return source.slice(start, end);
}

test('whole-order office issue immediately updates every loaded position cache', async () => {
  const source = await readFile(sourceUrl, 'utf8');
  const method = methodSource(source, 'confirmOrderIssue', 'openExpenseDialog');
  const requestIndex = method.indexOf("body: JSON.stringify({ office_status: 'issued' })");
  const itemCacheIndex = method.indexOf('fresh.items.forEach((item) => {');
  const orderCacheIndex = method.indexOf('this.updateOrderCaches(orderId, {');
  const reloadIndex = method.indexOf('await this.loadAllowedData();');

  assert.ok(requestIndex >= 0, 'issue request must be present');
  assert.ok(itemCacheIndex > requestIndex, 'item caches must change only after the server accepts issue');
  assert.ok(orderCacheIndex > itemCacheIndex, 'item and order caches must be updated together');
  assert.ok(reloadIndex > orderCacheIndex, 'server-backed reload must still verify the optimistic cache state');
  assert.match(method, /this\.updateOrderItemCaches\(item\.id, \{\s*item_status: 'delivered',\s*office_status: 'issued',\s*\}\)/);
});

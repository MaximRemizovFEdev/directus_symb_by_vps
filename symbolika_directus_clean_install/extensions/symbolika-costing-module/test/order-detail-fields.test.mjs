import test from 'node:test';
import assert from 'node:assert/strict';

import {
  managerOrderItemFields,
  orderDetailFields,
  orderItemCardFields,
  orderItemCardWorkerFields,
  orderItemDesignerFields,
  orderItemManagerFields,
  orderItemPrivilegedFields,
  orderItemSafeFields,
  orderItemsListFields,
  orderItemWorkerFields,
} from '../lib/order-detail-fields.js';

test('order detail mask contains the canonical relations and finance fields', () => {
  assert.ok(orderDetailFields.includes('manager_employee.full_name'));
  assert.ok(orderDetailFields.includes('shipping_comment'));
  assert.ok(orderDetailFields.includes('payment_due'));
  assert.equal(new Set(orderDetailFields).size, orderDetailFields.length);
});

test('manager item mask exposes costs only when editing costs is allowed', () => {
  assert.strictEqual(managerOrderItemFields(true), orderItemManagerFields);
  const restricted = managerOrderItemFields(false);
  assert.equal(restricted.includes('contractor_1_cost'), false);
  assert.equal(restricted.includes('contractor_2_cost'), false);
  assert.ok(restricted.includes('contractor_1.name'));
});

test('item card fields preserve role-specific security masks', () => {
  assert.strictEqual(orderItemCardFields({ roleName: 'Дизайнер' }), orderItemDesignerFields);
  assert.strictEqual(orderItemCardFields({ roleName: 'Производство' }), orderItemCardWorkerFields);
  assert.strictEqual(orderItemCardFields({ ownsOrder: true, canEditItemCosts: true }), orderItemManagerFields);
  assert.strictEqual(orderItemCardFields({ hasManagerWorkflowAccess: true, canEditItemCosts: true }), orderItemManagerFields);
});

test('order item list fields preserve override and owner behavior', () => {
  assert.strictEqual(orderItemsListFields({ hasManagerOverrideAccess: true }), orderItemPrivilegedFields);
  assert.strictEqual(orderItemsListFields({ roleName: 'Менеджер', canEditItemCosts: true }), orderItemManagerFields);
  assert.strictEqual(orderItemsListFields({ roleName: 'Производство' }), orderItemWorkerFields);
});

test('fallback mask remains independent from nested relation masks', () => {
  assert.ok(orderItemSafeFields.includes('order_link'));
  assert.ok(orderItemSafeFields.includes('contractor_1'));
  assert.equal(orderItemSafeFields.includes('contractor_1.name'), false);
  assert.equal(new Set(orderItemSafeFields).size, orderItemSafeFields.length);
});

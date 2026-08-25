import { entityId } from './core-utils.js';

const itemSources = new Set([
  'orders_items',
  'costing',
  'contractor_costing',
  'items_archive',
  'production_work',
  'screen_printing_work',
  'contractor_work',
]);

const orderSources = new Set([
  'order',
  'orders',
  'all_orders',
  'my_orders',
  'orders_archive',
  'office',
  'office_issue',
]);

export function detailEntityType(sourceType, row) {
  if (row?._entity_type === 'order' || row?._entity_type === 'item') return row._entity_type;
  if (orderSources.has(sourceType)) return 'order';
  if (itemSources.has(sourceType)) return 'item';
  if (row?.order_item !== undefined && row?.order_item !== null) return 'item';
  if (row?.product_name !== undefined && row?.product_name !== null) return 'item';
  return 'order';
}

export function detailItemId(row) {
  return entityId(row?.order_item)
    || (detailEntityType('', row) === 'item' ? entityId(row?.id) : '');
}

export function detailIsOrder(row) {
  return detailEntityType('', row) === 'order';
}

export function orderId(row) {
  if (row?.order_link) return row.order_link;
  if (row?.order_number && !row?.product_name && row?.id) return row.id;
  if (!row?.order) return '';
  return typeof row.order === 'object' ? (row.order.id || '') : row.order;
}

export function orderNumber(row) {
  if (row?.order_number) return row.order_number;
  if (typeof row?.order === 'object') return row.order.order_number || `#${row.order.id}`;
  return row?.order ? `#${row.order}` : '-';
}

export function orderRowKey(row) {
  const linkedOrderId = entityId(orderId(row));
  if (linkedOrderId) return linkedOrderId;

  // A position id is not an order id. Never use it as a fallback because an
  // unrelated order may have the same numeric id.
  if (!row?.product_name && row?.id) return entityId(row.id);
  if (!row?.product_name && row?.order_number) return String(row.order_number);
  return '';
}

export function orderItemId(row) {
  return entityId(row?.order_item) || entityId(row?.id);
}

function quantityIdentity(value) {
  const number = Number(String(value ?? '').replace(',', '.'));
  if (!Number.isFinite(number)) return '0';
  return Number.isInteger(number)
    ? String(number)
    : new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 }).format(number);
}

export function orderItemIdentityKey(row, { includeOrder = false } = {}) {
  const itemId = orderItemId(row);
  if (itemId) return `id:${itemId}`;

  const product = String(row?.product_name || '').trim().toLowerCase();
  const quantity = quantityIdentity(row?.quantity);
  return includeOrder ? `${orderNumber(row)}:${product}:${quantity}` : `${product}:${quantity}`;
}

export function findOrderContext(row, sources = []) {
  if (row?.order_context) return row.order_context;

  const linkedOrderId = entityId(orderId(row));
  const linkedOrderNumber = orderNumber(row);
  return sources.find((candidate) => {
    const candidateOrderId = entityId(orderId(candidate));
    const matchesOrderId = linkedOrderId && candidateOrderId && candidateOrderId === linkedOrderId;
    const matchesNumber = linkedOrderNumber !== '-' && candidate?.order_number === linkedOrderNumber;
    return matchesOrderId || matchesNumber;
  }) || row;
}

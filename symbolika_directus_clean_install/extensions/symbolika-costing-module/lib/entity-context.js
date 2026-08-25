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

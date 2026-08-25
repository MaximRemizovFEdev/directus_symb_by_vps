export const orderDetailFields = Object.freeze([
  'id',
  'order_number',
  'date',
  'deadline',
  'customer.id',
  'customer.name',
  'customer_company.id',
  'customer_company.name',
  'manager_employee.id',
  'manager_employee.full_name',
  'order_status',
  'office_status',
  'shipping_method',
  'shipping_comment',
  'payment_type.id',
  'payment_type.name',
  'payment_on_receipt',
  'comment',
  'order_sum',
  'paid_amount',
  'payment_due',
]);

export const orderItemManagerFields = Object.freeze([
  'id',
  'order',
  'order.order_number',
  'product_name',
  'quantity',
  'price_per_unit',
  'order_sum',
  'deadline',
  'item_status',
  'office_status',
  'shipping_method',
  'blank_source',
  'product_category',
  'product_subcategory',
  'application_method',
  'contractor_1.id',
  'contractor_1.name',
  'contractor_1.supplies_textile_blanks',
  'contractor_1.supplies_merch_blanks',
  'contractor_1_cost',
  'contractor_2.id',
  'contractor_2.name',
  'contractor_2_cost',
  'technical_task_text',
  'url',
  'layout_revision_url_snapshot',
  'layout_disk_path',
  'layout_disk_name',
  'layout_disk_size',
  'layout_disk_mime_type',
  'layout_disk_uploaded_at',
  'layout_preview_url',
  'layout_preview_disk_path',
  'layout_preview_disk_name',
  'layout_preview_disk_size',
  'layout_preview_disk_mime_type',
  'layout_preview_uploaded_at',
  'needs_designer_help',
  'designer_comment',
  'designer_source_url',
  'production_status',
  'production_comment',
]);

export const orderItemPrivilegedFields = Object.freeze([
  ...orderItemManagerFields,
  'internal_route_production',
  'internal_route_screen',
]);

export const orderItemWorkerFields = Object.freeze([
  'id',
  'order',
  'order.order_number',
  'product_name',
  'quantity',
  'deadline',
  'item_status',
  'production_status',
  'production_comment',
  'technical_task_text',
  'shipping_method',
  'office_status',
  'url',
]);

export const orderItemCardWorkerFields = Object.freeze([
  'id',
  'order',
  'product_name',
  'quantity',
  'deadline',
  'item_status',
  'technical_task_text',
  'url',
  'production_status',
  'production_comment',
]);

export const orderItemDesignerFields = Object.freeze([
  'id',
  'order',
  'product_name',
  'quantity',
  'deadline',
  'technical_task_text',
  'url',
  'needs_designer_help',
  'designer_comment',
  'designer_source_url',
  'layout_preview_url',
  'layout_preview_disk_name',
  'layout_preview_disk_size',
  'layout_preview_disk_mime_type',
  'layout_preview_uploaded_at',
]);

export const orderItemSafeFields = Object.freeze([
  'id',
  'order',
  'order_link',
  'product_name',
  'quantity',
  'price_per_unit',
  'order_sum',
  'deadline',
  'item_status',
  'office_status',
  'shipping_method',
  'blank_source',
  'product_category',
  'product_subcategory',
  'application_method',
  'contractor_1',
  'contractor_1_cost',
  'contractor_2',
  'contractor_2_cost',
  'technical_task_text',
  'url',
  'needs_designer_help',
  'designer_comment',
  'designer_source_url',
  'production_status',
  'production_comment',
]);

const costFields = new Set(['contractor_1_cost', 'contractor_2_cost']);

export function managerOrderItemFields(canEditItemCosts) {
  return canEditItemCosts
    ? orderItemManagerFields
    : orderItemManagerFields.filter((field) => !costFields.has(field));
}

export function orderItemCardFields({
  roleName = '',
  hasManagerWorkflowAccess = false,
  ownsOrder = false,
  canEditItemCosts = false,
} = {}) {
  if (hasManagerWorkflowAccess || ownsOrder) return managerOrderItemFields(canEditItemCosts);
  if (roleName === 'Дизайнер') return orderItemDesignerFields;
  return orderItemCardWorkerFields;
}

export function orderItemsListFields({
  roleName = '',
  hasManagerOverrideAccess = false,
  ownsOrder = false,
  canEditItemCosts = false,
} = {}) {
  if (hasManagerOverrideAccess) return orderItemPrivilegedFields;
  if (roleName === 'Менеджер' || ownsOrder) return managerOrderItemFields(canEditItemCosts);
  return orderItemWorkerFields;
}

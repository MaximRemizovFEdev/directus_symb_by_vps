BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION sync_work_item(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  order_status_name text;
  item_work_status character varying;
BEGIN
  DELETE FROM production_work WHERE id = item_id;
  DELETE FROM screen_printing_work WHERE id = item_id;
  DELETE FROM contractor_work WHERE order_item = item_id;

  SELECT os.name, symbolika_normalize_item_status(oi.item_status)
    INTO order_status_name, item_work_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE oi.id = item_id;

  IF item_work_status NOT IN ('sent_to_work', 'in_work', 'layout_revision', 'ready', 'cancelled')
     AND order_status_name NOT IN (
       U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443',
       U&'\0412 \0440\0430\0431\043e\0442\0435',
       U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430',
       U&'\0413\043e\0442\043e\0432',
       U&'\041e\0442\043c\0435\043d\0435\043d'
     ) THEN
    RETURN;
  END IF;

  INSERT INTO production_work (
    id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
    product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
    product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
    technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
  )
  SELECT
    oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
    oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
    oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
    oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (
      c1.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
      OR c2.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
      OR COALESCE(oi.internal_route_production, false)
    );

  INSERT INTO screen_printing_work (
    id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
    product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
    product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
    application_contractor_slot, application_cost_per_unit, application_cost_total,
    technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
  )
  SELECT
    oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
    oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
    oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
    CASE
      WHEN c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%' THEN 2
      ELSE 1
    END,
    oi.screen_printing_cost_per_unit,
    COALESCE(oi.quantity, 0) * COALESCE(oi.screen_printing_cost_per_unit, 0),
    oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (
      c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
      OR c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
      OR COALESCE(oi.internal_route_screen, false)
    );

  INSERT INTO contractor_work (
    id, order_item, contractor, contractor_slot, contractor_has_own_view, access_user,
    "order", customer, customer_company, manager_employee,
    product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
  )
  SELECT
    oi.id * 10 + contractor_slots.slot,
    oi.id,
    contractor_slots.contractor_id,
    contractor_slots.slot,
    c.has_own_view,
    c.directus_user,
    oi."order",
    o.customer,
    o.customer_company,
    o.manager_employee,
    oi.product_name,
    oi.quantity,
    oi.technical_task_text,
    oi.production_comment,
    oi.url,
    oi.production_status,
    oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  CROSS JOIN LATERAL (
    VALUES (1, oi.contractor_1), (2, oi.contractor_2)
  ) AS contractor_slots(slot, contractor_id)
  JOIN contractors c ON c.id = contractor_slots.contractor_id
  WHERE oi.id = item_id
    AND contractor_slots.contractor_id IS NOT NULL;
END;
$$;

-- Let the screen-printing role update only its dedicated persistent cost
-- field and only on positions routed to that workshop.
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT
  'orders_items',
  'read',
  '{"_or":[{"contractor_1":{"name":{"_icontains":"шелкограф"}}},{"contractor_2":{"name":{"_icontains":"шелкограф"}}},{"internal_route_screen":{"_eq":true}}]}'::json,
  NULL,
  NULL,
  'id,screen_printing_cost_per_unit',
  '00000000-0000-4000-8000-000000000206'
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions permission
  WHERE permission.collection = 'orders_items'
    AND permission.action = 'read'
    AND permission.policy = '00000000-0000-4000-8000-000000000206'
    AND permission.fields = 'id,screen_printing_cost_per_unit'
);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT
  'orders_items',
  'update',
  '{"_or":[{"contractor_1":{"name":{"_icontains":"шелкограф"}}},{"contractor_2":{"name":{"_icontains":"шелкограф"}}},{"internal_route_screen":{"_eq":true}}]}'::json,
  '{"_or":[{"contractor_1":{"name":{"_icontains":"шелкограф"}}},{"contractor_2":{"name":{"_icontains":"шелкограф"}}},{"internal_route_screen":{"_eq":true}}]}'::json,
  NULL,
  'screen_printing_cost_per_unit',
  '00000000-0000-4000-8000-000000000206'
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions permission
  WHERE permission.collection = 'orders_items'
    AND permission.action = 'update'
    AND permission.policy = '00000000-0000-4000-8000-000000000206'
    AND permission.fields = 'screen_printing_cost_per_unit'
);

-- Repair work rows previously rebuilt by the legacy function without cost
-- columns. The order item is authoritative.
UPDATE screen_printing_work work
SET application_cost_per_unit = item.screen_printing_cost_per_unit,
    application_cost_total = COALESCE(item.quantity, 0) * COALESCE(item.screen_printing_cost_per_unit, 0)
FROM orders_items item
WHERE work.id = item.id
  AND (
    work.application_cost_per_unit IS DISTINCT FROM item.screen_printing_cost_per_unit
    OR work.application_cost_total IS DISTINCT FROM COALESCE(item.quantity, 0) * COALESCE(item.screen_printing_cost_per_unit, 0)
  );

COMMIT;

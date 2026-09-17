BEGIN;

-- Full reconciliation rebuilds are still needed for client operations and
-- payments. Serialize those rare rebuilds so two DELETE/INSERT cycles cannot
-- create the same projection id concurrently.
DO $$
BEGIN
  IF to_regprocedure('refresh_customer_reconciliation()') IS NULL THEN
    RAISE EXCEPTION 'refresh_customer_reconciliation() is required before this migration';
  END IF;

  IF to_regprocedure('symbolika_refresh_customer_reconciliation_body()') IS NULL THEN
    ALTER FUNCTION refresh_customer_reconciliation()
      RENAME TO symbolika_refresh_customer_reconciliation_body;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION refresh_customer_reconciliation()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('symbolika_customer_reconciliation_refresh'));
  PERFORM symbolika_refresh_customer_reconciliation_body();
END;
$$;

-- Ordinary order and item changes must update only their own reconciliation
-- rows. A per-order lock makes repeated item triggers in one order harmless
-- without blocking changes in unrelated orders.
CREATE OR REPLACE FUNCTION sync_customer_reconciliation_order(target_order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF target_order_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('symbolika_customer_reconciliation_order'), target_order_id);

  DELETE FROM customer_reconciliation_items
   WHERE order_link = target_order_id;
  DELETE FROM customer_reconciliation
   WHERE id = target_order_id
     AND COALESCE(entry_type, 'order') = 'order';

  INSERT INTO customer_reconciliation (
    id, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name,
    order_sum, paid_amount, payment_due, overpayment,
    customer_debt_to_us, our_debt_to_customer, reconciliation_result,
    entry_type, client_operation, operation_type, direction, description
  )
  SELECT
    o.id, o.id, o.order_number, o.date, o.deadline,
    o.customer, c.name, o.customer_company, cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), 'Без заказчика'),
    o.manager_employee, e.full_name, o.order_status, os.name,
    COALESCE(o.order_sum, 0), COALESCE(o.paid_amount, 0), COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    GREATEST(COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    GREATEST(-COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    CASE WHEN COALESCE(o.payment_due, 0) > 0 THEN 'Клиент должен'
         WHEN COALESCE(o.payment_due, 0) < 0 THEN 'Мы должны'
         ELSE 'Расчет закрыт' END,
    'order', NULL, NULL, NULL, NULL
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE o.id = target_order_id;

  INSERT INTO customer_reconciliation_items (
    id, order_item, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name, production_status_name,
    product_name, quantity, price_per_unit, item_sum,
    order_sum, paid_amount, payment_due, overpayment, reconciliation_result
  )
  SELECT
    oi.id, oi.id, o.id, o.order_number, o.date, COALESCE(oi.deadline, o.deadline),
    o.customer, c.name, o.customer_company, cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), 'Без заказчика'),
    o.manager_employee, e.full_name, o.order_status, os.name, ps.name,
    oi.product_name, COALESCE(oi.quantity, 0), COALESCE(oi.price_per_unit, 0),
    COALESCE(oi.order_sum, COALESCE(oi.quantity, 0) * COALESCE(oi.price_per_unit, 0)),
    COALESCE(o.order_sum, 0), COALESCE(o.paid_amount, 0), COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    CASE WHEN COALESCE(o.payment_due, 0) > 0 THEN 'Клиент должен'
         WHEN COALESCE(o.payment_due, 0) < 0 THEN 'Мы должны'
         ELSE 'Расчет закрыт' END
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  LEFT JOIN production_statuses ps ON ps.id = oi.production_status
  WHERE o.id = target_order_id;
END;
$$;

DO $$
DECLARE
  function_definition text;
BEGIN
  function_definition := pg_get_functiondef('sync_orders_overview(integer)'::regprocedure);
  IF position('PERFORM sync_customer_reconciliation_order(order_id);' IN function_definition) = 0 THEN
    IF position('PERFORM refresh_customer_reconciliation();' IN function_definition) = 0 THEN
      RAISE EXCEPTION 'sync_orders_overview(integer) has an unexpected definition';
    END IF;
    function_definition := replace(
      function_definition,
      'PERFORM refresh_customer_reconciliation();',
      'PERFORM sync_customer_reconciliation_order(order_id);'
    );
    EXECUTE function_definition;
  END IF;
END;
$$;

SELECT refresh_customer_reconciliation();

COMMIT;

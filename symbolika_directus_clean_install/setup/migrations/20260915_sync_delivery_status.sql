BEGIN;

-- Delivery and the public order status describe the same final state. Keep
-- them consistent even when the status is changed indirectly by item
-- aggregation or by a server hook.
CREATE OR REPLACE FUNCTION symbolika_normalize_order_delivery_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  delivered_status_id integer;
BEGIN
  delivered_status_id := symbolika_order_status_id(U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d');

  IF NEW.shipping_method = 'office_pickup' THEN
    NEW.delivery_status := NULL;
  ELSE
    NEW.office_status := 'not_in_office';

    IF delivered_status_id IS NOT NULL
       AND NEW.order_status = delivered_status_id THEN
      NEW.delivery_status := 'delivered';
    ELSIF TG_OP = 'INSERT'
       OR NEW.shipping_method IS DISTINCT FROM OLD.shipping_method THEN
      NEW.delivery_status := COALESCE(NULLIF(NEW.delivery_status, ''), 'pending');
    ELSE
      NEW.delivery_status := COALESCE(NULLIF(NEW.delivery_status, ''), OLD.delivery_status, 'pending');
    END IF;

    IF NEW.delivery_status = 'delivered'
       AND delivered_status_id IS NOT NULL THEN
      NEW.order_status := delivered_status_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_normalize_order_delivery ON orders;
CREATE TRIGGER symbolika_normalize_order_delivery
BEFORE INSERT OR UPDATE OF shipping_method, delivery_status, order_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_normalize_order_delivery_trigger();

-- The production database acquired delivery_status after orders_overview had
-- already been created. Install the current synchronizer explicitly so every
-- later refresh copies this field as well.
CREATE OR REPLACE FUNCTION sync_orders_overview(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM orders_overview_items WHERE orders_overview = order_id;
  DELETE FROM orders_overview WHERE id = order_id;

  INSERT INTO orders_overview (
    id, order_number, date, deadline, customer, customer_company, customer_display, manager_name,
    order_status, order_status_name, office_status, delivery_status,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due,
    completion_percent, completion_missing_count, completion_missing,
    work_completion_percent, work_completion_missing_count, work_completion_missing
  )
  SELECT
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    o.customer_company,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
    e.full_name,
    o.order_status,
    os.name,
    o.office_status,
    o.delivery_status,
    o.shipping_method,
    CASE o.shipping_method
      WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
      WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
      WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
      ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
    END,
    o.order_sum,
    o.paid_amount,
    o.payment_due,
    completion.completion_percent,
    completion.completion_missing_count,
    completion.completion_missing,
    work_completion.work_completion_percent,
    work_completion.work_completion_missing_count,
    work_completion.work_completion_missing
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  LEFT JOIN LATERAL symbolika_order_completion(o.id) completion ON true
  LEFT JOIN LATERAL symbolika_order_work_completion(o.id) work_completion ON true
  WHERE o.id = order_id;

  UPDATE orders_overview
     SET order_link = id
   WHERE id = order_id;

  INSERT INTO orders_overview_items (id, orders_overview, product_name, quantity)
  SELECT oi.id, oi."order", oi.product_name, oi.quantity
    FROM orders_items oi
   WHERE oi."order" = order_id
     AND EXISTS (SELECT 1 FROM orders_overview overview WHERE overview.id = order_id);

  PERFORM refresh_orders_due_tables();
  PERFORM refresh_customer_reconciliation();
END;
$$;

-- Repair historical records and every stale overview row in one migration.
UPDATE orders order_row
   SET delivery_status = 'delivered',
       office_status = 'not_in_office'
  FROM order_statuses status_row
 WHERE status_row.id = order_row.order_status
   AND status_row.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
   AND order_row.shipping_method IS DISTINCT FROM 'office_pickup'
   AND (
     order_row.delivery_status IS DISTINCT FROM 'delivered'
     OR order_row.office_status IS DISTINCT FROM 'not_in_office'
   );

UPDATE orders_overview overview
   SET delivery_status = source.delivery_status,
       office_status = source.office_status
  FROM orders source
 WHERE source.id = overview.id
   AND (
     overview.delivery_status IS DISTINCT FROM source.delivery_status
     OR overview.office_status IS DISTINCT FROM source.office_status
   );

COMMIT;

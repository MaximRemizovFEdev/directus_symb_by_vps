BEGIN;

-- Screen printing is an internal contractor, so its settlement cost remains
-- zero. The costing summary must use the separate operational cost field.
CREATE OR REPLACE FUNCTION sync_contractor_costing_item(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO contractor_costing (
    id, "order", order_link, order_number, date, order_deadline, customer, customer_company,
    manager_employee, product_name, quantity, price_per_unit, order_sum, product_category,
    product_subcategory, application_method, blank_source, blank_ordered, contractor_1,
    contractor_2, contractor_1_cost, contractor_2_cost, unit_cost, total_cost,
    manager_commission_sum, tax_sum, profit_sum, margin_percent, item_status, production_status, deadline
  )
  SELECT
    oi.id, oi."order", oi.order_link, o.order_number, o.date, o.deadline,
    o.customer, o.customer_company, o.manager_employee, oi.product_name, oi.quantity,
    oi.price_per_unit, oi.order_sum, oi.product_category, oi.product_subcategory,
    oi.application_method, COALESCE(oi.blank_source, 'none'), COALESCE(oi.blank_ordered, false),
    oi.contractor_1, oi.contractor_2,
    CASE WHEN COALESCE(c1.name, '') ILIKE '%шелкограф%'
      THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE oi.contractor_1_cost END,
    CASE WHEN COALESCE(c2.name, '') ILIKE '%шелкограф%'
      THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE oi.contractor_2_cost END,
    costs.effective_unit_cost,
    costs.effective_total_cost,
    oi.manager_commission_sum,
    oi.tax_sum,
    ROUND(COALESCE(oi.profit_sum, 0) + COALESCE(oi.total_cost, 0) - costs.effective_total_cost, 2),
    CASE WHEN COALESCE(oi.order_sum, 0) > 0 THEN ROUND(
      (COALESCE(oi.profit_sum, 0) + COALESCE(oi.total_cost, 0) - costs.effective_total_cost)
        / oi.order_sum * 100,
      2
    ) ELSE 0 END,
    oi.item_status, oi.production_status, oi.deadline
  FROM orders_items oi
  LEFT JOIN orders o ON o.id = oi."order"
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  CROSS JOIN LATERAL (
    SELECT
      ROUND(
        (CASE WHEN COALESCE(c1.name, '') ILIKE '%шелкограф%'
          THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE COALESCE(oi.contractor_1_cost, 0) END)
        + (CASE WHEN COALESCE(c2.name, '') ILIKE '%шелкограф%'
          THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE COALESCE(oi.contractor_2_cost, 0) END),
        2
      ) AS effective_unit_cost,
      ROUND(
        COALESCE(oi.quantity, 0) * (
          (CASE WHEN COALESCE(c1.name, '') ILIKE '%шелкограф%'
            THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE COALESCE(oi.contractor_1_cost, 0) END)
          + (CASE WHEN COALESCE(c2.name, '') ILIKE '%шелкограф%'
            THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE COALESCE(oi.contractor_2_cost, 0) END)
        ),
        2
      ) AS effective_total_cost
  ) costs
  WHERE oi.id = item_id
  ON CONFLICT (id) DO UPDATE SET
    "order" = EXCLUDED."order", order_link = EXCLUDED.order_link,
    order_number = EXCLUDED.order_number, date = EXCLUDED.date,
    order_deadline = EXCLUDED.order_deadline, customer = EXCLUDED.customer,
    customer_company = EXCLUDED.customer_company, manager_employee = EXCLUDED.manager_employee,
    product_name = EXCLUDED.product_name, quantity = EXCLUDED.quantity,
    price_per_unit = EXCLUDED.price_per_unit, order_sum = EXCLUDED.order_sum,
    product_category = EXCLUDED.product_category, product_subcategory = EXCLUDED.product_subcategory,
    application_method = EXCLUDED.application_method, blank_source = EXCLUDED.blank_source,
    blank_ordered = EXCLUDED.blank_ordered, contractor_1 = EXCLUDED.contractor_1,
    contractor_2 = EXCLUDED.contractor_2, contractor_1_cost = EXCLUDED.contractor_1_cost,
    contractor_2_cost = EXCLUDED.contractor_2_cost, unit_cost = EXCLUDED.unit_cost,
    total_cost = EXCLUDED.total_cost, manager_commission_sum = EXCLUDED.manager_commission_sum,
    tax_sum = EXCLUDED.tax_sum, profit_sum = EXCLUDED.profit_sum,
    margin_percent = EXCLUDED.margin_percent, item_status = EXCLUDED.item_status,
    production_status = EXCLUDED.production_status, deadline = EXCLUDED.deadline;
END;
$$;

CREATE OR REPLACE FUNCTION push_contractor_costing_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  contractor_1_is_screen boolean;
  contractor_2_is_screen boolean;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name ILIKE '%шелкограф%', false)
    INTO contractor_1_is_screen FROM contractors WHERE id = NEW.contractor_1;
  SELECT COALESCE(name ILIKE '%шелкограф%', false)
    INTO contractor_2_is_screen FROM contractors WHERE id = NEW.contractor_2;

  UPDATE orders_items
  SET
    contractor_1 = NEW.contractor_1,
    contractor_2 = NEW.contractor_2,
    blank_source = COALESCE(NEW.blank_source, 'none'),
    blank_ordered = COALESCE(NEW.blank_ordered, false),
    contractor_1_cost = CASE WHEN COALESCE(contractor_1_is_screen, false)
      THEN contractor_1_cost ELSE COALESCE(NEW.contractor_1_cost, 0) END,
    contractor_2_cost = CASE WHEN COALESCE(contractor_2_is_screen, false)
      THEN contractor_2_cost ELSE COALESCE(NEW.contractor_2_cost, 0) END,
    screen_printing_cost_per_unit = CASE
      WHEN COALESCE(contractor_1_is_screen, false) THEN NEW.contractor_1_cost
      WHEN COALESCE(contractor_2_is_screen, false) THEN NEW.contractor_2_cost
      ELSE screen_printing_cost_per_unit
    END
  WHERE id = NEW.id
    AND (
      contractor_1 IS DISTINCT FROM NEW.contractor_1
      OR contractor_2 IS DISTINCT FROM NEW.contractor_2
      OR blank_source IS DISTINCT FROM COALESCE(NEW.blank_source, 'none')
      OR blank_ordered IS DISTINCT FROM COALESCE(NEW.blank_ordered, false)
      OR (NOT COALESCE(contractor_1_is_screen, false)
        AND contractor_1_cost IS DISTINCT FROM COALESCE(NEW.contractor_1_cost, 0))
      OR (NOT COALESCE(contractor_2_is_screen, false)
        AND contractor_2_cost IS DISTINCT FROM COALESCE(NEW.contractor_2_cost, 0))
      OR (COALESCE(contractor_1_is_screen, false)
        AND screen_printing_cost_per_unit IS DISTINCT FROM NEW.contractor_1_cost)
      OR (COALESCE(contractor_2_is_screen, false)
        AND screen_printing_cost_per_unit IS DISTINCT FROM NEW.contractor_2_cost)
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contractor_costing_sync_item ON orders_items;
CREATE TRIGGER contractor_costing_sync_item
AFTER INSERT OR DELETE OR UPDATE OF
  "order", order_link, product_name, quantity, price_per_unit, order_sum,
  product_category, product_subcategory, application_method,
  blank_source, blank_ordered, contractor_1, contractor_2,
  contractor_1_cost, contractor_2_cost, screen_printing_cost_per_unit, unit_cost, total_cost,
  manager_commission_sum, tax_sum, profit_sum, margin_percent,
  item_status, production_status, deadline
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_costing_item_trigger();

SELECT sync_contractor_costing_item(id) FROM orders_items;

COMMIT;

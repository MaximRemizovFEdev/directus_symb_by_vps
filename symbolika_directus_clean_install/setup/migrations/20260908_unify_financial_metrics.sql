BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

CREATE OR REPLACE FUNCTION symbolika_recalc_item_financials_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  contractor_1_internal boolean := false;
  contractor_2_internal boolean := false;
  contractor_1_screen boolean := false;
  contractor_2_screen boolean := false;
  effective_unit_cost numeric := 0;
BEGIN
  IF NEW.contractor_1 IS NOT NULL THEN
    SELECT
      COALESCE(is_internal_production, false),
      COALESCE(name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
    INTO contractor_1_internal, contractor_1_screen
    FROM contractors
    WHERE id = NEW.contractor_1;
  END IF;

  IF NEW.contractor_2 IS NOT NULL THEN
    SELECT
      COALESCE(is_internal_production, false),
      COALESCE(name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
    INTO contractor_2_internal, contractor_2_screen
    FROM contractors
    WHERE id = NEW.contractor_2;
  END IF;

  effective_unit_cost :=
    CASE WHEN COALESCE(contractor_1_internal, false) OR COALESCE(contractor_1_screen, false)
      THEN 0 ELSE COALESCE(NEW.contractor_1_cost, 0) END
    + CASE WHEN COALESCE(contractor_2_internal, false) OR COALESCE(contractor_2_screen, false)
      THEN 0 ELSE COALESCE(NEW.contractor_2_cost, 0) END
    + CASE WHEN COALESCE(contractor_1_screen, false)
             OR COALESCE(contractor_2_screen, false)
             OR COALESCE(NEW.internal_route_screen, false)
      THEN COALESCE(NEW.screen_printing_cost_per_unit, 0) ELSE 0 END;

  NEW.order_sum := ROUND(COALESCE(NEW.quantity, 0) * COALESCE(NEW.price_per_unit, 0), 2);
  NEW.unit_cost := ROUND(effective_unit_cost, 2);
  NEW.total_cost := ROUND(COALESCE(NEW.quantity, 0) * effective_unit_cost, 2);
  NEW.manager_commission_sum := ROUND(NEW.order_sum * COALESCE(NEW.manager_percent, 0) / 100, 2);
  NEW.profit_sum := ROUND(
    NEW.order_sum - NEW.total_cost - NEW.manager_commission_sum - COALESCE(NEW.tax_sum, 0),
    2
  );
  NEW.margin_percent := CASE WHEN NEW.order_sum > 0
    THEN ROUND(NEW.profit_sum / NEW.order_sum * 100, 2)
    ELSE 0
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_recalc_item_financials ON orders_items;
CREATE TRIGGER symbolika_recalc_item_financials
BEFORE INSERT OR UPDATE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_recalc_item_financials_trigger();

CREATE OR REPLACE FUNCTION symbolika_sync_canonical_contractor_costing_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  UPDATE contractor_costing costing
  SET unit_cost = NEW.unit_cost,
      total_cost = NEW.total_cost,
      manager_commission_sum = NEW.manager_commission_sum,
      tax_sum = NEW.tax_sum,
      profit_sum = NEW.profit_sum,
      margin_percent = NEW.margin_percent
  WHERE costing.id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_sync_canonical_contractor_costing ON orders_items;
CREATE TRIGGER symbolika_sync_canonical_contractor_costing
AFTER INSERT OR UPDATE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_sync_canonical_contractor_costing_trigger();

-- Backfill in sets with projection triggers temporarily disabled. Re-saving
-- rows one by one would rebuild reconciliation tables for every position and
-- can exceed the deployment timeout on a live database.
ALTER TABLE orders_items DISABLE TRIGGER USER;

WITH calculated AS (
  SELECT
    oi.id,
    ROUND(COALESCE(oi.quantity, 0) * COALESCE(oi.price_per_unit, 0), 2) AS order_sum,
    ROUND(
      CASE WHEN COALESCE(c1.is_internal_production, false)
                  OR COALESCE(c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
        THEN 0 ELSE COALESCE(oi.contractor_1_cost, 0) END
      + CASE WHEN COALESCE(c2.is_internal_production, false)
                    OR COALESCE(c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
        THEN 0 ELSE COALESCE(oi.contractor_2_cost, 0) END
      + CASE WHEN COALESCE(c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
                     OR COALESCE(c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
                     OR COALESCE(oi.internal_route_screen, false)
        THEN COALESCE(oi.screen_printing_cost_per_unit, 0) ELSE 0 END,
      2
    ) AS unit_cost,
    COALESCE(oi.quantity, 0) AS quantity,
    COALESCE(oi.manager_percent, 0) AS manager_percent,
    COALESCE(oi.tax_sum, 0) AS tax_sum
  FROM orders_items oi
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
), totals AS (
  SELECT
    calculated.*,
    ROUND(calculated.quantity * calculated.unit_cost, 2) AS total_cost,
    ROUND(calculated.order_sum * calculated.manager_percent / 100, 2) AS manager_commission_sum
  FROM calculated
)
UPDATE orders_items item
SET order_sum = totals.order_sum,
    unit_cost = totals.unit_cost,
    total_cost = totals.total_cost,
    manager_commission_sum = totals.manager_commission_sum,
    profit_sum = ROUND(totals.order_sum - totals.total_cost - totals.manager_commission_sum - totals.tax_sum, 2),
    margin_percent = CASE WHEN totals.order_sum > 0 THEN ROUND(
      (totals.order_sum - totals.total_cost - totals.manager_commission_sum - totals.tax_sum)
        / totals.order_sum * 100,
      2
    ) ELSE 0 END
FROM totals
WHERE item.id = totals.id;

ALTER TABLE orders_items ENABLE TRIGGER USER;

ALTER TABLE orders DISABLE TRIGGER USER;

WITH totals AS (
  SELECT
    o.id,
    COALESCE(SUM(oi.order_sum) FILTER (
      WHERE symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ), 0)::numeric(10,2) AS order_sum,
    COALESCE(SUM(oi.total_cost) FILTER (
      WHERE symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ), 0)::numeric(10,2) AS items_total_cost,
    COALESCE(SUM(oi.manager_commission_sum) FILTER (
      WHERE symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ), 0)::numeric(10,2) AS manager_commission_sum,
    COALESCE(SUM(oi.tax_sum) FILTER (
      WHERE symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ), 0)::numeric(10,2) AS tax_sum
  FROM orders o
  LEFT JOIN orders_items oi ON oi."order" = o.id
  GROUP BY o.id
)
UPDATE orders o
SET order_sum = totals.order_sum,
    items_total_cost = totals.items_total_cost,
    items_manager_commission_sum = totals.manager_commission_sum,
    items_tax_sum = totals.tax_sum,
    profit_sum = ROUND(totals.order_sum - totals.items_total_cost - totals.manager_commission_sum - totals.tax_sum, 2),
    margin_percent = CASE WHEN totals.order_sum > 0 THEN ROUND(
      (totals.order_sum - totals.items_total_cost - totals.manager_commission_sum - totals.tax_sum)
        / totals.order_sum * 100,
      2
    ) ELSE 0 END,
    payment_due = totals.order_sum - COALESCE(o.paid_amount, 0),
    office_payment_due = CASE WHEN o.payment_on_receipt
      THEN totals.order_sum - COALESCE(o.paid_amount, 0) ELSE 0 END
FROM totals
WHERE o.id = totals.id;

ALTER TABLE orders ENABLE TRIGGER USER;

ALTER TABLE contractor_costing DISABLE TRIGGER USER;

UPDATE contractor_costing costing
SET order_sum = item.order_sum,
    unit_cost = item.unit_cost,
    total_cost = item.total_cost,
    manager_commission_sum = item.manager_commission_sum,
    tax_sum = item.tax_sum,
    profit_sum = item.profit_sum,
    margin_percent = item.margin_percent
FROM orders_items item
WHERE costing.id = item.id;

ALTER TABLE contractor_costing ENABLE TRIGGER USER;

UPDATE orders_overview overview
SET order_sum = source.order_sum,
    paid_amount = source.paid_amount,
    payment_due = source.payment_due
FROM orders source
WHERE overview.id = source.id;

DO $$
DECLARE row_item record;
BEGIN
  FOR row_item IN SELECT id FROM customers LOOP
    PERFORM symbolika_recalc_customer_operation_balance(row_item.id);
  END LOOP;
  FOR row_item IN SELECT id FROM customer_companies LOOP
    PERFORM symbolika_recalc_company_operation_balance(row_item.id);
  END LOOP;
  FOR row_item IN SELECT id FROM orders LOOP
    PERFORM sync_my_order_buckets(row_item.id);
  END LOOP;
END;
$$;

SELECT refresh_orders_due_tables();
SELECT refresh_customer_reconciliation();

COMMIT;

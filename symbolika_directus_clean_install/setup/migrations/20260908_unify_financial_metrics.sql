BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

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

-- Re-save every position through the canonical calculator. Existing orders
-- with a contractor cost or screen-printing cost but stale zero totals are
-- repaired here as part of the migration.
UPDATE orders_items
SET quantity = quantity;

UPDATE contractor_costing costing
SET unit_cost = item.unit_cost,
    total_cost = item.total_cost,
    manager_commission_sum = item.manager_commission_sum,
    tax_sum = item.tax_sum,
    profit_sum = item.profit_sum,
    margin_percent = item.margin_percent
FROM orders_items item
WHERE costing.id = item.id;

DO $$
DECLARE
  existing_order_id integer;
BEGIN
  FOR existing_order_id IN SELECT id FROM orders ORDER BY id LOOP
    PERFORM recalc_order_payment_totals(existing_order_id);
  END LOOP;
END;
$$;

COMMIT;

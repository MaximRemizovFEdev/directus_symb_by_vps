BEGIN;

-- Preserve the currently installed due-bucket implementation and place a
-- serialized wrapper in front of it. This keeps the migration small and does
-- not duplicate the long materialization query from the bootstrap SQL.
DO $$
BEGIN
  IF to_regprocedure('refresh_orders_due_tables()') IS NULL THEN
    RAISE EXCEPTION 'refresh_orders_due_tables() is required before this migration';
  END IF;

  IF to_regprocedure('symbolika_refresh_orders_due_tables_body()') IS NULL THEN
    ALTER FUNCTION refresh_orders_due_tables()
      RENAME TO symbolika_refresh_orders_due_tables_body;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION refresh_orders_due_tables()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('symbolika_orders_due_refresh'));
  PERFORM symbolika_refresh_orders_due_tables_body();
END;
$$;

-- A write must not wait for a second, identical rebuild of the admin-only
-- consistency list. The refresh function itself retains its blocking lock for
-- explicit/manual checks; only automatic duplicate trigger runs are skipped.
CREATE OR REPLACE FUNCTION symbolika_refresh_automation_issues_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('symbolika_automation_issues_refresh')) THEN
    RETURN NULL;
  END IF;

  PERFORM refresh_symbolika_automation_issues();
  RETURN NULL;
END;
$$;

-- The costing table is a derived administrative projection. Refresh it only
-- when one of its source columns changes. Running it for URL, office-status or
-- calculated order updates made unrelated transactions contend for the same
-- derived row and could deadlock with production synchronization.
DROP TRIGGER IF EXISTS contractor_costing_sync_item ON orders_items;
CREATE TRIGGER contractor_costing_sync_item
AFTER INSERT OR DELETE OR UPDATE OF
  "order", order_link, product_name, quantity, price_per_unit, order_sum,
  product_category, product_subcategory, application_method,
  blank_source, blank_ordered, contractor_1, contractor_2,
  contractor_1_cost, contractor_2_cost, unit_cost, total_cost,
  manager_commission_sum, tax_sum, profit_sum, margin_percent,
  item_status, production_status, deadline
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_costing_item_trigger();

DROP TRIGGER IF EXISTS contractor_costing_sync_order ON orders;
CREATE TRIGGER contractor_costing_sync_order
AFTER DELETE OR UPDATE OF
  order_number, date, deadline, customer, customer_company, manager_employee
ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_costing_order_trigger();

COMMIT;

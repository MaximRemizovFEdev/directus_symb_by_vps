BEGIN;

ALTER TABLE screen_printing_work
  ADD COLUMN IF NOT EXISTS application_contractor_slot smallint,
  ADD COLUMN IF NOT EXISTS application_cost_per_unit numeric(14,2),
  ADD COLUMN IF NOT EXISTS application_cost_total numeric(14,2);

-- Keep the compact screen-printing costing summary synchronized with the
-- order item without replacing the larger work-routing function on a live DB.
CREATE OR REPLACE FUNCTION symbolika_refresh_screen_application_cost(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE screen_printing_work spw
     SET application_contractor_slot = CASE
           WHEN c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%' THEN 2
           ELSE 1
         END,
         application_cost_per_unit = CASE
           WHEN c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%' THEN oi.contractor_2_cost
           ELSE oi.contractor_1_cost
         END,
         application_cost_total = COALESCE(oi.quantity, 0) * COALESCE(
           CASE
             WHEN c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%' THEN oi.contractor_2_cost
             ELSE oi.contractor_1_cost
           END,
           0
         )
    FROM orders_items oi
    LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
   WHERE spw.id = oi.id
     AND oi.id = item_id;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_refresh_screen_application_cost_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM symbolika_refresh_screen_application_cost(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zz_symbolika_sync_screen_application_cost ON orders_items;
CREATE TRIGGER zz_symbolika_sync_screen_application_cost
AFTER INSERT OR UPDATE OF quantity, contractor_1, contractor_2, contractor_1_cost, contractor_2_cost
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_refresh_screen_application_cost_trigger();

CREATE OR REPLACE FUNCTION push_screen_application_cost_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.application_cost_per_unit IS NOT DISTINCT FROM OLD.application_cost_per_unit THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.application_contractor_slot, 1) = 2 THEN
    UPDATE orders_items
       SET contractor_2_cost = NEW.application_cost_per_unit
     WHERE id = NEW.id
       AND contractor_2_cost IS DISTINCT FROM NEW.application_cost_per_unit;
  ELSE
    UPDATE orders_items
       SET contractor_1_cost = NEW.application_cost_per_unit
     WHERE id = NEW.id
       AND contractor_1_cost IS DISTINCT FROM NEW.application_cost_per_unit;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS screen_printing_work_cost_push_update ON screen_printing_work;
CREATE TRIGGER screen_printing_work_cost_push_update
AFTER UPDATE OF application_cost_per_unit ON screen_printing_work
FOR EACH ROW
EXECUTE FUNCTION push_screen_application_cost_update();

DO $$
DECLARE
  item record;
BEGIN
  FOR item IN SELECT id FROM screen_printing_work LOOP
    PERFORM symbolika_refresh_screen_application_cost(item.id);
  END LOOP;
END;
$$;

UPDATE directus_permissions
   SET fields = CASE
     WHEN action = 'read' THEN 'id,order,order_number,order_link,customer_name,customer_company_name,manager_employee,product_name,quantity,date,deadline,item_status,office_status,technical_task_text,production_comment,url,production_status,application_contractor_slot,application_cost_per_unit,application_cost_total'
     WHEN action = 'update' THEN 'production_status,production_comment,application_cost_per_unit'
     ELSE fields
   END
 WHERE collection = 'screen_printing_work'
   AND policy = '00000000-0000-4000-8000-000000000206'
   AND action IN ('read', 'update');

COMMIT;

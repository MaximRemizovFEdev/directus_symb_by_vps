BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Internal workshop contractor costs are intentionally forced to zero. Keep
-- the operational screen-printing cost in its own source field instead of a
-- contractor cost that the normalization trigger immediately clears.
ALTER TABLE orders_items
  ADD COLUMN IF NOT EXISTS screen_printing_cost_per_unit numeric(14,2);

UPDATE orders_items oi
   SET screen_printing_cost_per_unit = spw.application_cost_per_unit
  FROM screen_printing_work spw
 WHERE spw.id = oi.id
   AND spw.application_cost_per_unit IS NOT NULL
   AND oi.screen_printing_cost_per_unit IS NULL;

CREATE OR REPLACE FUNCTION symbolika_refresh_screen_application_cost(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE screen_printing_work spw
     SET application_cost_per_unit = oi.screen_printing_cost_per_unit,
         application_cost_total = COALESCE(oi.quantity, 0)
           * COALESCE(oi.screen_printing_cost_per_unit, 0)
    FROM orders_items oi
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

CREATE OR REPLACE FUNCTION push_screen_application_cost_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.application_cost_per_unit IS NOT DISTINCT FROM OLD.application_cost_per_unit THEN
    RETURN NEW;
  END IF;

  UPDATE orders_items
     SET screen_printing_cost_per_unit = NEW.application_cost_per_unit
   WHERE id = NEW.id
     AND screen_printing_cost_per_unit IS DISTINCT FROM NEW.application_cost_per_unit;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zz_symbolika_sync_screen_application_cost ON orders_items;
CREATE TRIGGER zz_symbolika_sync_screen_application_cost
AFTER INSERT OR UPDATE OF quantity, contractor_1, contractor_2,
  contractor_1_cost, contractor_2_cost, screen_printing_cost_per_unit
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_refresh_screen_application_cost_trigger();

DO $$
DECLARE
  item record;
BEGIN
  FOR item IN SELECT id FROM screen_printing_work LOOP
    PERFORM symbolika_refresh_screen_application_cost(item.id);
  END LOOP;
END;
$$;

COMMIT;

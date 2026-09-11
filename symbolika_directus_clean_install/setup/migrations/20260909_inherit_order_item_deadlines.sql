BEGIN;

CREATE OR REPLACE FUNCTION symbolika_inherit_order_item_deadline()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  previous_order_deadline timestamp without time zone;
  next_order_deadline timestamp without time zone;
BEGIN
  IF NEW."order" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT deadline
    INTO next_order_deadline
    FROM orders
   WHERE id = NEW."order";

  IF TG_OP = 'INSERT' THEN
    IF NEW.deadline IS NULL THEN
      NEW.deadline := next_order_deadline;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW."order" IS DISTINCT FROM OLD."order" THEN
    SELECT deadline
      INTO previous_order_deadline
      FROM orders
     WHERE id = OLD."order";

    IF NEW.deadline IS NULL
       OR NEW.deadline::date IS NOT DISTINCT FROM previous_order_deadline::date THEN
      NEW.deadline := next_order_deadline;
    END IF;
  ELSIF NEW.deadline IS NULL THEN
    NEW.deadline := next_order_deadline;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_inherit_order_item_deadline ON orders_items;
CREATE TRIGGER symbolika_inherit_order_item_deadline
BEFORE INSERT OR UPDATE OF "order", deadline ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_inherit_order_item_deadline();

CREATE OR REPLACE FUNCTION symbolika_sync_order_deadline_to_items()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.deadline IS NOT DISTINCT FROM OLD.deadline THEN
    RETURN NEW;
  END IF;

  UPDATE orders_items
     SET deadline = NEW.deadline
   WHERE "order" = NEW.id
     AND (
       deadline IS NULL
       OR deadline::date IS NOT DISTINCT FROM OLD.deadline::date
     );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_sync_order_deadline_to_items ON orders;
CREATE TRIGGER symbolika_sync_order_deadline_to_items
AFTER UPDATE OF deadline ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_sync_order_deadline_to_items();

UPDATE orders_items oi
   SET deadline = o.deadline
  FROM orders o
 WHERE o.id = oi."order"
   AND oi.deadline IS NULL
   AND o.deadline IS NOT NULL;

COMMIT;

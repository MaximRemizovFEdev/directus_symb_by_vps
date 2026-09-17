BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE SEQUENCE IF NOT EXISTS orders_order_number_seq;

-- Serialize the short sequence initialization/backfill window with order
-- writes. The transaction keeps reads available.
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;

CREATE OR REPLACE FUNCTION symbolika_assign_order_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NULLIF(btrim(NEW.order_number), '') IS NULL THEN
    NEW.order_number := 'SO-' || lpad(nextval('orders_order_number_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_assign_order_number_before_write ON orders;
CREATE TRIGGER symbolika_assign_order_number_before_write
BEFORE INSERT OR UPDATE OF order_number ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_assign_order_number();

DO $$
DECLARE
  max_number bigint;
  missing_order record;
BEGIN
  SELECT COALESCE(max((regexp_match(order_number, '([0-9]+)$'))[1]::bigint), 0)
  INTO max_number
  FROM orders
  WHERE NULLIF(btrim(order_number), '') IS NOT NULL;

  IF max_number > 0 THEN
    PERFORM setval('orders_order_number_seq', max_number, true);
  ELSE
    PERFORM setval('orders_order_number_seq', 1, false);
  END IF;

  FOR missing_order IN
    SELECT id FROM orders
    WHERE NULLIF(btrim(order_number), '') IS NULL
    ORDER BY id
  LOOP
    UPDATE orders SET order_number = NULL WHERE id = missing_order.id;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS orders_order_number_uidx
  ON orders(order_number)
  WHERE NULLIF(btrim(order_number), '') IS NOT NULL;

COMMIT;

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION recalc_order_office_status(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  items_count integer;
  all_issued boolean;
  all_in_office boolean;
  has_not_in_office boolean;
  has_arrived boolean;
  next_status character varying(255);
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.id = order_id
      AND o.shipping_method = 'office_pickup'
  ) THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO items_count
  FROM orders_items oi
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND COALESCE(pc.office_applicable, true);

  IF items_count = 0 THEN
    RETURN;
  END IF;

  SELECT
    bool_and(office_status = 'issued'),
    bool_and(office_status IN ('in_office', 'issued')),
    bool_or(COALESCE(office_status, 'not_in_office') = 'not_in_office'),
    bool_or(office_status IN ('in_office', 'issued'))
  INTO all_issued, all_in_office, has_not_in_office, has_arrived
  FROM orders_items oi
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND COALESCE(pc.office_applicable, true);

  IF all_issued THEN
    next_status := 'issued';
  ELSIF all_in_office THEN
    next_status := 'in_office';
  ELSIF has_arrived AND has_not_in_office THEN
    next_status := 'partially_in_office';
  ELSE
    next_status := 'not_in_office';
  END IF;

  UPDATE orders
     SET office_status = next_status
   WHERE id = order_id
     AND office_status IS DISTINCT FROM next_status;

  PERFORM sync_office_issue_order(order_id);
  PERFORM sync_office_issue_items(order_id);
END;
$$;

DO $$
DECLARE
  order_row record;
BEGIN
  FOR order_row IN
    SELECT id FROM orders WHERE shipping_method = 'office_pickup'
  LOOP
    PERFORM recalc_order_office_status(order_row.id);
  END LOOP;
END;
$$;

COMMIT;

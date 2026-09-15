BEGIN;

CREATE OR REPLACE FUNCTION symbolika_apply_delivery_status_to_items_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  ready_production_status integer;
BEGIN
  IF NEW.shipping_method = 'office_pickup'
     OR NEW.delivery_status IS DISTINCT FROM 'delivered'
     OR NEW.delivery_status IS NOT DISTINCT FROM OLD.delivery_status THEN
    RETURN NEW;
  END IF;

  SELECT status_row.id INTO ready_production_status
  FROM production_statuses status_row
  WHERE status_row.name = U&'\0413\043e\0442\043e\0432'
  ORDER BY status_row.id
  LIMIT 1;

  -- The item trigger derives `ready` whenever production_status changes. Do
  -- that transition first and persist `delivered` in a separate statement.
  IF ready_production_status IS NOT NULL THEN
    UPDATE orders_items
       SET production_status = ready_production_status
     WHERE "order" = NEW.id
       AND symbolika_normalize_item_status(item_status) <> 'cancelled'
       AND production_status IS DISTINCT FROM ready_production_status;
  END IF;

  UPDATE orders_items
     SET item_status = 'delivered',
         office_status = 'not_in_office',
         shipping_method = NEW.shipping_method
   WHERE "order" = NEW.id
     AND symbolika_normalize_item_status(item_status) <> 'cancelled'
     AND (
       symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
       OR office_status IS DISTINCT FROM 'not_in_office'
       OR shipping_method IS DISTINCT FROM NEW.shipping_method
     );

  RETURN NEW;
END;
$$;

-- Repair historical rows without firing the expensive per-item refresh tree.
-- All affected derived item buckets are mirrored explicitly below.
SET LOCAL session_replication_role = 'replica';
UPDATE orders_items item
   SET item_status = 'delivered',
       office_status = 'not_in_office',
       shipping_method = order_row.shipping_method,
       production_status = ready_status.id
  FROM orders order_row
  JOIN order_statuses order_status ON order_status.id = order_row.order_status
  CROSS JOIN LATERAL (
    SELECT id
      FROM production_statuses
     WHERE name = U&'\0413\043e\0442\043e\0432'
     ORDER BY id
     LIMIT 1
  ) ready_status
 WHERE item."order" = order_row.id
   AND order_status.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
   AND order_row.shipping_method IS DISTINCT FROM 'office_pickup'
   AND symbolika_normalize_item_status(item.item_status) <> 'cancelled'
   AND (
     symbolika_normalize_item_status(item.item_status) IS DISTINCT FROM 'delivered'
     OR item.office_status IS DISTINCT FROM 'not_in_office'
     OR item.shipping_method IS DISTINCT FROM order_row.shipping_method
     OR item.production_status IS DISTINCT FROM ready_status.id
   );

UPDATE my_orders_completed_items bucket
   SET item_status = source.item_status,
       production_status = source.production_status,
       office_status = source.office_status
  FROM orders_items source
 WHERE source.id = bucket.id
   AND (
     bucket.item_status IS DISTINCT FROM source.item_status
     OR bucket.production_status IS DISTINCT FROM source.production_status
     OR bucket.office_status IS DISTINCT FROM source.office_status
   );

UPDATE my_orders_unpaid_items bucket
   SET item_status = source.item_status,
       production_status = source.production_status,
       office_status = source.office_status
  FROM orders_items source
 WHERE source.id = bucket.id
   AND (
     bucket.item_status IS DISTINCT FROM source.item_status
     OR bucket.production_status IS DISTINCT FROM source.production_status
     OR bucket.office_status IS DISTINCT FROM source.office_status
   );

UPDATE my_orders_in_work_items bucket
   SET item_status = source.item_status,
       production_status = source.production_status,
       office_status = source.office_status
  FROM orders_items source
 WHERE source.id = bucket.id
   AND (
     bucket.item_status IS DISTINCT FROM source.item_status
     OR bucket.production_status IS DISTINCT FROM source.production_status
     OR bucket.office_status IS DISTINCT FROM source.office_status
   );
SET LOCAL session_replication_role = 'origin';

COMMIT;

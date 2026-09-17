BEGIN;

SET LOCAL lock_timeout = '15s';

ALTER TABLE my_orders_in_work
  ADD COLUMN IF NOT EXISTS delivery_status character varying(32);
ALTER TABLE my_orders_completed
  ADD COLUMN IF NOT EXISTS delivery_status character varying(32);
ALTER TABLE my_orders_unpaid
  ADD COLUMN IF NOT EXISTS delivery_status character varying(32);

UPDATE my_orders_in_work bucket
   SET delivery_status = source.delivery_status
  FROM orders source
 WHERE source.id = bucket.id
   AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;

UPDATE my_orders_completed bucket
   SET delivery_status = source.delivery_status
  FROM orders source
 WHERE source.id = bucket.id
   AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;

UPDATE my_orders_unpaid bucket
   SET delivery_status = source.delivery_status
  FROM orders source
 WHERE source.id = bucket.id
   AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;

CREATE OR REPLACE FUNCTION symbolika_refresh_my_order_delivery(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE my_orders_in_work bucket
     SET delivery_status = source.delivery_status
    FROM orders source
   WHERE source.id = order_id
     AND bucket.id = source.id
     AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;

  UPDATE my_orders_completed bucket
     SET delivery_status = source.delivery_status
    FROM orders source
   WHERE source.id = order_id
     AND bucket.id = source.id
     AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;

  UPDATE my_orders_unpaid bucket
     SET delivery_status = source.delivery_status
    FROM orders source
   WHERE source.id = order_id
     AND bucket.id = source.id
     AND bucket.delivery_status IS DISTINCT FROM source.delivery_status;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_refresh_my_order_delivery_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_order_id integer;
  new_order_id integer;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN
    old_order_id := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN OLD.id ELSE NULL END;
    new_order_id := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN NEW.id ELSE NULL END;
  ELSE
    old_order_id := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN OLD."order" ELSE NULL END;
    new_order_id := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN NEW."order" ELSE NULL END;
  END IF;

  PERFORM symbolika_refresh_my_order_delivery(old_order_id);
  IF new_order_id IS DISTINCT FROM old_order_id THEN
    PERFORM symbolika_refresh_my_order_delivery(new_order_id);
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_sync_my_order_delivery_zz ON orders;
CREATE TRIGGER symbolika_sync_my_order_delivery_zz
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_refresh_my_order_delivery_trigger();

DROP TRIGGER IF EXISTS symbolika_sync_my_order_item_delivery_zz ON orders_items;
CREATE TRIGGER symbolika_sync_my_order_item_delivery_zz
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_refresh_my_order_delivery_trigger();

DROP TRIGGER IF EXISTS symbolika_sync_my_order_payment_delivery_zz ON order_payments;
CREATE TRIGGER symbolika_sync_my_order_payment_delivery_zz
AFTER INSERT OR UPDATE OR DELETE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION symbolika_refresh_my_order_delivery_trigger();

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  collections.collection_name,
  'delivery_status',
  NULL,
  'select-dropdown',
  '{"choices":[{"text":"Ожидает доставки","value":"pending"},{"text":"В доставке","value":"in_delivery"},{"text":"Доставлен","value":"delivered"}]}'::json,
  'labels',
  '{"choices":[{"text":"Ожидает доставки","value":"pending","foreground":"#ef9b3f","background":"#ef9b3f22"},{"text":"В доставке","value":"in_delivery","foreground":"#5b9cff","background":"#5b9cff22"},{"text":"Доставлен","value":"delivered","foreground":"#35c98b","background":"#35c98b22"}]}'::json,
  true,
  false,
  12,
  'half',
  json_build_array(json_build_object('language', 'ru-RU', 'translation', 'Статус доставки'))::json,
  false,
  true
FROM (VALUES
  ('my_orders_in_work'),
  ('my_orders_completed'),
  ('my_orders_unpaid')
) AS collections(collection_name)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_fields fields
  WHERE fields.collection = collections.collection_name
    AND fields.field = 'delivery_status'
);

UPDATE directus_permissions
   SET fields = fields || ',delivery_status'
 WHERE collection IN ('my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid')
   AND action = 'read'
   AND fields IS NOT NULL
   AND fields <> '*'
   AND NOT ('delivery_status' = ANY(string_to_array(fields, ',')));

COMMIT;

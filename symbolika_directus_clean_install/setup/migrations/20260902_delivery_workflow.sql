BEGIN;

SET LOCAL lock_timeout = '15s';

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_status character varying(32);

ALTER TABLE orders_overview
  ADD COLUMN IF NOT EXISTS delivery_status character varying(32);

CREATE OR REPLACE FUNCTION symbolika_normalize_order_delivery_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  delivered_status_id integer;
BEGIN
  IF NEW.shipping_method = 'office_pickup' THEN
    NEW.delivery_status := NULL;
  ELSE
    NEW.office_status := 'not_in_office';

    IF TG_OP = 'INSERT'
       OR NEW.shipping_method IS DISTINCT FROM OLD.shipping_method THEN
      NEW.delivery_status := COALESCE(NULLIF(NEW.delivery_status, ''), 'pending');
    ELSE
      NEW.delivery_status := COALESCE(NULLIF(NEW.delivery_status, ''), OLD.delivery_status, 'pending');
    END IF;

    IF NEW.delivery_status = 'delivered' THEN
      delivered_status_id := symbolika_order_status_id(U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d');
      IF delivered_status_id IS NOT NULL THEN
        NEW.order_status := delivered_status_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

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

  SELECT ps.id INTO ready_production_status
  FROM production_statuses ps
  WHERE ps.name = U&'\0413\043e\0442\043e\0432'
  ORDER BY ps.id
  LIMIT 1;

  UPDATE orders_items
     SET item_status = 'delivered',
         office_status = 'not_in_office',
         shipping_method = NEW.shipping_method,
         production_status = COALESCE(ready_production_status, production_status)
   WHERE "order" = NEW.id
     AND symbolika_normalize_item_status(item_status) <> 'cancelled'
     AND (
       symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
       OR office_status IS DISTINCT FROM 'not_in_office'
       OR shipping_method IS DISTINCT FROM NEW.shipping_method
       OR (ready_production_status IS NOT NULL AND production_status IS DISTINCT FROM ready_production_status)
     );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_normalize_order_delivery ON orders;
CREATE TRIGGER symbolika_normalize_order_delivery
BEFORE INSERT OR UPDATE OF shipping_method, delivery_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_normalize_order_delivery_trigger();

DROP TRIGGER IF EXISTS symbolika_apply_delivery_status_to_items ON orders;
CREATE TRIGGER symbolika_apply_delivery_status_to_items
AFTER UPDATE OF delivery_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_delivery_status_to_items_trigger();

UPDATE orders o
   SET delivery_status = CASE
     WHEN o.shipping_method = 'office_pickup' THEN NULL
     WHEN os.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
     ELSE COALESCE(NULLIF(o.delivery_status, ''), 'pending')
   END,
       office_status = CASE
         WHEN o.shipping_method = 'office_pickup' THEN o.office_status
         ELSE 'not_in_office'
       END
  FROM order_statuses os
 WHERE os.id = o.order_status
   AND (
     o.delivery_status IS DISTINCT FROM CASE
       WHEN o.shipping_method = 'office_pickup' THEN NULL
       WHEN os.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
       ELSE COALESCE(NULLIF(o.delivery_status, ''), 'pending')
     END
     OR (
       o.shipping_method IS DISTINCT FROM 'office_pickup'
       AND o.office_status IS DISTINCT FROM 'not_in_office'
     )
   );

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'orders', 'delivery_status', NULL, 'select-dropdown',
  '{"choices":[{"text":"Ожидает доставки","value":"pending"},{"text":"В доставке","value":"in_delivery"},{"text":"Доставлен","value":"delivered"}]}'::json,
  'labels',
  '{"choices":[{"text":"Ожидает доставки","value":"pending","foreground":"#ef9b3f","background":"#ef9b3f22"},{"text":"В доставке","value":"in_delivery","foreground":"#5b9cff","background":"#5b9cff22"},{"text":"Доставлен","value":"delivered","foreground":"#35c98b","background":"#35c98b22"}]}'::json,
  false, false, 8, 'half',
  json_build_array(json_build_object('language','ru-RU','translation','Статус доставки'))::json,
  false, true
WHERE NOT EXISTS (
  SELECT 1 FROM directus_fields WHERE collection = 'orders' AND field = 'delivery_status'
);

UPDATE directus_fields
   SET interface = 'select-dropdown',
       options = '{"choices":[{"text":"Ожидает доставки","value":"pending"},{"text":"В доставке","value":"in_delivery"},{"text":"Доставлен","value":"delivered"}]}'::json,
       display = 'labels',
       display_options = '{"choices":[{"text":"Ожидает доставки","value":"pending","foreground":"#ef9b3f","background":"#ef9b3f22"},{"text":"В доставке","value":"in_delivery","foreground":"#5b9cff","background":"#5b9cff22"},{"text":"Доставлен","value":"delivered","foreground":"#35c98b","background":"#35c98b22"}]}'::json,
       readonly = false,
       hidden = false,
       width = 'half',
       translations = json_build_array(json_build_object('language','ru-RU','translation','Статус доставки'))::json
 WHERE collection = 'orders'
   AND field = 'delivery_status';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'orders_overview', 'delivery_status', NULL, 'select-dropdown',
  '{"choices":[{"text":"Ожидает доставки","value":"pending"},{"text":"В доставке","value":"in_delivery"},{"text":"Доставлен","value":"delivered"}]}'::json,
  'labels', NULL, true, false, 12, 'half',
  json_build_array(json_build_object('language','ru-RU','translation','Статус доставки'))::json,
  false, true
WHERE NOT EXISTS (
  SELECT 1 FROM directus_fields WHERE collection = 'orders_overview' AND field = 'delivery_status'
);

UPDATE directus_permissions
   SET fields = fields || ',delivery_status'
 WHERE collection IN ('orders', 'orders_overview')
   AND action IN ('create', 'read', 'update')
   AND fields IS NOT NULL
   AND fields <> '*'
   AND NOT ('delivery_status' = ANY(string_to_array(fields, ',')));

COMMIT;

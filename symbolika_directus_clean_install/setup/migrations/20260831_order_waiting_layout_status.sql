BEGIN;

INSERT INTO order_statuses (name, sort, is_active)
SELECT status_name, sort_value, true
FROM (VALUES
  (U&'\041d\043e\0432\044b\0439', 1),
  (U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442', 2),
  (U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 3),
  (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 4),
  (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 5),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 6),
  (U&'\0413\043e\0442\043e\0432', 7),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 8),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 9)
) AS required_statuses(status_name, sort_value)
WHERE NOT EXISTS (
  SELECT 1 FROM order_statuses os WHERE os.name = required_statuses.status_name
);

UPDATE order_statuses os
SET sort = required_statuses.sort_value,
    is_active = true
FROM (VALUES
  (U&'\041d\043e\0432\044b\0439', 1),
  (U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442', 2),
  (U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 3),
  (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 4),
  (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 5),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 6),
  (U&'\0413\043e\0442\043e\0432', 7),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 8),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 9)
) AS required_statuses(status_name, sort_value)
WHERE os.name = required_statuses.status_name;

CREATE OR REPLACE FUNCTION symbolika_validate_order_workflow_transition_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_status_name text;
  new_status_name text;
  readiness record;
  transition_allowed boolean := false;
BEGIN
  IF NEW.order_status IS NOT DISTINCT FROM OLD.order_status OR pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT name INTO old_status_name FROM order_statuses WHERE id = OLD.order_status;
  SELECT name INTO new_status_name FROM order_statuses WHERE id = NEW.order_status;

  transition_allowed := CASE
    WHEN old_status_name IN (
      U&'\041d\043e\0432\044b\0439',
      U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442',
      U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
    )
      THEN new_status_name IN (
        U&'\041d\043e\0432\044b\0439',
        U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442',
        U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435',
        U&'\0412 \0440\0430\0431\043e\0442\0435'
      )
    WHEN old_status_name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
      THEN new_status_name IN (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', U&'\0412 \0440\0430\0431\043e\0442\0435')
    WHEN old_status_name IN (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', U&'\0412 \0440\0430\0431\043e\0442\0435')
      THEN new_status_name IN (U&'\0412 \0440\0430\0431\043e\0442\0435', U&'\0413\043e\0442\043e\0432', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d')
    WHEN old_status_name = U&'\0413\043e\0442\043e\0432'
      THEN new_status_name IN (U&'\0413\043e\0442\043e\0432', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d')
    WHEN old_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
      THEN new_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
    ELSE false
  END;

  IF NOT transition_allowed THEN
    RAISE EXCEPTION 'Недопустимый переход статуса заказа: % -> %', COALESCE(old_status_name, '-'), COALESCE(new_status_name, '-');
  END IF;

  IF new_status_name = U&'\0412 \0440\0430\0431\043e\0442\0435'
     AND old_status_name IN (
       U&'\041d\043e\0432\044b\0439',
       U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442',
       U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435',
       U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
     ) THEN
    SELECT * INTO readiness FROM symbolika_order_work_readiness(NEW.id);
    IF NOT COALESCE(readiness.ready_for_work, false) THEN
      RAISE EXCEPTION 'Заказ нельзя отправить в работу. Заполните: %', replace(COALESCE(readiness.missing_fields, ''), '||', ', ');
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_order_status_from_items(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  items_count integer;
  current_status_name text;
  next_status_name text;
  next_status_id integer;
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO items_count FROM orders_items WHERE "order" = order_id;
  IF items_count = 0 THEN
    RETURN;
  END IF;

  SELECT os.name INTO current_status_name
  FROM orders o
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE o.id = order_id;

  WITH normalized AS (
    SELECT symbolika_normalize_item_status(item_status) AS item_status
    FROM orders_items
    WHERE "order" = order_id
  )
  SELECT CASE
    WHEN bool_and(item_status = 'cancelled') THEN U&'\041e\0442\043c\0435\043d\0435\043d'
    WHEN bool_and(item_status IN ('delivered', 'cancelled')) AND bool_or(item_status = 'delivered') THEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
    WHEN bool_and(item_status IN ('ready', 'cancelled')) AND bool_or(item_status = 'ready') THEN U&'\0413\043e\0442\043e\0432'
    WHEN bool_or(item_status = 'layout_revision') THEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
    WHEN bool_or(item_status = 'cancellation_requested') THEN U&'\0412 \0440\0430\0431\043e\0442\0435'
    WHEN bool_or(item_status = 'sent_to_work') THEN U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443'
    WHEN bool_or(item_status = 'in_work') THEN U&'\0412 \0440\0430\0431\043e\0442\0435'
    WHEN bool_or(item_status = 'approval') THEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
    ELSE CASE
      WHEN current_status_name = U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442' THEN current_status_name
      ELSE U&'\041d\043e\0432\044b\0439'
    END
  END
  INTO next_status_name
  FROM normalized;

  next_status_id := symbolika_order_status_id(next_status_name);
  IF next_status_id IS NOT NULL THEN
    UPDATE orders
       SET order_status = next_status_id,
           office_status = CASE
             WHEN next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'issued'
             ELSE office_status
           END
     WHERE id = order_id
       AND (
         order_status IS DISTINCT FROM next_status_id
         OR (next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' AND office_status IS DISTINCT FROM 'issued')
       );

    IF next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN
      UPDATE orders_items
         SET office_status = 'issued', shipping_method = 'office_pickup'
       WHERE "order" = order_id AND office_status IS DISTINCT FROM 'issued';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_order_status_to_items_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  status_name text;
  previous_status_name text;
  next_item_status character varying;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT name INTO status_name FROM order_statuses WHERE id = NEW.order_status;
  SELECT name INTO previous_status_name FROM order_statuses WHERE id = OLD.order_status;

  next_item_status := CASE status_name
    WHEN U&'\041d\043e\0432\044b\0439' THEN 'new'
    WHEN U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442' THEN 'new'
    WHEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435' THEN 'approval'
    WHEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN 'layout_revision'
    WHEN U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443' THEN 'sent_to_work'
    WHEN U&'\0412 \0440\0430\0431\043e\0442\0435' THEN 'in_work'
    WHEN U&'\0413\043e\0442\043e\0432' THEN 'ready'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    WHEN U&'\041e\0442\043c\0435\043d\0435\043d' THEN 'cancelled'
    ELSE NULL
  END;

  IF next_item_status IS NOT NULL THEN
    IF next_item_status = 'in_work'
       AND previous_status_name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN
      UPDATE orders_items
         SET item_status = 'in_work', layout_revision_url_snapshot = NULL
       WHERE "order" = NEW.id
         AND symbolika_normalize_item_status(item_status) = 'layout_revision';
    ELSE
      UPDATE orders_items
         SET item_status = next_item_status,
             layout_revision_url_snapshot = CASE WHEN next_item_status = 'in_work' THEN NULL ELSE layout_revision_url_snapshot END,
             office_status = CASE WHEN next_item_status = 'delivered' THEN 'issued' ELSE office_status END,
             shipping_method = CASE WHEN next_item_status = 'delivered' THEN 'office_pickup' ELSE shipping_method END
       WHERE "order" = NEW.id
         AND (
           symbolika_normalize_item_status(item_status) IS DISTINCT FROM next_item_status
           OR (next_item_status = 'delivered' AND office_status IS DISTINCT FROM 'issued')
         );
    END IF;

    IF next_item_status = 'delivered' THEN
      UPDATE orders SET office_status = 'issued'
       WHERE id = NEW.id AND office_status IS DISTINCT FROM 'issued';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;

BEGIN;

CREATE OR REPLACE FUNCTION symbolika_normalize_item_status(status_value character varying)
RETURNS character varying
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE status_value
    WHEN 'send_to_work' THEN 'sent_to_work'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    ELSE COALESCE(status_value, 'new')
  END
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

  SELECT COUNT(*) INTO items_count
  FROM orders_items
  WHERE "order" = order_id;

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
    WHEN bool_or(item_status = 'waiting_layout') THEN U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442'
    WHEN bool_or(item_status = 'approval') THEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
    ELSE CASE
      WHEN current_status_name = U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442'
        THEN current_status_name
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
         OR (
           next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
           AND office_status IS DISTINCT FROM 'issued'
         )
       );

    IF next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN
      UPDATE orders_items
         SET office_status = 'issued',
             shipping_method = 'office_pickup'
       WHERE "order" = order_id
         AND office_status IS DISTINCT FROM 'issued';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_item_status_from_production_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_item_status character varying;
  previous_item_status character varying;
  item_transition_allowed boolean;
  ready_production_status integer;
  parent_order_delivered boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.item_status := 'new';
    NEW.office_status := 'not_in_office';
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.production_status IS DISTINCT FROM OLD.production_status THEN
    next_item_status := symbolika_item_status_from_production(NEW.production_status);
  ELSE
    next_item_status := NULL;
  END IF;

  IF next_item_status IS NOT NULL THEN
    NEW.item_status := next_item_status;
  ELSE
    NEW.item_status := symbolika_normalize_item_status(NEW.item_status);
  END IF;

  previous_item_status := CASE
    WHEN TG_OP = 'INSERT' THEN NULL
    ELSE symbolika_normalize_item_status(OLD.item_status)
  END;

  IF NEW.item_status = 'layout_revision'
     AND previous_item_status IS DISTINCT FROM 'layout_revision' THEN
    NEW.layout_revision_url_snapshot := NEW.url;
  END IF;

  IF TG_OP = 'INSERT' OR NEW.office_status IS DISTINCT FROM OLD.office_status THEN
    IF NEW.office_status = 'issued' THEN
      NEW.item_status := 'delivered';
      NEW.shipping_method := 'office_pickup';
    ELSIF NEW.office_status = 'in_office' THEN
      NEW.item_status := 'ready';
      NEW.shipping_method := 'office_pickup';
    END IF;
  ELSIF NEW.item_status IS DISTINCT FROM previous_item_status THEN
    IF NEW.item_status = 'delivered' THEN
      NEW.office_status := 'issued';
      NEW.shipping_method := 'office_pickup';
    ELSIF previous_item_status = 'delivered' AND OLD.office_status = 'issued' THEN
      NEW.office_status := CASE WHEN NEW.item_status = 'ready' THEN 'in_office' ELSE 'not_in_office' END;
      NEW.shipping_method := CASE WHEN NEW.item_status = 'ready' THEN 'office_pickup' ELSE NULL END;
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM orders o
    JOIN order_statuses os ON os.id = o.order_status
    WHERE o.id = NEW."order"
      AND os.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
  ) INTO parent_order_delivered;

  IF parent_order_delivered AND TG_OP <> 'INSERT' THEN
    NEW.office_status := 'issued';
  END IF;

  IF NEW.office_status IN ('in_office', 'issued') THEN
    SELECT ps.id INTO ready_production_status
    FROM production_statuses ps
    WHERE ps.name = U&'\0413\043e\0442\043e\0432'
    ORDER BY ps.id
    LIMIT 1;

    IF ready_production_status IS NOT NULL THEN
      NEW.production_status := ready_production_status;
    END IF;

    NEW.item_status := CASE
      WHEN NEW.office_status = 'issued' THEN 'delivered'
      ELSE 'ready'
    END;
    NEW.shipping_method := 'office_pickup';
  END IF;

  IF TG_OP = 'UPDATE'
     AND pg_trigger_depth() = 1
     AND NEW.production_status IS NOT DISTINCT FROM OLD.production_status
     AND NEW.office_status IS NOT DISTINCT FROM OLD.office_status
     AND NEW.item_status IS DISTINCT FROM previous_item_status THEN
    item_transition_allowed := CASE
      WHEN previous_item_status IN ('new', 'waiting_layout', 'approval') THEN NEW.item_status IN ('new', 'waiting_layout', 'approval', 'sent_to_work', 'in_work')
      WHEN previous_item_status = 'layout_revision' THEN NEW.item_status IN ('layout_revision', 'sent_to_work', 'in_work')
      WHEN previous_item_status IN ('sent_to_work', 'in_work') THEN NEW.item_status IN ('sent_to_work', 'in_work', 'cancellation_requested', 'ready', 'delivered')
      WHEN previous_item_status = 'cancellation_requested' THEN NEW.item_status IN ('cancellation_requested', 'cancelled')
      WHEN previous_item_status = 'ready' THEN NEW.item_status IN ('ready', 'delivered')
      WHEN previous_item_status = 'delivered' THEN NEW.item_status = 'delivered'
      ELSE NEW.item_status = previous_item_status
    END;

    IF NOT COALESCE(item_transition_allowed, false) THEN
      RAISE EXCEPTION 'Недопустимый переход статуса позиции: % -> %', previous_item_status, NEW.item_status;
    END IF;

    IF NEW.item_status IN ('sent_to_work', 'in_work')
       AND previous_item_status IN ('new', 'waiting_layout', 'approval', 'layout_revision') THEN
      IF NULLIF(BTRIM(COALESCE(NEW.product_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните наименование';
      END IF;
      IF COALESCE(NEW.quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните количество';
      END IF;
      IF NULLIF(BTRIM(COALESCE(NEW.technical_task_text, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните ТЗ';
      END IF;
      IF NULLIF(BTRIM(COALESCE(NEW.url, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: загрузите макет';
      END IF;
      IF previous_item_status = 'layout_revision'
         AND BTRIM(COALESCE(NEW.url, '')) = BTRIM(COALESCE(OLD.layout_revision_url_snapshot, '')) THEN
        RAISE EXCEPTION 'Позицию нельзя повторно запустить в работу: загрузите обновленный макет';
      END IF;
      NEW.layout_revision_url_snapshot := NULL;
    END IF;
  END IF;

  RETURN NEW;
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

  SELECT name INTO status_name
  FROM order_statuses
  WHERE id = NEW.order_status;

  SELECT name INTO previous_status_name
  FROM order_statuses
  WHERE id = OLD.order_status;

  next_item_status := CASE status_name
    WHEN U&'\041d\043e\0432\044b\0439' THEN 'new'
    WHEN U&'\0416\0434\0435\043c \043c\0430\043a\0435\0442' THEN 'waiting_layout'
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
         SET item_status = 'in_work',
             layout_revision_url_snapshot = NULL
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
      UPDATE orders
         SET office_status = 'issued'
       WHERE id = NEW.id
         AND office_status IS DISTINCT FROM 'issued';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;

BEGIN;

CREATE TABLE IF NOT EXISTS symbolika_office_item_status_snapshots (
  item_id integer PRIMARY KEY REFERENCES orders_items(id) ON DELETE CASCADE,
  order_id integer NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  item_status character varying,
  production_status integer,
  shipping_method character varying,
  captured_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS symbolika_office_item_status_snapshots_order_idx
  ON symbolika_office_item_status_snapshots(order_id);

CREATE OR REPLACE FUNCTION symbolika_apply_item_status_from_production_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  office_snapshot record;
  next_item_status character varying;
  previous_item_status character varying;
  item_transition_allowed boolean;
  ready_production_status integer;
  parent_order_delivered boolean := false;
  parent_shipping_method text;
BEGIN
  -- A position added to an already ready/delivered order starts its own
  -- workflow and must never inherit the final state of the parent order.
  IF TG_OP = 'INSERT' THEN
    NEW.item_status := 'new';
    NEW.office_status := 'not_in_office';
  END IF;

  -- Entering the office is a reversible presentation state. Preserve the
  -- workflow fields before forcing the item to Ready/Delivered, then restore
  -- them exactly when the item is returned to Not in office.
  IF TG_OP = 'UPDATE'
     AND NEW.office_status IS DISTINCT FROM OLD.office_status THEN
    IF NEW.office_status IN ('in_office', 'issued')
       AND COALESCE(OLD.office_status, 'not_in_office') = 'not_in_office' THEN
      INSERT INTO symbolika_office_item_status_snapshots (
        item_id, order_id, item_status, production_status, shipping_method
      ) VALUES (
        OLD.id, OLD."order", OLD.item_status, OLD.production_status, OLD.shipping_method
      )
      ON CONFLICT (item_id) DO NOTHING;
    ELSIF NEW.office_status = 'not_in_office'
          AND OLD.office_status IN ('in_office', 'issued') THEN
      SELECT * INTO office_snapshot
      FROM symbolika_office_item_status_snapshots
      WHERE item_id = OLD.id;

      IF FOUND THEN
        NEW.item_status := office_snapshot.item_status;
        NEW.production_status := office_snapshot.production_status;
        NEW.shipping_method := office_snapshot.shipping_method;

        DELETE FROM symbolika_office_item_status_snapshots
        WHERE item_id = OLD.id;

        RETURN NEW;
      END IF;
    END IF;
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

  SELECT o.shipping_method
    INTO parent_shipping_method
    FROM orders o
   WHERE o.id = NEW."order";

  IF NEW.item_status = 'layout_revision'
     AND previous_item_status IS DISTINCT FROM 'layout_revision' THEN
    NEW.layout_revision_url_snapshot := NEW.url;
  END IF;

  -- Office issue and the public item status describe the same final state.
  -- Whichever field was changed by the UI becomes the source of truth.
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
      NEW.office_status := CASE
        WHEN parent_shipping_method = 'office_pickup' THEN 'issued'
        ELSE 'not_in_office'
      END;
      NEW.shipping_method := parent_shipping_method;
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

  -- A delivered order cannot contain an item that is merely waiting in the office.
  IF parent_order_delivered AND TG_OP <> 'INSERT' THEN
    NEW.office_status := CASE
      WHEN parent_shipping_method = 'office_pickup' THEN 'issued'
      ELSE 'not_in_office'
    END;
    NEW.shipping_method := parent_shipping_method;
  END IF;

  -- A position physically accepted by the office has completed production,
  -- even if the workshop forgot to set its status before handing it over.
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

COMMIT;


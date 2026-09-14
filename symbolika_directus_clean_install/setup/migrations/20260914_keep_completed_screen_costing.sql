BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- screen_printing_work is both the operational queue and the durable source
-- for the monthly screen-printing costing summary. Completed rows must remain
-- in it; the UI already hides archived statuses from the active task list.
DO $migration$
DECLARE
  current_definition text;
  updated_definition text;
BEGIN
  SELECT pg_get_functiondef('sync_work_item(integer)'::regprocedure)
    INTO current_definition;

  updated_definition := replace(
    current_definition,
    'item_work_status NOT IN (''sent_to_work'', ''in_work'', ''layout_revision'', ''ready'', ''cancelled'')',
    'item_work_status NOT IN (''sent_to_work'', ''in_work'', ''layout_revision'', ''ready'', ''cancelled'', ''delivered'')'
  );

  IF updated_definition = current_definition THEN
    RAISE EXCEPTION 'sync_work_item status guard has an unexpected definition';
  END IF;

  current_definition := updated_definition;
  updated_definition := replace(
    current_definition,
    'U&''\041e\0442\043c\0435\043d\0435\043d''',
    'U&''\041e\0442\043c\0435\043d\0435\043d'', U&''\0414\043e\0441\0442\0430\0432\043b\0435\043d'''
  );

  IF updated_definition = current_definition THEN
    RAISE EXCEPTION 'sync_work_item order status guard has an unexpected definition';
  END IF;

  EXECUTE updated_definition;
END;
$migration$;

-- Restore historical rows which the former guard removed after delivery.
SELECT sync_work_item(oi.id)
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN order_statuses os ON os.id = o.order_status
WHERE symbolika_normalize_item_status(oi.item_status) = 'delivered'
   OR os.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d';

COMMIT;

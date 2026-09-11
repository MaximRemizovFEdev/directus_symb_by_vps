BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION sync_office_issue_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM office_issue_items WHERE id = OLD.id;
    DELETE FROM office_issue_archive_items WHERE id = OLD.id;
    DELETE FROM office_items_in_office WHERE id = OLD.id;
    IF pg_trigger_depth() = 1 THEN
      PERFORM recalc_order_office_status(OLD."order");
    END IF;
    RETURN OLD;
  END IF;

  PERFORM sync_office_issue_items(NEW."order");
  PERFORM sync_office_items_in_office(NEW.id);

  -- Recalculate the parent only for a direct item write. An item write caused
  -- by the order trigger is already part of an order-level status operation;
  -- re-entering the parent from every affected row can create an endless
  -- order -> items -> order loop while aggregate states are still changing.
  IF pg_trigger_depth() = 1 THEN
    PERFORM recalc_order_office_status(NEW."order");
  END IF;

  RETURN NEW;
END;
$$;

-- Complete the explicitly requested issue of SO-00073. Categories excluded
-- from office handling (for example design) retain their null office status.
UPDATE orders_items oi
SET office_status = 'issued',
    item_status = 'delivered',
    shipping_method = 'office_pickup'
FROM orders o
WHERE oi."order" = o.id
  AND o.order_number = 'SO-00073'
  AND COALESCE((
    SELECT pc.office_applicable
    FROM product_categories pc
    WHERE pc.id = oi.product_category
  ), true)
  AND (
    oi.office_status IS DISTINCT FROM 'issued'
    OR symbolika_normalize_item_status(oi.item_status) IS DISTINCT FROM 'delivered'
    OR oi.shipping_method IS DISTINCT FROM 'office_pickup'
  );

SELECT recalc_order_office_status(id)
FROM orders
WHERE order_number = 'SO-00073';

COMMIT;

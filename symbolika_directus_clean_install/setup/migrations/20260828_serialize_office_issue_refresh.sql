-- Prevent concurrent orders_items triggers from rebuilding the same office
-- mirror rows at once. The canonical definition is in create-work-views.sql.

CREATE OR REPLACE FUNCTION sync_office_issue_items(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(205117, order_id);

  DELETE FROM office_issue_items mirror
  WHERE mirror.office_issue = order_id
     OR mirror.id IN (
       SELECT oi.id
       FROM orders_items oi
       WHERE oi."order" = order_id
     );
  DELETE FROM office_issue_archive_items mirror
  WHERE mirror.office_issue = order_id
     OR mirror.id IN (
       SELECT oi.id
       FROM orders_items oi
       WHERE oi."order" = order_id
     );

  INSERT INTO office_issue_items (
    id, office_issue, product_name, quantity, office_status
  )
  SELECT
    oi.id,
    oi."order",
    oi.product_name,
    oi.quantity,
    oi.office_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(pc.office_applicable, true)
    AND COALESCE(o.office_status, 'not_in_office') <> 'issued'
  ON CONFLICT (id) DO UPDATE SET
    office_issue = EXCLUDED.office_issue,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    office_status = EXCLUDED.office_status;

  INSERT INTO office_issue_archive_items (
    id, office_issue, product_name, quantity, office_status
  )
  SELECT
    oi.id,
    oi."order",
    oi.product_name,
    oi.quantity,
    oi.office_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(pc.office_applicable, true)
    AND o.office_status = 'issued'
  ON CONFLICT (id) DO UPDATE SET
    office_issue = EXCLUDED.office_issue,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    office_status = EXCLUDED.office_status;
END;
$$;

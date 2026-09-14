BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- An office mirror update reaches orders_items at trigger depth 2. The
-- generic item aggregate intentionally ignores such nested writes to avoid
-- recursive order/item loops, so the mirror owner must finish both parent
-- aggregates explicitly.
CREATE OR REPLACE FUNCTION push_office_item_status_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  order_id integer;
BEGIN
  UPDATE orders_items
     SET office_status = NEW.office_status,
         item_status = CASE
           WHEN NEW.office_status = 'issued' THEN 'delivered'
           WHEN NEW.office_status = 'in_office' THEN 'ready'
           ELSE item_status
         END
   WHERE id = NEW.id
     AND (
       office_status IS DISTINCT FROM NEW.office_status
       OR (
         NEW.office_status = 'issued'
         AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
       )
       OR (
         NEW.office_status = 'in_office'
         AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'ready'
       )
     )
   RETURNING "order" INTO order_id;

  IF order_id IS NULL THEN
    SELECT "order" INTO order_id
    FROM orders_items
    WHERE id = NEW.id;
  END IF;

  IF order_id IS NOT NULL THEN
    PERFORM recalc_order_office_status(order_id);
    PERFORM symbolika_recalc_order_status_from_items(order_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION push_office_issue_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE orders
     SET office_status = NEW.office_status
   WHERE id = NEW.id
     AND office_status IS DISTINCT FROM NEW.office_status;

  IF NEW.office_status IN ('in_office', 'issued', 'not_in_office') THEN
    UPDATE orders_items
       SET office_status = NEW.office_status,
           item_status = CASE
             WHEN NEW.office_status = 'issued' THEN 'delivered'
             WHEN NEW.office_status = 'in_office' THEN 'ready'
             ELSE item_status
           END
     WHERE "order" = NEW.id
       AND (
         office_status IS DISTINCT FROM NEW.office_status
         OR (
           NEW.office_status = 'issued'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
         )
         OR (
           NEW.office_status = 'in_office'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'ready'
         )
       );
  END IF;

  PERFORM recalc_order_office_status(NEW.id);
  PERFORM symbolika_recalc_order_status_from_items(NEW.id);

  IF COALESCE(NEW.add_payment, 0) > 0 THEN
    INSERT INTO order_payments (
      "order", customer, customer_company, amount, payment_date, payment_type,
      payment_direction, allocation_mode, comment
    )
    SELECT
      o.id,
      o.customer,
      o.customer_company,
      NEW.add_payment,
      CURRENT_DATE,
      NEW.payment_type,
      'incoming',
      'to_order',
      NEW.payment_comment
    FROM orders o
    WHERE o.id = NEW.id;
  END IF;

  UPDATE orders o
     SET paid_amount = totals.paid_amount,
         payment_due = COALESCE(o.order_sum, 0) - totals.paid_amount,
         office_payment_due = CASE
           WHEN o.payment_on_receipt THEN COALESCE(o.order_sum, 0) - totals.paid_amount
           ELSE 0
         END
    FROM (
      SELECT COALESCE(SUM(pa.amount), 0)::numeric(10,2) AS paid_amount
      FROM payment_allocations pa
      WHERE pa."order" = NEW.id
    ) totals
   WHERE o.id = NEW.id;

  PERFORM sync_office_issue_order(NEW.id);
  PERFORM sync_office_issue_items(NEW.id);

  RETURN NEW;
END;
$$;

-- Repair every latent mismatch, including SO-00088, using the same aggregate
-- that will handle future item and whole-order issue operations.
SELECT symbolika_recalc_order_status_from_items(o.id)
FROM orders o
WHERE EXISTS (
  SELECT 1
  FROM orders_items oi
  WHERE oi."order" = o.id
)
AND NOT EXISTS (
  SELECT 1
  FROM orders_items oi
  WHERE oi."order" = o.id
    AND symbolika_normalize_item_status(oi.item_status) NOT IN ('delivered', 'cancelled')
)
AND EXISTS (
  SELECT 1
  FROM orders_items oi
  WHERE oi."order" = o.id
    AND symbolika_normalize_item_status(oi.item_status) = 'delivered'
);

COMMIT;

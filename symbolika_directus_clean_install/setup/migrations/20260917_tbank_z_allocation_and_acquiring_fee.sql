BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS acquiring_fee_sum numeric(14,2) NOT NULL DEFAULT 0;

ALTER TABLE orders_items
  ADD COLUMN IF NOT EXISTS acquiring_fee_sum numeric(14,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION symbolika_apply_item_finance_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.profit_sum := ROUND(
    COALESCE(NEW.order_sum, 0)
    - COALESCE(NEW.total_cost, 0)
    - COALESCE(NEW.manager_commission_sum, 0)
    - COALESCE(NEW.tax_sum, 0)
    - COALESCE(NEW.acquiring_fee_sum, 0),
    2
  );
  NEW.margin_percent := CASE
    WHEN COALESCE(NEW.order_sum, 0) > 0
      THEN ROUND(NEW.profit_sum / NEW.order_sum * 100, 2)
    ELSE 0
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_apply_item_finance_totals ON orders_items;
CREATE TRIGGER symbolika_apply_item_finance_totals
BEFORE INSERT OR UPDATE OF order_sum, total_cost, manager_commission_sum, tax_sum, acquiring_fee_sum, profit_sum, margin_percent
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_item_finance_totals();

CREATE OR REPLACE FUNCTION symbolika_apply_order_finance_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.profit_sum := ROUND(
    COALESCE(NEW.order_sum, 0)
    - COALESCE(NEW.items_total_cost, 0)
    - COALESCE(NEW.items_manager_commission_sum, 0)
    - COALESCE(NEW.items_tax_sum, 0)
    - COALESCE(NEW.acquiring_fee_sum, 0),
    2
  );
  NEW.margin_percent := CASE
    WHEN COALESCE(NEW.order_sum, 0) > 0
      THEN ROUND(NEW.profit_sum / NEW.order_sum * 100, 2)
    ELSE 0
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_apply_order_finance_totals ON orders;
CREATE TRIGGER symbolika_apply_order_finance_totals
BEFORE INSERT OR UPDATE OF order_sum, items_total_cost, items_manager_commission_sum, items_tax_sum, acquiring_fee_sum, profit_sum, margin_percent
ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_order_finance_totals();

CREATE OR REPLACE FUNCTION symbolika_recalc_order_acquiring_fee(target_order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  tbank_paid numeric := 0;
BEGIN
  IF target_order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(pa.amount), 0)
    INTO tbank_paid
    FROM payment_allocations pa
    JOIN symbolika_tbank_payments tp ON tp.order_payment_id = pa.payment
   WHERE pa."order" = target_order_id;

  WITH item_ranges AS (
    SELECT
      oi.id,
      COALESCE(oi.order_sum, 0)::numeric AS item_sum,
      COALESCE(
        SUM(COALESCE(oi.order_sum, 0)) OVER (
          ORDER BY oi.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::numeric AS range_start
    FROM orders_items oi
    WHERE oi."order" = target_order_id
      AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
  ), fees AS (
    SELECT
      id,
      ROUND(
        LEAST(item_sum, GREATEST(tbank_paid - range_start, 0)) * 0.022,
        2
      ) AS fee
    FROM item_ranges
  )
  UPDATE orders_items oi
     SET acquiring_fee_sum = fees.fee
    FROM fees
   WHERE oi.id = fees.id;

  UPDATE orders_items
     SET acquiring_fee_sum = 0
   WHERE "order" = target_order_id
     AND symbolika_normalize_item_status(item_status) = 'cancelled';

  UPDATE orders o
     SET acquiring_fee_sum = COALESCE((
       SELECT SUM(oi.acquiring_fee_sum)
       FROM orders_items oi
       WHERE oi."order" = target_order_id
         AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
     ), 0)
   WHERE o.id = target_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_acquiring_fee_on_allocation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM symbolika_recalc_order_acquiring_fee(NEW."order");
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM symbolika_recalc_order_acquiring_fee(OLD."order");
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS zz_symbolika_recalc_acquiring_fee ON payment_allocations;
CREATE TRIGGER zz_symbolika_recalc_acquiring_fee
AFTER INSERT OR UPDATE OR DELETE ON payment_allocations
FOR EACH ROW
EXECUTE FUNCTION symbolika_recalc_acquiring_fee_on_allocation();

-- Payments created by the bank callback belong to the order in the link.
UPDATE symbolika_tbank_payments
   SET status = 'CONFIRMED',
       date_updated = now()
 WHERE order_payment_id IS NOT NULL;

UPDATE order_payments op
   SET allocation_mode = 'to_order',
       payment_type = COALESCE(
         (SELECT pt.id FROM payment_types pt WHERE pt.tax_percent = 8 ORDER BY pt.id LIMIT 1),
         op.payment_type
       )
  FROM symbolika_tbank_payments tp
 WHERE tp.order_payment_id = op.id;

INSERT INTO payment_allocations (payment, "order", amount, comment)
SELECT
  op.id,
  tp.order_id,
  op.amount,
  'Автоматическое распределение оплаты Т-Банка'
FROM symbolika_tbank_payments tp
JOIN order_payments op ON op.id = tp.order_payment_id
WHERE NOT EXISTS (
  SELECT 1
  FROM payment_allocations pa
  WHERE pa.payment = op.id
    AND pa."order" = tp.order_id
);

DO $$
DECLARE
  affected_order_id integer;
BEGIN
  FOR affected_order_id IN
    SELECT DISTINCT order_id
    FROM symbolika_tbank_payments
    WHERE order_payment_id IS NOT NULL
  LOOP
    PERFORM recalc_order_payment_totals(affected_order_id);
    PERFORM symbolika_recalc_order_acquiring_fee(affected_order_id);
  END LOOP;
END;
$$;

COMMIT;

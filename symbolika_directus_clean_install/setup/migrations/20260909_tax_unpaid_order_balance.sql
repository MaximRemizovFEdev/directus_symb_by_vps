BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION recalc_order_payment_totals(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  IF current_setting('symbolika.recalculating_order_finance', true) = '1' THEN
    RETURN;
  END IF;

  IF NOT pg_try_advisory_xact_lock(hashtext('recalc_order_payment_totals'), order_id) THEN
    RETURN;
  END IF;

  PERFORM set_config('symbolika.recalculating_order_finance', '1', true);

  UPDATE order_payments op
     SET allocated_amount = COALESCE(allocated.total, 0),
         unallocated_amount = COALESCE(op.amount, 0) - COALESCE(allocated.total, 0)
    FROM (
      SELECT payment, COALESCE(SUM(amount), 0)::numeric(10,2) AS total
      FROM payment_allocations
      GROUP BY payment
    ) allocated
   WHERE op.id = allocated.payment
     AND op."order" = order_id;

  UPDATE order_payments op
     SET allocated_amount = 0,
         unallocated_amount = COALESCE(op.amount, 0)
   WHERE op."order" = order_id
     AND NOT EXISTS (
       SELECT 1
       FROM payment_allocations pa
       WHERE pa.payment = op.id
     );

  UPDATE orders o
     SET order_sum = COALESCE(item_totals.order_sum, 0),
         paid_amount = COALESCE(payment_totals.paid_amount, 0),
         payment_due = COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0),
         office_payment_due = CASE
           WHEN o.payment_on_receipt THEN COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0)
           ELSE 0
         END
    FROM (
      SELECT COALESCE(SUM(order_sum), 0)::numeric(10,2) AS order_sum
      FROM orders_items
      WHERE "order" = order_id
        AND symbolika_normalize_item_status(item_status) <> 'cancelled'
    ) item_totals,
    (
      SELECT COALESCE(SUM(amount), 0)::numeric(10,2) AS paid_amount
      FROM payment_allocations
      WHERE "order" = order_id
    ) payment_totals
  WHERE o.id = order_id;

  -- Actual payments define tax for the covered prefix of an order. The
  -- selected order payment type defines tax for the still-unpaid suffix.
  WITH item_ranges AS (
    SELECT
      oi.id,
      COALESCE(oi.order_sum, 0)::numeric AS item_sum,
      COALESCE(
        SUM(COALESCE(oi.order_sum, 0)) OVER (
          ORDER BY oi.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::numeric AS range_start,
      SUM(COALESCE(oi.order_sum, 0)) OVER (
        ORDER BY oi.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::numeric AS range_end
    FROM orders_items oi
    WHERE oi."order" = order_id
      AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
  ),
  payment_steps AS (
    SELECT
      pa.id,
      pa.payment,
      CASE
        WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -1
        ELSE 1
      END::numeric AS direction_sign,
      COALESCE(pa.amount, 0)::numeric AS allocated_amount,
      COALESCE(pt.tax_percent, 0)::numeric AS tax_percent,
      COALESCE(
        SUM(
          CASE
            WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -COALESCE(pa.amount, 0)
            ELSE COALESCE(pa.amount, 0)
          END
        ) OVER (
          ORDER BY op.payment_date, op.id, pa.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::numeric AS balance_before,
      SUM(
        CASE
          WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -COALESCE(pa.amount, 0)
          ELSE COALESCE(pa.amount, 0)
        END
      ) OVER (
        ORDER BY op.payment_date, op.id, pa.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::numeric AS balance_after
    FROM payment_allocations pa
    JOIN order_payments op ON op.id = pa.payment
    LEFT JOIN payment_types pt ON pt.id = op.payment_type
    WHERE pa."order" = order_id
  ),
  order_tax_context AS (
    SELECT
      COALESCE(nominal_type.tax_percent, 0)::numeric AS nominal_tax_percent,
      GREATEST(
        COALESCE(SUM(
          CASE
            WHEN paid.payment_direction = 'outgoing_refund' OR paid.allocation_mode = 'refund'
              THEN -COALESCE(allocation.amount, 0)
            ELSE COALESCE(allocation.amount, 0)
          END
        ), 0),
        0
      )::numeric AS paid_balance
    FROM orders selected_order
    LEFT JOIN payment_types nominal_type ON nominal_type.id = selected_order.payment_type
    LEFT JOIN payment_allocations allocation ON allocation."order" = selected_order.id
    LEFT JOIN order_payments paid ON paid.id = allocation.payment
    WHERE selected_order.id = order_id
    GROUP BY nominal_type.tax_percent
  ),
  item_taxes AS (
    SELECT
      ir.id,
      ir.item_sum,
      ROUND(
        COALESCE(SUM(
          ps.direction_sign
          * GREATEST(
              LEAST(ir.range_end, GREATEST(ps.balance_before, ps.balance_after))
              - GREATEST(ir.range_start, LEAST(ps.balance_before, ps.balance_after)),
              0
            )
          * ps.tax_percent / 100
        ), 0)
        + GREATEST(ir.range_end - GREATEST(ir.range_start, otc.paid_balance), 0)
          * otc.nominal_tax_percent / 100,
        2
      ) AS tax_sum
    FROM item_ranges ir
    CROSS JOIN order_tax_context otc
    LEFT JOIN payment_steps ps
      ON GREATEST(ps.balance_before, ps.balance_after) > ir.range_start
     AND LEAST(ps.balance_before, ps.balance_after) < ir.range_end
    GROUP BY ir.id, ir.item_sum, ir.range_start, ir.range_end,
      otc.paid_balance, otc.nominal_tax_percent
  )
  UPDATE orders_items oi
     SET tax_sum = GREATEST(it.tax_sum, 0),
         tax_percent = CASE
           WHEN it.item_sum > 0 THEN ROUND(GREATEST(it.tax_sum, 0) / it.item_sum * 100, 4)
           ELSE 0
         END,
         profit_sum = ROUND(
           COALESCE(oi.order_sum, 0)
           - COALESCE(oi.total_cost, 0)
           - COALESCE(oi.manager_commission_sum, 0)
           - GREATEST(it.tax_sum, 0),
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(oi.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(oi.order_sum, 0)
               - COALESCE(oi.total_cost, 0)
               - COALESCE(oi.manager_commission_sum, 0)
               - GREATEST(it.tax_sum, 0)
             ) / oi.order_sum * 100,
             2
           )
           ELSE 0
         END
    FROM item_taxes it
   WHERE oi.id = it.id;

  UPDATE orders_items oi
     SET tax_sum = 0,
         tax_percent = 0,
         profit_sum = ROUND(
           COALESCE(oi.order_sum, 0)
           - COALESCE(oi.total_cost, 0)
           - COALESCE(oi.manager_commission_sum, 0),
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(oi.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(oi.order_sum, 0)
               - COALESCE(oi.total_cost, 0)
               - COALESCE(oi.manager_commission_sum, 0)
             ) / oi.order_sum * 100,
             2
           )
           ELSE 0
         END
   WHERE oi."order" = order_id
     AND symbolika_normalize_item_status(oi.item_status) = 'cancelled';

  UPDATE orders o
     SET items_total_cost = totals.items_total_cost,
         items_manager_commission_sum = totals.items_manager_commission_sum,
         items_tax_sum = totals.items_tax_sum,
         profit_sum = ROUND(
           COALESCE(o.order_sum, 0)
           - totals.items_total_cost
           - totals.items_manager_commission_sum
           - totals.items_tax_sum,
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(o.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(o.order_sum, 0)
               - totals.items_total_cost
               - totals.items_manager_commission_sum
               - totals.items_tax_sum
             ) / o.order_sum * 100,
             2
           )
           ELSE 0
         END
    FROM (
      SELECT
        COALESCE(SUM(oi.total_cost), 0)::numeric(10,2) AS items_total_cost,
        COALESCE(SUM(oi.manager_commission_sum), 0)::numeric(10,2) AS items_manager_commission_sum,
        COALESCE(SUM(oi.tax_sum), 0)::numeric(10,2) AS items_tax_sum
      FROM orders_items oi
      WHERE oi."order" = order_id
        AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ) totals
   WHERE o.id = order_id;

  PERFORM sync_office_issue_order(order_id);
  PERFORM set_config('symbolika.recalculating_order_finance', '0', true);
END;
$$;

DROP TRIGGER IF EXISTS symbolika_recalc_order_payment_on_order ON orders;
CREATE TRIGGER symbolika_recalc_order_payment_on_order
AFTER UPDATE OF payment_on_receipt, payment_type ON orders
FOR EACH ROW
EXECUTE FUNCTION recalc_order_payment_on_order_trigger();

DO $$
DECLARE
  existing_order_id integer;
BEGIN
  FOR existing_order_id IN
    SELECT id FROM orders ORDER BY id
  LOOP
    PERFORM recalc_order_payment_totals(existing_order_id);
  END LOOP;
END;
$$;

COMMIT;

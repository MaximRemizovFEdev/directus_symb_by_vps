BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Keep internal routing and external contractor settlements separate from the
-- ability to enter an item-level production cost. Kalvin remains an internal
-- personal executor, but his item cost participates in the order margin.
ALTER TABLE contractors
ADD COLUMN IF NOT EXISTS allows_item_cost boolean NOT NULL DEFAULT false;

UPDATE contractors
SET is_internal_production = true,
    allows_item_cost = true
WHERE lower(trim(name)) IN (
  lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c')),
  lower(trim(U&'\041a\0430\043b\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
)
AND (
  is_internal_production IS DISTINCT FROM true
  OR allows_item_cost IS DISTINCT FROM true
);

CREATE OR REPLACE FUNCTION symbolika_zero_internal_contractor_costs_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.contractor_1 IS NOT NULL AND EXISTS (
    SELECT 1 FROM contractors c
    WHERE c.id = NEW.contractor_1
      AND COALESCE(c.is_internal_production, false)
      AND NOT COALESCE(c.allows_item_cost, false)
  ) THEN
    NEW.contractor_1_cost := 0;
  END IF;

  IF NEW.contractor_2 IS NOT NULL AND EXISTS (
    SELECT 1 FROM contractors c
    WHERE c.id = NEW.contractor_2
      AND COALESCE(c.is_internal_production, false)
      AND NOT COALESCE(c.allows_item_cost, false)
  ) THEN
    NEW.contractor_2_cost := 0;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_item_financials_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  contractor_1_internal boolean := false;
  contractor_2_internal boolean := false;
  contractor_1_cost_allowed boolean := false;
  contractor_2_cost_allowed boolean := false;
  contractor_1_screen boolean := false;
  contractor_2_screen boolean := false;
  effective_unit_cost numeric := 0;
BEGIN
  IF NEW.contractor_1 IS NOT NULL THEN
    SELECT
      COALESCE(is_internal_production, false),
      COALESCE(allows_item_cost, false),
      COALESCE(name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
    INTO contractor_1_internal, contractor_1_cost_allowed, contractor_1_screen
    FROM contractors
    WHERE id = NEW.contractor_1;
  END IF;

  IF NEW.contractor_2 IS NOT NULL THEN
    SELECT
      COALESCE(is_internal_production, false),
      COALESCE(allows_item_cost, false),
      COALESCE(name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', false)
    INTO contractor_2_internal, contractor_2_cost_allowed, contractor_2_screen
    FROM contractors
    WHERE id = NEW.contractor_2;
  END IF;

  effective_unit_cost :=
    CASE WHEN (COALESCE(contractor_1_internal, false) AND NOT COALESCE(contractor_1_cost_allowed, false))
                   OR COALESCE(contractor_1_screen, false)
      THEN 0 ELSE COALESCE(NEW.contractor_1_cost, 0) END
    + CASE WHEN (COALESCE(contractor_2_internal, false) AND NOT COALESCE(contractor_2_cost_allowed, false))
                   OR COALESCE(contractor_2_screen, false)
      THEN 0 ELSE COALESCE(NEW.contractor_2_cost, 0) END
    + CASE WHEN COALESCE(contractor_1_screen, false)
             OR COALESCE(contractor_2_screen, false)
             OR COALESCE(NEW.internal_route_screen, false)
      THEN COALESCE(NEW.screen_printing_cost_per_unit, 0) ELSE 0 END;

  NEW.order_sum := ROUND(COALESCE(NEW.quantity, 0) * COALESCE(NEW.price_per_unit, 0), 2);
  NEW.unit_cost := ROUND(effective_unit_cost, 2);
  NEW.total_cost := ROUND(COALESCE(NEW.quantity, 0) * effective_unit_cost, 2);
  NEW.manager_commission_sum := ROUND(NEW.order_sum * COALESCE(NEW.manager_percent, 0) / 100, 2);
  NEW.profit_sum := ROUND(
    NEW.order_sum - NEW.total_cost - NEW.manager_commission_sum - COALESCE(NEW.tax_sum, 0),
    2
  );
  NEW.margin_percent := CASE WHEN NEW.order_sum > 0
    THEN ROUND(NEW.profit_sum / NEW.order_sum * 100, 2)
    ELSE 0
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_recalc_item_financials ON orders_items;
CREATE TRIGGER symbolika_recalc_item_financials
BEFORE INSERT OR UPDATE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_recalc_item_financials_trigger();

-- Recover the latest positive value that a user actually submitted while the
-- incorrect flag was active. Do not overwrite a value that has subsequently
-- been saved successfully, and do not invent costs where the last intent was 0.
WITH kalvin AS (
  SELECT id
  FROM contractors
  WHERE lower(trim(name)) IN (
    lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c')),
    lower(trim(U&'\041a\0430\043b\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  )
), latest_attempt AS (
  SELECT DISTINCT ON (r.item)
         r.item::integer AS item_id,
         replace(r.delta::jsonb->>'contractor_1_cost', ',', '.')::numeric AS requested_cost
  FROM directus_revisions r
  JOIN directus_activity a ON a.id = r.activity
  WHERE a.collection = 'orders_items'
    AND r.item ~ '^[0-9]+$'
    AND r.delta::jsonb ? 'contractor_1_cost'
    AND COALESCE(r.delta::jsonb->>'contractor_1_cost', '') ~ '^[0-9]+([.,][0-9]+)?$'
    AND r.item::integer IN (
      SELECT oi.id FROM orders_items oi WHERE oi.contractor_1 IN (SELECT id FROM kalvin)
    )
  ORDER BY r.item, a.timestamp DESC, r.id DESC
)
UPDATE orders_items oi
SET contractor_1_cost = latest_attempt.requested_cost
FROM latest_attempt
WHERE oi.id = latest_attempt.item_id
  AND oi.contractor_1 IN (SELECT id FROM kalvin)
  AND COALESCE(oi.contractor_1_cost, 0) = 0
  AND latest_attempt.requested_cost > 0;

WITH kalvin AS (
  SELECT id
  FROM contractors
  WHERE lower(trim(name)) IN (
    lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c')),
    lower(trim(U&'\041a\0430\043b\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  )
), latest_attempt AS (
  SELECT DISTINCT ON (r.item)
         r.item::integer AS item_id,
         replace(r.delta::jsonb->>'contractor_2_cost', ',', '.')::numeric AS requested_cost
  FROM directus_revisions r
  JOIN directus_activity a ON a.id = r.activity
  WHERE a.collection = 'orders_items'
    AND r.item ~ '^[0-9]+$'
    AND r.delta::jsonb ? 'contractor_2_cost'
    AND COALESCE(r.delta::jsonb->>'contractor_2_cost', '') ~ '^[0-9]+([.,][0-9]+)?$'
    AND r.item::integer IN (
      SELECT oi.id FROM orders_items oi WHERE oi.contractor_2 IN (SELECT id FROM kalvin)
    )
  ORDER BY r.item, a.timestamp DESC, r.id DESC
)
UPDATE orders_items oi
SET contractor_2_cost = latest_attempt.requested_cost
FROM latest_attempt
WHERE oi.id = latest_attempt.item_id
  AND oi.contractor_2 IN (SELECT id FROM kalvin)
  AND COALESCE(oi.contractor_2_cost, 0) = 0
  AND latest_attempt.requested_cost > 0;

COMMIT;

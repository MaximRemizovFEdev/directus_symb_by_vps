BEGIN;

-- Preserve the exact set of affected specs for the repair below before the
-- templates themselves are updated.
CREATE TEMP TABLE symbolika_affected_tz_specs ON COMMIT DROP AS
SELECT id, category, subcategory, application_method
FROM tz_constructor_specs
WHERE active IS TRUE
  AND template NOT LIKE '%{{quantity}}%';

UPDATE tz_constructor_specs
SET template = CASE
      WHEN template LIKE '%{{product_name}}%'
        THEN replace(template, '{{product_name}}', '{{product_name}}, {{quantity}} шт.')
      ELSE '{{quantity}} шт., ' || template
    END,
    updated_at = now()
WHERE id IN (SELECT id FROM symbolika_affected_tz_specs);

-- Add the current run to already assembled tasks from the affected templates
-- without discarding their parameters or comments.
UPDATE orders_items item
SET technical_task_text = CASE
      WHEN NULLIF(btrim(item.product_name), '') IS NOT NULL
        AND item.technical_task_text LIKE item.product_name || '%'
        THEN item.product_name || ', ' || item.quantity::text || ' шт., '
          || ltrim(substr(item.technical_task_text, length(item.product_name) + 1), ' ,')
      ELSE item.quantity::text || ' шт., ' || item.technical_task_text
    END
WHERE item.quantity > 0
  AND NULLIF(btrim(item.technical_task_text), '') IS NOT NULL
  AND item.technical_task_text NOT ILIKE '%' || item.quantity::text || ' шт.%'
  AND EXISTS (
    SELECT 1
    FROM symbolika_affected_tz_specs spec
    WHERE (spec.category IS NULL OR spec.category = item.product_category)
      AND (spec.subcategory IS NULL OR spec.subcategory = item.product_subcategory)
      AND (spec.application_method IS NULL OR spec.application_method = item.application_method)
  );

COMMIT;

BEGIN;

-- Quantity is part of the order item and must always be visible in a task
-- routed to screen printing. Older souvenir/application templates omitted
-- the placeholder, unlike the textile templates.
UPDATE tz_constructor_specs
SET template = CASE
  WHEN template LIKE '%{{product_name}}%'
    THEN replace(template, '{{product_name}}', '{{product_name}}, {{quantity}} шт.')
  ELSE '{{quantity}} шт., ' || template
END
WHERE active IS TRUE
  AND route_area = 'screen_printing'
  AND template NOT LIKE '%{{quantity}}%';

-- Repair already generated tasks that used the affected templates. Keep all
-- manually entered details and only insert the current item quantity after
-- the product name.
UPDATE orders_items item
SET technical_task_text = item.product_name || ', '
  || item.quantity::text
  || ' шт., '
  || ltrim(substr(item.technical_task_text, length(item.product_name) + 2))
FROM product_categories category
WHERE category.id = item.product_category
  AND category.name IN ('Сувениры, мерч', 'Нанесение')
  AND item.quantity > 0
  AND item.technical_task_text IS NOT NULL
  AND btrim(item.technical_task_text) <> ''
  AND item.technical_task_text LIKE item.product_name || ',%'
  AND item.technical_task_text NOT ILIKE '%'
    || item.quantity::text
    || ' шт.%'
  AND EXISTS (
    SELECT 1
    FROM screen_printing_work work
    WHERE work.id = item.id
  );

COMMIT;

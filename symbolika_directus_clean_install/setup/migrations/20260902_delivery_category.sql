-- Add delivery as a non-physical order item category.
-- Delivery remains visible in the order and finances, but does not participate
-- in office issue workflows and does not require a category detail selector.

BEGIN;

INSERT INTO product_categories (name, detail_mode, sort, is_active, office_applicable)
SELECT U&'\0414\043e\0441\0442\0430\0432\043a\0430', 'none', 120, true, false
WHERE NOT EXISTS (
  SELECT 1
  FROM product_categories
  WHERE lower(trim(name)) = lower(trim(U&'\0414\043e\0441\0442\0430\0432\043a\0430'))
);

UPDATE product_categories
SET detail_mode = 'none',
    sort = 120,
    is_active = true,
    office_applicable = false
WHERE lower(trim(name)) = lower(trim(U&'\0414\043e\0441\0442\0430\0432\043a\0430'));

UPDATE orders_items item
SET office_status = NULL
FROM product_categories category
WHERE category.id = item.product_category
  AND lower(trim(category.name)) = lower(trim(U&'\0414\043e\0441\0442\0430\0432\043a\0430'))
  AND item.office_status IS NOT NULL;

COMMIT;

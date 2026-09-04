-- Rollup positions use exactly two counterparty slots:
-- contractor_1 is the construction/blank supplier and contractor_2 is the
-- application executor. Normalize legacy rows created before rollups were
-- recognized as products with a blank.
UPDATE public.orders_items AS item
SET blank_source = 'supplier'
FROM public.product_categories AS category
WHERE category.id = item.product_category
  AND lower(coalesce(category.name, '')) LIKE U&'%\043A\043E\043D\0441\0442\0440\0443\043A\0446%'
  AND (
    lower(coalesce(item.product_name, '')) LIKE U&'%\0440\043E\043B\0430\043F%'
    OR lower(coalesce(item.product_name, '')) LIKE U&'%\0440\043E\043B\043B\0430\043F%'
    OR EXISTS (
      SELECT 1
      FROM public.product_subcategories AS subcategory
      WHERE subcategory.id = item.product_subcategory
        AND (
          lower(coalesce(subcategory.name, '')) LIKE U&'%\0440\043E\043B\0430\043F%'
          OR lower(coalesce(subcategory.name, '')) LIKE U&'%\0440\043E\043B\043B\0430\043F%'
        )
    )
  )
  AND coalesce(item.blank_source, 'none') = 'none';

-- Add mounting as an order category and expose Piar as its work executor.
-- Keep this migration idempotent for both existing VPS installations and
-- clean local environments.

BEGIN;

INSERT INTO product_categories (name, detail_mode, sort, is_active, office_applicable)
SELECT U&'\041c\043e\043d\0442\0430\0436', 'none', 105, true, true
WHERE NOT EXISTS (
  SELECT 1
  FROM product_categories
  WHERE lower(trim(name)) = lower(trim(U&'\041c\043e\043d\0442\0430\0436'))
);

UPDATE product_categories
SET detail_mode = 'none',
    sort = 105,
    is_active = true,
    office_applicable = true
WHERE lower(trim(name)) = lower(trim(U&'\041c\043e\043d\0442\0430\0436'));

INSERT INTO contractors (
  name, comment, supplier_kind, can_mount, approval_status
)
SELECT
  U&'\041f\0438\0430\0440',
  U&'\041c\043e\043d\0442\0430\0436\043d\044b\0435 \0440\0430\0431\043e\0442\044b',
  'contractor', true, 'approved'
WHERE NOT EXISTS (
  SELECT 1
  FROM contractors
  WHERE lower(trim(name)) = lower(trim(U&'\041f\0438\0430\0440'))
);

UPDATE contractors
SET can_mount = true
WHERE lower(trim(name)) = lower(trim(U&'\041f\0438\0430\0440'));

INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, product_subcategory,
  application_method, priority, is_active
)
SELECT
  contractor.id, 'executor', category.id, NULL,
  NULL, 10, true
FROM contractors contractor
CROSS JOIN product_categories category
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041f\0438\0430\0440'))
  AND lower(trim(category.name)) = lower(trim(U&'\041c\043e\043d\0442\0430\0436'))
  AND COALESCE(contractor.approval_status, 'approved') = 'approved'
ON CONFLICT (
  contractor, capability_type, product_category,
  (COALESCE(product_subcategory, 0)), (COALESCE(application_method, 0))
) DO UPDATE SET priority = 10, is_active = true;

COMMIT;

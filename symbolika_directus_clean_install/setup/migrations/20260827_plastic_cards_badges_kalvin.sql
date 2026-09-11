BEGIN;

-- Plastic cards and badges belong to printing and are made by the internal
-- personal executor Kalvin Maksim. The executor uses the existing contractor
-- routing layer, while its Directus account is inherited from employees.
WITH requested(name, sort) AS (VALUES
  (U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b', 110),
  (U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438', 120)
)
INSERT INTO product_subcategories (category, name, sort, is_active)
SELECT category.id, requested.name, requested.sort, true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f'))
WHERE NOT EXISTS (
  SELECT 1
  FROM product_subcategories existing
  WHERE existing.category = category.id
    AND lower(trim(existing.name)) = lower(trim(requested.name))
);

WITH requested(name, sort) AS (VALUES
  (U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b', 110),
  (U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438', 120)
)
UPDATE product_subcategories subcategory
SET sort = requested.sort,
    is_active = true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f'))
WHERE subcategory.category = category.id
  AND lower(trim(subcategory.name)) = lower(trim(requested.name));

INSERT INTO contractors (
  name, contact_name, directus_user, approval_status, is_internal_production
)
SELECT
  U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c',
  U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c',
  employee.directus_user,
  'approved',
  true
FROM (SELECT 1) seed
LEFT JOIN LATERAL (
  SELECT employees.directus_user
  FROM employees
  WHERE lower(trim(employees.full_name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  ORDER BY employees.id
  LIMIT 1
) employee ON true
WHERE NOT EXISTS (
  SELECT 1
  FROM contractors
  WHERE lower(trim(contractors.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
);

UPDATE contractors contractor
SET contact_name = COALESCE(NULLIF(contractor.contact_name, ''), U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'),
    approval_status = 'approved',
    is_internal_production = true
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
;

UPDATE contractors contractor
SET directus_user = employee.directus_user
FROM employees employee
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  AND lower(trim(employee.full_name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  AND contractor.directus_user IS NULL
  AND employee.directus_user IS NOT NULL;

INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, product_subcategory,
  application_method, priority, is_active
)
SELECT
  contractor.id,
  'executor',
  category.id,
  subcategory.id,
  NULL,
  1,
  true
FROM contractors contractor
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f'))
JOIN product_subcategories subcategory
  ON subcategory.category = category.id
 AND lower(trim(subcategory.name)) IN (
   lower(trim(U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b')),
   lower(trim(U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438'))
 )
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
ON CONFLICT (
  contractor, capability_type, product_category,
  (COALESCE(product_subcategory, 0)), (COALESCE(application_method, 0))
) DO UPDATE SET priority = 1, is_active = true;

COMMIT;

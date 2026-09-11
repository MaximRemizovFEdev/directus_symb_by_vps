BEGIN;

-- Award products use both a product subtype and an application method.
INSERT INTO product_categories (name, detail_mode, sort, is_active, office_applicable)
SELECT U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f',
       'subcategory', 55, true, true
WHERE NOT EXISTS (
  SELECT 1 FROM product_categories
  WHERE lower(trim(name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'))
);

UPDATE product_categories
SET detail_mode = 'subcategory', sort = 55, is_active = true, office_applicable = true
WHERE lower(trim(name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'));

WITH requested(name, sort) AS (VALUES
  (U&'\041a\0443\0431\043a\0438', 10),
  (U&'\041c\0435\0434\0430\043b\0438', 20),
  (U&'\0421\0442\0435\043b\044b', 30),
  (U&'\041b\0435\043d\0442\044b', 40)
)
INSERT INTO product_subcategories (category, name, sort, is_active)
SELECT category.id, requested.name, requested.sort, true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'))
WHERE NOT EXISTS (
  SELECT 1 FROM product_subcategories existing
  WHERE existing.category = category.id
    AND lower(trim(existing.name)) = lower(trim(requested.name))
);

WITH requested(name, sort) AS (VALUES
  (U&'\041a\0443\0431\043a\0438', 10),
  (U&'\041c\0435\0434\0430\043b\0438', 20),
  (U&'\0421\0442\0435\043b\044b', 30),
  (U&'\041b\0435\043d\0442\044b', 40)
)
UPDATE product_subcategories subcategory
SET sort = requested.sort, is_active = true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'))
WHERE subcategory.category = category.id
  AND lower(trim(subcategory.name)) = lower(trim(requested.name));

WITH requested(name, sort) AS (VALUES
  (U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 10),
  (U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 20),
  (U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 30),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', 40)
)
INSERT INTO product_application_methods (category, name, sort, is_active)
SELECT category.id, requested.name, requested.sort, true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'))
WHERE NOT EXISTS (
  SELECT 1 FROM product_application_methods existing
  WHERE existing.category = category.id
    AND lower(trim(existing.name)) = lower(trim(requested.name))
);

WITH requested(name, sort) AS (VALUES
  (U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 10),
  (U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 20),
  (U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 30),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', 40)
)
UPDATE product_application_methods method
SET sort = requested.sort, is_active = true
FROM requested
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041d\0430\0433\0440\0430\0434\043d\0430\044f \043f\0440\043e\0434\0443\043a\0446\0438\044f'))
WHERE method.category = category.id
  AND lower(trim(method.name)) = lower(trim(requested.name));

COMMIT;

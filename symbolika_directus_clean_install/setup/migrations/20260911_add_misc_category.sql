BEGIN;

INSERT INTO product_categories (name, detail_mode, sort, is_active, office_applicable)
SELECT U&'\041f\0440\043e\0447\0435\0435', 'none', 130, true, true
WHERE NOT EXISTS (
  SELECT 1 FROM product_categories
  WHERE lower(trim(name)) = lower(trim(U&'\041f\0440\043e\0447\0435\0435'))
);

UPDATE product_categories
SET detail_mode = 'none', sort = 130, is_active = true, office_applicable = true
WHERE lower(trim(name)) = lower(trim(U&'\041f\0440\043e\0447\0435\0435'));

COMMIT;

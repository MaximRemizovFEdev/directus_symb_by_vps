BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Managing supervises all orders, so the costing read model must not hide
-- totals or scope rows to the current employee. Editing stays limited to the
-- six source fields supported by the synchronized costing table.
DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000205'
  AND collection = 'contractor_costing';

INSERT INTO directus_permissions
  (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('contractor_costing', 'read', '{}'::json, NULL, NULL, '*',
   '00000000-0000-4000-8000-000000000205'),
  ('contractor_costing', 'update', '{}'::json, NULL, NULL,
   'blank_source,blank_ordered,contractor_1,contractor_2,contractor_1_cost,contractor_2_cost',
   '00000000-0000-4000-8000-000000000205');

COMMIT;

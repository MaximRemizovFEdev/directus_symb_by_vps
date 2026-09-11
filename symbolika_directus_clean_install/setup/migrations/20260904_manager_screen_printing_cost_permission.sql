BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- The manager UI includes this persisted cost in its editable item mask.
-- Keep the existing own-order row filter intact and extend only the field
-- list, so managers still cannot read or update another manager's positions.
UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'screen_printing_cost_per_unit')
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND NOT ('screen_printing_cost_per_unit' = ANY(string_to_array(fields, ',')))
  AND policy = '00000000-0000-4000-8000-000000000202';

COMMIT;

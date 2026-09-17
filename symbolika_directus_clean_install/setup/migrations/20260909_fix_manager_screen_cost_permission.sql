BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- The manager role is attached to policy ...201 in the live installation.
-- An earlier migration only updated the legacy ...202 policy, so requesting
-- this field made Directus reject the complete order-item response. That also
-- made an already uploaded layout look as though it had disappeared.
UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'screen_printing_cost_per_unit')
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND NOT ('screen_printing_cost_per_unit' = ANY(string_to_array(fields, ',')))
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

COMMIT;

BEGIN;

-- Cancelled order items are terminal and may be removed deliberately after
-- confirmation. Preserve every role's existing ownership filter and only
-- extend the set of deletable workflow statuses.
UPDATE directus_permissions
SET permissions = regexp_replace(
  permissions::text,
  '"_in"\s*:\s*\[\s*"new"\s*,\s*"approval"\s*\]',
  '"_in":["new","approval","cancelled"]',
  'g'
)::json
WHERE collection = 'orders_items'
  AND action = 'delete'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  )
  AND permissions::text NOT LIKE '%"cancelled"%';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM directus_permissions
    WHERE collection = 'orders_items'
      AND action = 'delete'
      AND policy IN (
        '00000000-0000-4000-8000-000000000201',
        '00000000-0000-4000-8000-000000000202',
        '00000000-0000-4000-8000-000000000204',
        '00000000-0000-4000-8000-000000000205',
        '00000000-0000-4000-8000-000000000206',
        '00000000-0000-4000-8000-000000000208'
      )
      AND permissions::text NOT LIKE '%"cancelled"%'
  ) THEN
    RAISE EXCEPTION 'Failed to enable deletion of cancelled order items';
  END IF;
END
$$;

COMMIT;

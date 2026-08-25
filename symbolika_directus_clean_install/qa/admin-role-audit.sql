\pset pager off

WITH administrator_roles AS (
  SELECT role.id,
         COUNT(DISTINCT users.id) AS users_count,
         COUNT(DISTINCT access.id) AS access_count,
         COUNT(DISTINCT presets.id) AS presets_count,
         COUNT(DISTINCT child_roles.id) AS child_roles_count
  FROM directus_roles role
  LEFT JOIN directus_users users ON users.role = role.id
  LEFT JOIN directus_access access ON access.role = role.id
  LEFT JOIN directus_presets presets ON presets.role = role.id
  LEFT JOIN directus_roles child_roles ON child_roles.parent = role.id
  WHERE role.name = 'Administrator'
  GROUP BY role.id
)
SELECT * FROM administrator_roles ORDER BY id;

SELECT policy.id,
       policy.name,
       policy.admin_access,
       policy.app_access,
       COUNT(DISTINCT access.id) AS access_refs,
       COUNT(DISTINCT permission.id) AS permission_rows
FROM directus_policies policy
LEFT JOIN directus_access access ON access.policy = policy.id
LEFT JOIN directus_permissions permission ON permission.policy = policy.id
WHERE policy.id IN (
  SELECT access.policy
  FROM directus_access access
  JOIN directus_roles role ON role.id = access.role
  WHERE role.name = 'Administrator'
)
GROUP BY policy.id
ORDER BY policy.id;

WITH permission_rows AS (
  SELECT policy,
         collection,
         action,
         COALESCE(permissions::TEXT, '') AS permissions,
         COALESCE(validation::TEXT, '') AS validation,
         COALESCE(presets::TEXT, '') AS presets,
         COALESCE(fields, '') AS fields
  FROM directus_permissions
  WHERE policy IN (
    'eccf79d5-45f2-478a-a970-fa727b0d9dee',
    '2cd5f529-c4a0-4326-aba4-79dd72967bbc'
  )
), permission_diff AS (
  SELECT collection, action, permissions, validation, presets, fields
  FROM permission_rows
  WHERE policy = 'eccf79d5-45f2-478a-a970-fa727b0d9dee'
  EXCEPT ALL
  SELECT collection, action, permissions, validation, presets, fields
  FROM permission_rows
  WHERE policy = '2cd5f529-c4a0-4326-aba4-79dd72967bbc'
)
SELECT 'keeper_permission_rows_missing_from_duplicate' AS check_name,
       CASE
         WHEN EXISTS (
           SELECT 1
           FROM directus_policies
           WHERE id = '2cd5f529-c4a0-4326-aba4-79dd72967bbc'
         ) THEN (SELECT COUNT(*) FROM permission_diff)
         ELSE 0
       END AS difference_count;

WITH duplicate_presets AS (
  SELECT bookmark,
         "user",
         collection,
         search,
         layout,
         COALESCE(layout_query::TEXT, '') AS layout_query,
         COALESCE(layout_options::TEXT, '') AS layout_options,
         refresh_interval,
         COALESCE(filter::TEXT, '') AS filter,
         icon,
         color
  FROM directus_presets
  WHERE role = '8d096ec4-c189-44a5-ae91-28e7a3c12857'
), keeper_presets AS (
  SELECT bookmark,
         "user",
         collection,
         search,
         layout,
         COALESCE(layout_query::TEXT, '') AS layout_query,
         COALESCE(layout_options::TEXT, '') AS layout_options,
         refresh_interval,
         COALESCE(filter::TEXT, '') AS filter,
         icon,
         color
  FROM directus_presets
  WHERE role = '7f3a96c2-f968-437b-8202-8593bb775e97'
), preset_diff AS (
  SELECT * FROM duplicate_presets
  EXCEPT ALL
  SELECT * FROM keeper_presets
)
SELECT 'duplicate_presets_missing_from_keeper' AS check_name,
       COUNT(*) AS difference_count
FROM preset_diff;

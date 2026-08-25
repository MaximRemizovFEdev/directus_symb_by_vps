\set ON_ERROR_STOP on

BEGIN;

-- Two Administrator roles were accidentally created with equivalent policies.
-- Keep the role used by the real administrator and archive/remove only the
-- unreferenced duplicate after strict structural checks. Any unexpected state
-- aborts the whole transaction before data is changed.
DO $$
DECLARE
  keeper_role CONSTANT UUID := '7f3a96c2-f968-437b-8202-8593bb775e97';
  duplicate_role CONSTANT UUID := '8d096ec4-c189-44a5-ae91-28e7a3c12857';
  keeper_policy CONSTANT UUID := 'eccf79d5-45f2-478a-a970-fa727b0d9dee';
  duplicate_policy CONSTANT UUID := '2cd5f529-c4a0-4326-aba4-79dd72967bbc';
  unexpected_count BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.directus_roles WHERE id = keeper_role) THEN
    RAISE EXCEPTION 'Keeper Administrator role % is missing', keeper_role;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.directus_policies WHERE id = keeper_policy) THEN
    RAISE EXCEPTION 'Keeper Administrator policy % is missing', keeper_policy;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.directus_roles WHERE id = duplicate_role) THEN
    IF EXISTS (SELECT 1 FROM public.directus_policies WHERE id = duplicate_policy) THEN
      RAISE EXCEPTION 'Duplicate role is absent, but duplicate policy % remains', duplicate_policy;
    END IF;
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.directus_policies WHERE id = duplicate_policy) THEN
    RAISE EXCEPTION 'Duplicate Administrator policy % is missing', duplicate_policy;
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.directus_users
  WHERE role = duplicate_role;
  IF unexpected_count <> 0 THEN
    RAISE EXCEPTION 'Duplicate Administrator role still has % user(s)', unexpected_count;
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.directus_roles
  WHERE parent = duplicate_role;
  IF unexpected_count <> 0 THEN
    RAISE EXCEPTION 'Duplicate Administrator role still has % child role(s)', unexpected_count;
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.directus_shares
  WHERE role = duplicate_role;
  IF unexpected_count <> 0 THEN
    RAISE EXCEPTION 'Duplicate Administrator role still has % share reference(s)', unexpected_count;
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.directus_settings
  WHERE public_registration_role = duplicate_role;
  IF unexpected_count <> 0 THEN
    RAISE EXCEPTION 'Duplicate Administrator role is configured for public registration';
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.directus_access
  WHERE role = duplicate_role
    AND "user" IS NULL
    AND policy = duplicate_policy;
  IF unexpected_count <> 1 OR (
    SELECT COUNT(*) FROM public.directus_access
    WHERE role = duplicate_role OR policy = duplicate_policy
  ) <> 1 THEN
    RAISE EXCEPTION 'Duplicate role/policy access mapping is not the expected single row';
  END IF;

  IF EXISTS (
    SELECT name, icon, description, ip_access, enforce_tfa, admin_access, app_access
    FROM public.directus_policies
    WHERE id = keeper_policy
    EXCEPT ALL
    SELECT name, icon, description, ip_access, enforce_tfa, admin_access, app_access
    FROM public.directus_policies
    WHERE id = duplicate_policy
  ) OR EXISTS (
    SELECT name, icon, description, ip_access, enforce_tfa, admin_access, app_access
    FROM public.directus_policies
    WHERE id = duplicate_policy
    EXCEPT ALL
    SELECT name, icon, description, ip_access, enforce_tfa, admin_access, app_access
    FROM public.directus_policies
    WHERE id = keeper_policy
  ) THEN
    RAISE EXCEPTION 'Administrator policies are no longer structurally equivalent';
  END IF;

  IF EXISTS (
    SELECT collection,
           action,
           COALESCE(permissions::TEXT, ''),
           COALESCE(validation::TEXT, ''),
           COALESCE(presets::TEXT, ''),
           COALESCE(fields, '')
    FROM public.directus_permissions
    WHERE policy = keeper_policy
    EXCEPT ALL
    SELECT collection,
           action,
           COALESCE(permissions::TEXT, ''),
           COALESCE(validation::TEXT, ''),
           COALESCE(presets::TEXT, ''),
           COALESCE(fields, '')
    FROM public.directus_permissions
    WHERE policy = duplicate_policy
  ) OR EXISTS (
    SELECT collection,
           action,
           COALESCE(permissions::TEXT, ''),
           COALESCE(validation::TEXT, ''),
           COALESCE(presets::TEXT, ''),
           COALESCE(fields, '')
    FROM public.directus_permissions
    WHERE policy = duplicate_policy
    EXCEPT ALL
    SELECT collection,
           action,
           COALESCE(permissions::TEXT, ''),
           COALESCE(validation::TEXT, ''),
           COALESCE(presets::TEXT, ''),
           COALESCE(fields, '')
    FROM public.directus_permissions
    WHERE policy = keeper_policy
  ) THEN
    RAISE EXCEPTION 'Administrator permission sets are no longer equivalent';
  END IF;

  -- The duplicate has one fewer preset. Every one of its presets must be an
  -- exact subset of the keeper role presets; the keeper-only preset is retained.
  IF EXISTS (
    SELECT bookmark,
           "user",
           collection,
           search,
           layout,
           COALESCE(layout_query::TEXT, ''),
           COALESCE(layout_options::TEXT, ''),
           refresh_interval,
           COALESCE(filter::TEXT, ''),
           icon,
           color
    FROM public.directus_presets
    WHERE role = duplicate_role
    EXCEPT ALL
    SELECT bookmark,
           "user",
           collection,
           search,
           layout,
           COALESCE(layout_query::TEXT, ''),
           COALESCE(layout_options::TEXT, ''),
           refresh_interval,
           COALESCE(filter::TEXT, ''),
           icon,
           color
    FROM public.directus_presets
    WHERE role = keeper_role
  ) THEN
    RAISE EXCEPTION 'Duplicate Administrator presets are not a subset of keeper presets';
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS symbolika_archive;

CREATE TABLE IF NOT EXISTS symbolika_archive.directus_roles_duplicate_admin_20260825
  AS SELECT * FROM public.directus_roles WITH NO DATA;
CREATE TABLE IF NOT EXISTS symbolika_archive.directus_policies_duplicate_admin_20260825
  AS SELECT * FROM public.directus_policies WITH NO DATA;
CREATE TABLE IF NOT EXISTS symbolika_archive.directus_access_duplicate_admin_20260825
  AS SELECT * FROM public.directus_access WITH NO DATA;
CREATE TABLE IF NOT EXISTS symbolika_archive.directus_permissions_duplicate_admin_20260825
  AS SELECT * FROM public.directus_permissions WITH NO DATA;
CREATE TABLE IF NOT EXISTS symbolika_archive.directus_presets_duplicate_admin_20260825
  AS SELECT * FROM public.directus_presets WITH NO DATA;

INSERT INTO symbolika_archive.directus_roles_duplicate_admin_20260825
SELECT source.*
FROM public.directus_roles source
WHERE source.id = '8d096ec4-c189-44a5-ae91-28e7a3c12857'
  AND NOT EXISTS (
    SELECT 1
    FROM symbolika_archive.directus_roles_duplicate_admin_20260825 archived
    WHERE archived.id = source.id
  );

INSERT INTO symbolika_archive.directus_policies_duplicate_admin_20260825
SELECT source.*
FROM public.directus_policies source
WHERE source.id = '2cd5f529-c4a0-4326-aba4-79dd72967bbc'
  AND NOT EXISTS (
    SELECT 1
    FROM symbolika_archive.directus_policies_duplicate_admin_20260825 archived
    WHERE archived.id = source.id
  );

INSERT INTO symbolika_archive.directus_access_duplicate_admin_20260825
SELECT source.*
FROM public.directus_access source
WHERE source.role = '8d096ec4-c189-44a5-ae91-28e7a3c12857'
   OR source.policy = '2cd5f529-c4a0-4326-aba4-79dd72967bbc';

INSERT INTO symbolika_archive.directus_permissions_duplicate_admin_20260825
SELECT source.*
FROM public.directus_permissions source
WHERE source.policy = '2cd5f529-c4a0-4326-aba4-79dd72967bbc'
  AND NOT EXISTS (
    SELECT 1
    FROM symbolika_archive.directus_permissions_duplicate_admin_20260825 archived
    WHERE archived.id = source.id
  );

INSERT INTO symbolika_archive.directus_presets_duplicate_admin_20260825
SELECT source.*
FROM public.directus_presets source
WHERE source.role = '8d096ec4-c189-44a5-ae91-28e7a3c12857'
  AND NOT EXISTS (
    SELECT 1
    FROM symbolika_archive.directus_presets_duplicate_admin_20260825 archived
    WHERE archived.id = source.id
  );

DELETE FROM public.directus_presets
WHERE role = '8d096ec4-c189-44a5-ae91-28e7a3c12857';

DELETE FROM public.directus_permissions
WHERE policy = '2cd5f529-c4a0-4326-aba4-79dd72967bbc';

DELETE FROM public.directus_access
WHERE role = '8d096ec4-c189-44a5-ae91-28e7a3c12857'
   OR policy = '2cd5f529-c4a0-4326-aba4-79dd72967bbc';

DELETE FROM public.directus_policies
WHERE id = '2cd5f529-c4a0-4326-aba4-79dd72967bbc';

DELETE FROM public.directus_roles
WHERE id = '8d096ec4-c189-44a5-ae91-28e7a3c12857';

COMMIT;

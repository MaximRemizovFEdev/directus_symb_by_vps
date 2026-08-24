\set ON_ERROR_STOP on

BEGIN;

-- Directus expects one scalar primary key for a collection. Preserve existing
-- read marks while migrating the historical composite (news, user) key.
ALTER TABLE public.symbolika_news_reads ADD COLUMN IF NOT EXISTS id BIGINT;
CREATE SEQUENCE IF NOT EXISTS public.symbolika_news_reads_id_seq;
ALTER SEQUENCE public.symbolika_news_reads_id_seq
  OWNED BY public.symbolika_news_reads.id;
ALTER TABLE public.symbolika_news_reads
  ALTER COLUMN id SET DEFAULT nextval('public.symbolika_news_reads_id_seq');
UPDATE public.symbolika_news_reads
SET id = nextval('public.symbolika_news_reads_id_seq')
WHERE id IS NULL;
SELECT setval(
  'public.symbolika_news_reads_id_seq',
  COALESCE((SELECT MAX(id) FROM public.symbolika_news_reads), 1),
  EXISTS (SELECT 1 FROM public.symbolika_news_reads)
);

DO $$
DECLARE
  current_primary_key TEXT;
BEGIN
  SELECT constraint_name
  INTO current_primary_key
  FROM information_schema.table_constraints
  WHERE table_schema = 'public'
    AND table_name = 'symbolika_news_reads'
    AND constraint_type = 'PRIMARY KEY';

  IF current_primary_key IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM information_schema.key_column_usage
    WHERE table_schema = 'public'
      AND table_name = 'symbolika_news_reads'
      AND constraint_name = current_primary_key
    GROUP BY constraint_name
    HAVING array_agg(column_name::TEXT ORDER BY ordinal_position) = ARRAY['id']::TEXT[]
  ) THEN
    EXECUTE format(
      'ALTER TABLE public.symbolika_news_reads DROP CONSTRAINT %I',
      current_primary_key
    );
    current_primary_key := NULL;
  END IF;

  IF current_primary_key IS NULL THEN
    ALTER TABLE public.symbolika_news_reads
      ADD CONSTRAINT symbolika_news_reads_pkey PRIMARY KEY (id);
  END IF;
END $$;

ALTER TABLE public.symbolika_news_reads ALTER COLUMN id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS symbolika_news_reads_news_user_uidx
  ON public.symbolika_news_reads (news, "user");

-- Keep historical snapshots intact, but outside public so Directus does not
-- expose them as collections or report missing-primary-key warnings.
CREATE SCHEMA IF NOT EXISTS symbolika_archive;
DO $$
DECLARE
  backup_table TEXT;
BEGIN
  FOREACH backup_table IN ARRAY ARRAY[
    'directus_fields_backup_before_access_v2',
    'directus_fields_backup_before_access_v4',
    'directus_fields_backup_before_access_v5',
    'directus_fields_backup_before_readonly_v3',
    'directus_permissions_backup_before_access_v2',
    'directus_permissions_backup_before_access_v4',
    'directus_permissions_backup_before_access_v5'
  ] LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = backup_table
        AND c.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I SET SCHEMA symbolika_archive',
        backup_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;

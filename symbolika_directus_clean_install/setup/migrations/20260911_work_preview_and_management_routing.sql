BEGIN;

ALTER TABLE production_work ADD COLUMN IF NOT EXISTS layout_preview_url text;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS layout_preview_disk_name text;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS layout_preview_disk_size bigint;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS layout_preview_disk_mime_type character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS layout_preview_uploaded_at timestamptz;

ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS layout_preview_url text;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS layout_preview_disk_name text;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS layout_preview_disk_size bigint;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS layout_preview_disk_mime_type character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS layout_preview_uploaded_at timestamptz;

CREATE OR REPLACE FUNCTION symbolika_fill_work_layout_preview()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT
    oi.layout_preview_url,
    oi.layout_preview_disk_name,
    oi.layout_preview_disk_size,
    oi.layout_preview_disk_mime_type,
    oi.layout_preview_uploaded_at
  INTO
    NEW.layout_preview_url,
    NEW.layout_preview_disk_name,
    NEW.layout_preview_disk_size,
    NEW.layout_preview_disk_mime_type,
    NEW.layout_preview_uploaded_at
  FROM orders_items oi
  WHERE oi.id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_production_work_layout_preview ON production_work;
CREATE TRIGGER symbolika_production_work_layout_preview
BEFORE INSERT ON production_work
FOR EACH ROW
EXECUTE FUNCTION symbolika_fill_work_layout_preview();

DROP TRIGGER IF EXISTS symbolika_screen_work_layout_preview ON screen_printing_work;
CREATE TRIGGER symbolika_screen_work_layout_preview
BEFORE INSERT ON screen_printing_work
FOR EACH ROW
EXECUTE FUNCTION symbolika_fill_work_layout_preview();

UPDATE production_work work
SET layout_preview_url = item.layout_preview_url,
    layout_preview_disk_name = item.layout_preview_disk_name,
    layout_preview_disk_size = item.layout_preview_disk_size,
    layout_preview_disk_mime_type = item.layout_preview_disk_mime_type,
    layout_preview_uploaded_at = item.layout_preview_uploaded_at
FROM orders_items item
WHERE item.id = work.id;

UPDATE screen_printing_work work
SET layout_preview_url = item.layout_preview_url,
    layout_preview_disk_name = item.layout_preview_disk_name,
    layout_preview_disk_size = item.layout_preview_disk_size,
    layout_preview_disk_mime_type = item.layout_preview_disk_mime_type,
    layout_preview_uploaded_at = item.layout_preview_uploaded_at
FROM orders_items item
WHERE item.id = work.id;

UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''),
  'layout_preview_url,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at')
WHERE collection = 'production_work'
  AND action = 'read'
  AND policy = '00000000-0000-4000-8000-000000000204'
  AND COALESCE(fields, '') NOT LIKE '%layout_preview_url%';

UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''),
  'layout_preview_url,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at')
WHERE collection = 'screen_printing_work'
  AND action = 'read'
  AND policy = '00000000-0000-4000-8000-000000000206'
  AND COALESCE(fields, '') NOT LIKE '%layout_preview_url%';

COMMIT;

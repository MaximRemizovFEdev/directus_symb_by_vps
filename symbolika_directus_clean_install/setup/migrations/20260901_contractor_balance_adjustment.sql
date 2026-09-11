BEGIN;

ALTER TABLE contractors ADD COLUMN IF NOT EXISTS balance_adjustment numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS balance_adjustment_comment text;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS balance_adjusted_at timestamptz;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS balance_adjusted_by uuid REFERENCES directus_users(id) ON DELETE SET NULL;

COMMIT;

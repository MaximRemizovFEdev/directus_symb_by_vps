BEGIN;
ALTER TABLE symbolika_tbank_payments ADD COLUMN IF NOT EXISTS public_token uuid UNIQUE;
ALTER TABLE symbolika_tbank_payments ADD COLUMN IF NOT EXISTS sbp_url text;
COMMIT;

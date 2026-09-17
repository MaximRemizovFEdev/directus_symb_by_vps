BEGIN;

-- An allocation now targets either an order or a customer operation. Keep the
-- Directus metadata aligned with the nullable database column; otherwise a
-- create request can be rejected before the one-target database constraint is
-- evaluated.
ALTER TABLE payment_allocations ALTER COLUMN "order" DROP NOT NULL;

UPDATE directus_fields
SET required = false
WHERE collection = 'payment_allocations'
  AND field = 'order';

COMMIT;

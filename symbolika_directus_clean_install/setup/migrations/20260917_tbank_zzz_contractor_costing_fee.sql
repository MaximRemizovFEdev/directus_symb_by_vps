BEGIN;

ALTER TABLE contractor_costing
  ADD COLUMN IF NOT EXISTS acquiring_fee_sum numeric(14,2) NOT NULL DEFAULT 0;

UPDATE contractor_costing costing
   SET acquiring_fee_sum = COALESCE(item.acquiring_fee_sum, 0)
  FROM orders_items item
 WHERE item.id = costing.id;

CREATE OR REPLACE FUNCTION symbolika_sync_canonical_contractor_costing_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  UPDATE contractor_costing costing
  SET unit_cost = NEW.unit_cost,
      total_cost = NEW.total_cost,
      manager_commission_sum = NEW.manager_commission_sum,
      tax_sum = NEW.tax_sum,
      acquiring_fee_sum = NEW.acquiring_fee_sum,
      profit_sum = NEW.profit_sum,
      margin_percent = NEW.margin_percent
  WHERE costing.id = NEW.id;

  RETURN NEW;
END;
$$;

UPDATE directus_fields
   SET readonly = true,
       hidden = false,
       translations = json_build_array(json_build_object('language', 'ru-RU', 'translation', 'Эквайринг'))::json
 WHERE collection = 'contractor_costing'
   AND field = 'acquiring_fee_sum';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations
)
SELECT
  'contractor_costing', 'acquiring_fee_sum', NULL, 'input', NULL, NULL, NULL,
  true, false, 26, 'half',
  json_build_array(json_build_object('language', 'ru-RU', 'translation', 'Эквайринг'))::json
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_fields
  WHERE collection = 'contractor_costing'
    AND field = 'acquiring_fee_sum'
);

UPDATE directus_permissions
   SET fields = CASE
     WHEN fields = '*' THEN fields
     WHEN fields IS NULL OR fields = '' THEN 'acquiring_fee_sum'
     WHEN position('acquiring_fee_sum' in fields) > 0 THEN fields
     ELSE fields || ',acquiring_fee_sum'
   END
 WHERE collection = 'contractor_costing'
   AND action = 'read';

COMMIT;

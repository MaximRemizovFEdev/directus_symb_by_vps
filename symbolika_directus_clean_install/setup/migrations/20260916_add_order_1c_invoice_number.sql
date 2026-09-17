BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);

ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS invoice_number_1c character varying(255);

CREATE OR REPLACE FUNCTION symbolika_fill_order_invoice_number_1c()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT o.invoice_number_1c
    INTO NEW.invoice_number_1c
    FROM orders o
   WHERE o.id = NEW.id;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  mirror_table text;
BEGIN
  FOREACH mirror_table IN ARRAY ARRAY[
    'orders_overview',
    'orders_due_today',
    'orders_due_this_week',
    'orders_due_next_week',
    'orders_due_this_month',
    'orders_due_urgent',
    'orders_due_next_month',
    'my_orders_in_work',
    'my_orders_completed',
    'my_orders_unpaid'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS symbolika_fill_order_invoice_number_1c ON %I', mirror_table);
    EXECUTE format(
      'CREATE TRIGGER symbolika_fill_order_invoice_number_1c BEFORE INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION symbolika_fill_order_invoice_number_1c()',
      mirror_table
    );
    EXECUTE format(
      'UPDATE %I mirror SET invoice_number_1c = orders.invoice_number_1c FROM orders WHERE orders.id = mirror.id',
      mirror_table
    );
  END LOOP;
END;
$$;

DELETE FROM directus_fields
WHERE field = 'invoice_number_1c'
  AND collection IN (
    'orders',
    'orders_overview',
    'orders_due_today',
    'orders_due_this_week',
    'orders_due_next_week',
    'orders_due_this_month',
    'orders_due_urgent',
    'orders_due_next_month',
    'my_orders_in_work',
    'my_orders_completed',
    'my_orders_unpaid'
  );

INSERT INTO directus_fields (
  collection, field, interface, readonly, hidden, sort, width, translations, required, searchable, "group"
) VALUES (
  'orders', 'invoice_number_1c', 'input', false, false, 7, 'half',
  json_build_array(json_build_object('language','ru-RU','translation','Номер счёта в 1С'))::json,
  false, true, 'payment'
);

INSERT INTO directus_fields (
  collection, field, interface, readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  collection_name, 'invoice_number_1c', 'input', true, false, 4, 'half',
  json_build_array(json_build_object('language','ru-RU','translation','Номер счёта в 1С'))::json,
  false, true
FROM (VALUES
  ('orders_overview'),
  ('orders_due_today'),
  ('orders_due_this_week'),
  ('orders_due_next_week'),
  ('orders_due_this_month'),
  ('orders_due_urgent'),
  ('orders_due_next_month'),
  ('my_orders_in_work'),
  ('my_orders_completed'),
  ('my_orders_unpaid')
) AS collections(collection_name);

UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'invoice_number_1c')
WHERE collection = 'orders'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND NOT ('invoice_number_1c' = ANY(string_to_array(fields, ',')));

COMMIT;

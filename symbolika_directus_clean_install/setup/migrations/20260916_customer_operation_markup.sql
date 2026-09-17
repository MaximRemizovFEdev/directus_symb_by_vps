BEGIN;

ALTER TABLE customer_operations
  ADD COLUMN IF NOT EXISTS actual_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS markup_percent numeric(7,3) NOT NULL DEFAULT 0;

UPDATE customer_operations
SET actual_amount = amount,
    markup_percent = 0
WHERE actual_amount IS NULL OR actual_amount <= 0;

ALTER TABLE customer_operations
  ALTER COLUMN actual_amount SET DEFAULT 0,
  ALTER COLUMN actual_amount SET NOT NULL;

ALTER TABLE customer_operations
  DROP CONSTRAINT IF EXISTS customer_operations_actual_amount_positive;
ALTER TABLE customer_operations
  ADD CONSTRAINT customer_operations_actual_amount_positive CHECK (actual_amount > 0);
ALTER TABLE customer_operations
  DROP CONSTRAINT IF EXISTS customer_operations_markup_percent_valid;
ALTER TABLE customer_operations
  ADD CONSTRAINT customer_operations_markup_percent_valid CHECK (markup_percent >= 0 AND markup_percent <= 1000);

CREATE OR REPLACE FUNCTION symbolika_prepare_customer_operation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.operation_date := COALESCE(NEW.operation_date, CURRENT_DATE);
  -- Backward compatibility for imports that still send only amount.
  IF TG_OP = 'INSERT' AND COALESCE(NEW.actual_amount, 0) <= 0 AND COALESCE(NEW.amount, 0) > 0 THEN
    NEW.actual_amount := NEW.amount;
  END IF;
  NEW.actual_amount := round(COALESCE(NEW.actual_amount, 0), 2);
  NEW.markup_percent := round(COALESCE(NEW.markup_percent, 0), 3);
  IF NEW.markup_percent < 0 OR NEW.markup_percent > 1000 THEN
    RAISE EXCEPTION 'Процент клиентской операции должен быть от 0 до 1000';
  END IF;
  NEW.amount := round(NEW.actual_amount * (1 + NEW.markup_percent / 100), 2);
  NEW.allocated_amount := round(COALESCE(NEW.allocated_amount, 0), 2);
  NEW.payment_due := GREATEST(NEW.amount - NEW.allocated_amount, 0);
  NEW.description := btrim(COALESCE(NEW.description, ''));
  NEW.date_updated := now();

  IF NEW.customer IS NULL AND NEW.customer_company IS NULL THEN
    RAISE EXCEPTION 'Укажите клиента или компанию для операции';
  END IF;
  IF NEW.actual_amount <= 0 THEN
    RAISE EXCEPTION 'Фактическая сумма клиентской операции должна быть больше нуля';
  END IF;
  IF NEW.description = '' THEN
    RAISE EXCEPTION 'Укажите описание клиентской операции';
  END IF;

  IF NEW.manager_employee IS NULL THEN
    IF NEW.customer_company IS NOT NULL THEN
      SELECT cc.manager INTO NEW.manager_employee
      FROM customer_companies cc WHERE cc.id = NEW.customer_company;
    END IF;
    IF NEW.manager_employee IS NULL AND NEW.customer IS NOT NULL THEN
      SELECT c.manager INTO NEW.manager_employee
      FROM customers c WHERE c.id = NEW.customer;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DELETE FROM directus_fields
WHERE collection = 'customer_operations'
  AND field IN ('actual_amount', 'markup_percent');

INSERT INTO directus_fields (
  collection, field, interface, readonly, hidden, sort, width, translations, required
) VALUES
  ('customer_operations','actual_amount','input',false,false,5,'half',json_build_array(json_build_object('language','ru-RU','translation','Фактический расход'))::json,true),
  ('customer_operations','markup_percent','input',false,false,6,'half',json_build_array(json_build_object('language','ru-RU','translation','Процент'))::json,true);

UPDATE directus_fields
SET sort = CASE field
      WHEN 'actual_amount' THEN 5 WHEN 'markup_percent' THEN 6 WHEN 'amount' THEN 7
      WHEN 'customer' THEN 8 WHEN 'customer_company' THEN 9 WHEN 'manager_employee' THEN 10
      WHEN 'status' THEN 11 WHEN 'description' THEN 12 WHEN 'reference' THEN 13
      WHEN 'allocated_amount' THEN 14 WHEN 'payment_due' THEN 15
      WHEN 'date_created' THEN 16 WHEN 'date_updated' THEN 17 ELSE sort END,
    readonly = CASE WHEN field = 'amount' THEN true ELSE readonly END,
    translations = CASE WHEN field = 'amount'
      THEN json_build_array(json_build_object('language','ru-RU','translation','Сумма в сверку'))::json
      ELSE translations END
WHERE collection = 'customer_operations';

UPDATE directus_permissions
SET fields = CASE
  WHEN fields IS NULL OR fields = '*' THEN fields
  ELSE concat_ws(',', fields,
    CASE WHEN position('actual_amount' IN fields) = 0 THEN 'actual_amount' END,
    CASE WHEN position('markup_percent' IN fields) = 0 THEN 'markup_percent' END)
  END
WHERE collection = 'customer_operations'
  AND action IN ('create', 'update');

DELETE FROM directus_fields
WHERE collection = 'customer_reconciliation'
  AND field = 'client_operation';

INSERT INTO directus_fields (
  collection, field, special, interface, display, readonly, hidden, width
) VALUES (
  'customer_reconciliation', 'client_operation', 'm2o', 'select-dropdown-m2o', 'related-values', true, true, 'half'
);

DELETE FROM directus_relations
WHERE many_collection = 'customer_reconciliation'
  AND many_field = 'client_operation';

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES (
  'customer_reconciliation', 'client_operation', 'customer_operations', NULL, 'cascade'
);

SELECT refresh_customer_reconciliation();

COMMIT;

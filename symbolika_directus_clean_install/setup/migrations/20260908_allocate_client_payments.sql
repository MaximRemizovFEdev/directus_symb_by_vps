BEGIN;

ALTER TABLE customer_operations
  ADD COLUMN IF NOT EXISTS allocated_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payment_due numeric(14,2) NOT NULL DEFAULT 0;

ALTER TABLE payment_allocations
  ALTER COLUMN "order" DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS customer_operation integer REFERENCES customer_operations(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS payment_allocations_customer_operation_idx
  ON payment_allocations(customer_operation);

ALTER TABLE payment_allocations
  DROP CONSTRAINT IF EXISTS payment_allocations_one_target_check;
ALTER TABLE payment_allocations
  ADD CONSTRAINT payment_allocations_one_target_check
  CHECK (num_nonnulls("order", customer_operation) = 1);

CREATE OR REPLACE FUNCTION symbolika_prepare_customer_operation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.operation_date := COALESCE(NEW.operation_date, CURRENT_DATE);
  NEW.amount := round(COALESCE(NEW.amount, 0), 2);
  NEW.allocated_amount := round(COALESCE(NEW.allocated_amount, 0), 2);
  NEW.payment_due := GREATEST(NEW.amount - NEW.allocated_amount, 0);
  NEW.description := btrim(COALESCE(NEW.description, ''));
  NEW.date_updated := now();
  IF NEW.customer IS NULL AND NEW.customer_company IS NULL THEN RAISE EXCEPTION 'Укажите клиента или компанию для операции'; END IF;
  IF NEW.amount <= 0 THEN RAISE EXCEPTION 'Сумма клиентской операции должна быть больше нуля'; END IF;
  IF NEW.description = '' THEN RAISE EXCEPTION 'Укажите описание клиентской операции'; END IF;
  IF NEW.manager_employee IS NULL THEN
    IF NEW.customer_company IS NOT NULL THEN
      SELECT cc.manager INTO NEW.manager_employee FROM customer_companies cc WHERE cc.id = NEW.customer_company;
    END IF;
    IF NEW.manager_employee IS NULL AND NEW.customer IS NOT NULL THEN
      SELECT c.manager INTO NEW.manager_employee FROM customers c WHERE c.id = NEW.customer;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_prepare_customer_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  source_order record;
BEGIN
  NEW.amount := round(COALESCE(NEW.amount, 0), 2);
  IF NEW.amount <= 0 THEN
    RAISE EXCEPTION 'Сумма платежа должна быть больше нуля';
  END IF;

  IF NEW."order" IS NOT NULL THEN
    SELECT o.customer, o.customer_company
      INTO source_order
      FROM orders o
     WHERE o.id = NEW."order";
    IF NOT FOUND THEN RAISE EXCEPTION 'Заказ для платежа не найден'; END IF;
    NEW.customer := source_order.customer;
    NEW.customer_company := source_order.customer_company;
  ELSIF num_nonnulls(NEW.customer, NEW.customer_company) <> 1 THEN
    RAISE EXCEPTION 'Для платежа без заказа укажите одного плательщика: клиента или компанию';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_prepare_customer_payment ON order_payments;
CREATE TRIGGER symbolika_prepare_customer_payment
BEFORE INSERT OR UPDATE OF "order", customer, customer_company, amount
ON order_payments
FOR EACH ROW EXECUTE FUNCTION symbolika_prepare_customer_payment();

CREATE OR REPLACE FUNCTION sync_order_payment_access(payment_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE order_payments op
     SET access_manager_user = source.access_manager_user,
         access_shipping_method = source.shipping_method,
         order_number_display = source.order_number,
         customer_name_display = source.customer_name,
         customer_company_name_display = source.company_name
    FROM (
      SELECT
        op2.id,
        COALESCE(order_employee.directus_user, company_employee.directus_user, customer_employee.directus_user) AS access_manager_user,
        o.shipping_method,
        o.order_number,
        COALESCE(c.name, direct_customer.name) AS customer_name,
        COALESCE(cc.name, direct_company.name) AS company_name
      FROM order_payments op2
      LEFT JOIN orders o ON o.id = op2."order"
      LEFT JOIN employees order_employee ON order_employee.id = o.manager_employee
      LEFT JOIN customers c ON c.id = o.customer
      LEFT JOIN customer_companies cc ON cc.id = o.customer_company
      LEFT JOIN customers direct_customer ON direct_customer.id = op2.customer
      LEFT JOIN employees customer_employee ON customer_employee.id = direct_customer.manager
      LEFT JOIN customer_companies direct_company ON direct_company.id = op2.customer_company
      LEFT JOIN employees company_employee ON company_employee.id = direct_company.manager
      WHERE op2.id = payment_id
    ) source
   WHERE op.id = source.id;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_sync_order_payment_access ON order_payments;
CREATE TRIGGER symbolika_sync_order_payment_access
AFTER INSERT OR UPDATE OF "order", customer, customer_company ON order_payments
FOR EACH ROW EXECUTE FUNCTION sync_order_payment_access_trigger();

CREATE OR REPLACE FUNCTION symbolika_validate_payment_allocation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  payment_row order_payments%ROWTYPE;
  target_customer integer;
  target_company integer;
  operation_direction text;
  operation_status text;
  allocated_total numeric(14,2);
  target_due numeric(14,2);
BEGIN
  NEW.amount := round(COALESCE(NEW.amount, 0), 2);
  IF NEW.amount <= 0 THEN RAISE EXCEPTION 'Сумма распределения должна быть больше нуля'; END IF;
  IF num_nonnulls(NEW."order", NEW.customer_operation) <> 1 THEN
    RAISE EXCEPTION 'Распределение должно ссылаться на один заказ или одну клиентскую операцию';
  END IF;

  SELECT * INTO payment_row FROM order_payments WHERE id = NEW.payment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Платеж для распределения не найден'; END IF;

  SELECT COALESCE(sum(pa.amount), 0)
    INTO allocated_total
    FROM payment_allocations pa
   WHERE pa.payment = NEW.payment
     AND pa.id IS DISTINCT FROM NEW.id;
  IF allocated_total + NEW.amount > payment_row.amount THEN
    RAISE EXCEPTION 'Распределено больше суммы платежа';
  END IF;

  IF NEW."order" IS NOT NULL THEN
    SELECT o.customer, o.customer_company
      INTO target_customer, target_company
    FROM orders o WHERE o.id = NEW."order";
  ELSE
    SELECT co.customer, co.customer_company, co.direction, co.status,
           GREATEST(COALESCE(co.payment_due, co.amount), 0)
             + COALESCE((SELECT pa.amount FROM payment_allocations pa WHERE pa.id = NEW.id), 0)
      INTO target_customer, target_company, operation_direction, operation_status, target_due
      FROM customer_operations co WHERE co.id = NEW.customer_operation;
    IF operation_status <> 'confirmed' THEN
      RAISE EXCEPTION 'Распределять оплату можно только на подтвержденную клиентскую операцию';
    END IF;
    IF COALESCE(payment_row.payment_direction, 'incoming') = 'incoming'
       AND operation_direction <> 'customer_owes_us' THEN
      RAISE EXCEPTION 'Входящую оплату можно зачесть только в операцию, по которой клиент должен нам';
    END IF;
  END IF;

  IF NEW.customer_operation IS NOT NULL AND NEW.amount > target_due THEN
    RAISE EXCEPTION 'Сумма распределения превышает остаток по основанию';
  END IF;

  IF target_company IS NOT NULL THEN
    IF payment_row.customer_company IS DISTINCT FROM target_company THEN
      RAISE EXCEPTION 'Платеж и основание относятся к разным компаниям';
    END IF;
  ELSIF payment_row.customer_company IS NOT NULL
     OR payment_row.customer IS DISTINCT FROM target_customer THEN
    RAISE EXCEPTION 'Платеж и основание относятся к разным клиентам';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_validate_payment_allocation ON payment_allocations;
CREATE TRIGGER symbolika_validate_payment_allocation
BEFORE INSERT OR UPDATE ON payment_allocations
FOR EACH ROW EXECUTE FUNCTION symbolika_validate_payment_allocation();

CREATE OR REPLACE FUNCTION symbolika_recalc_payment_allocation_totals(payment_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF payment_id IS NULL THEN RETURN; END IF;
  UPDATE order_payments op
     SET allocated_amount = totals.allocated,
         unallocated_amount = GREATEST(COALESCE(op.amount, 0) - totals.allocated, 0)
    FROM (
      SELECT COALESCE(sum(pa.amount), 0)::numeric(10,2) AS allocated
      FROM payment_allocations pa WHERE pa.payment = payment_id
    ) totals
   WHERE op.id = payment_id;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_customer_operation_payment(operation_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF operation_id IS NULL THEN RETURN; END IF;
  UPDATE customer_operations co
     SET allocated_amount = totals.allocated,
         payment_due = GREATEST(COALESCE(co.amount, 0) - totals.allocated, 0)
    FROM (
      SELECT COALESCE(sum(pa.amount), 0)::numeric(14,2) AS allocated
      FROM payment_allocations pa WHERE pa.customer_operation = operation_id
    ) totals
   WHERE co.id = operation_id;
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_allocation_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM symbolika_recalc_payment_allocation_totals(NEW.payment);
    PERFORM recalc_order_payment_totals(NEW."order");
    PERFORM symbolika_recalc_customer_operation_payment(NEW.customer_operation);
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM symbolika_recalc_payment_allocation_totals(OLD.payment);
    PERFORM recalc_order_payment_totals(OLD."order");
    PERFORM symbolika_recalc_customer_operation_payment(OLD.customer_operation);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_payment_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  allocation record;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW."order" IS NOT NULL
       AND COALESCE(NEW.amount, 0) > 0
       AND COALESCE(NEW.allocation_mode, 'to_order') = 'to_order'
       AND NOT EXISTS (SELECT 1 FROM payment_allocations pa WHERE pa.payment = NEW.id) THEN
      INSERT INTO payment_allocations (payment, "order", amount, comment)
      VALUES (NEW.id, NEW."order", NEW.amount, 'Автоматическое распределение');
    END IF;
    PERFORM symbolika_recalc_payment_allocation_totals(NEW.id);
    PERFORM recalc_order_payment_totals(NEW."order");
    FOR allocation IN SELECT customer_operation FROM payment_allocations WHERE payment = NEW.id AND customer_operation IS NOT NULL LOOP
      PERFORM symbolika_recalc_customer_operation_payment(allocation.customer_operation);
    END LOOP;
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM recalc_order_payment_totals(OLD."order");
    FOR allocation IN SELECT customer_operation FROM payment_allocations WHERE payment = OLD.id AND customer_operation IS NOT NULL LOOP
      PERFORM symbolika_recalc_customer_operation_payment(allocation.customer_operation);
    END LOOP;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_refresh_customer_payment_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM symbolika_recalc_customer_operation_balance(OLD.customer);
    PERFORM symbolika_recalc_company_operation_balance(OLD.customer_company);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM symbolika_recalc_customer_operation_balance(NEW.customer);
    PERFORM symbolika_recalc_company_operation_balance(NEW.customer_company);
  END IF;
  PERFORM refresh_customer_reconciliation();
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_refresh_customer_payment_balance ON order_payments;
CREATE TRIGGER symbolika_refresh_customer_payment_balance
AFTER INSERT OR UPDATE OR DELETE ON order_payments
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_customer_payment_balance();

CREATE OR REPLACE FUNCTION symbolika_refresh_customer_order_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM symbolika_recalc_customer_operation_balance(OLD.customer);
    PERFORM symbolika_recalc_company_operation_balance(OLD.customer_company);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM symbolika_recalc_customer_operation_balance(NEW.customer);
    PERFORM symbolika_recalc_company_operation_balance(NEW.customer_company);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_refresh_customer_order_balance ON orders;
CREATE TRIGGER symbolika_refresh_customer_order_balance
AFTER INSERT OR UPDATE OF customer, customer_company, order_sum OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_customer_order_balance();

UPDATE customer_operations co
SET allocated_amount = totals.allocated,
    payment_due = GREATEST(co.amount - totals.allocated, 0)
FROM (
  SELECT co2.id, COALESCE(sum(pa.amount), 0)::numeric(14,2) AS allocated
  FROM customer_operations co2
  LEFT JOIN payment_allocations pa ON pa.customer_operation = co2.id
  GROUP BY co2.id
) totals
WHERE totals.id = co.id;

UPDATE order_payments op
SET allocated_amount = totals.allocated,
    unallocated_amount = GREATEST(op.amount - totals.allocated, 0)
FROM (
  SELECT op2.id, COALESCE(sum(pa.amount), 0)::numeric(10,2) AS allocated
  FROM order_payments op2
  LEFT JOIN payment_allocations pa ON pa.payment = op2.id
  GROUP BY op2.id
) totals
WHERE totals.id = op.id;

DELETE FROM directus_fields
WHERE collection = 'payment_allocations' AND field = 'customer_operation';
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required
) VALUES (
  'payment_allocations', 'customer_operation', 'm2o', 'select-dropdown-m2o',
  '{"template":"{{description}}"}'::json, 'related-values', '{"template":"{{description}}"}'::json,
  false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Клиентская операция'))::json, false
);

DELETE FROM directus_relations
WHERE many_collection = 'payment_allocations' AND many_field = 'customer_operation';
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_deselect_action)
VALUES ('payment_allocations', 'customer_operation', 'customer_operations', 'cascade');

DELETE FROM directus_fields
WHERE collection = 'customer_operations' AND field IN ('allocated_amount', 'payment_due');
INSERT INTO directus_fields (
  collection, field, interface, display, readonly, hidden, sort, width, translations, required
) VALUES
  ('customer_operations','allocated_amount','input',NULL,true,false,12,'half',json_build_array(json_build_object('language','ru-RU','translation','Оплачено'))::json,false),
  ('customer_operations','payment_due','input',NULL,true,false,13,'half',json_build_array(json_build_object('language','ru-RU','translation','Остаток'))::json,false);

UPDATE directus_fields
SET options = '{"choices":[{"text":"Начальный остаток","value":"opening_balance"},{"text":"Покупка на маркетплейсе","value":"marketplace_purchase"},{"text":"Выдача / снятие наличных","value":"cash_withdrawal"},{"text":"Долг перед клиентом","value":"customer_debt"},{"text":"Прочая просьба","value":"other"}]}'::json
WHERE collection = 'customer_operations' AND field = 'operation_type';

UPDATE directus_permissions
SET fields = '*'
WHERE collection IN ('order_payments', 'payment_allocations', 'customer_operations')
  AND policy = '00000000-0000-4000-8000-000000000205';

UPDATE directus_permissions
SET fields = CASE WHEN fields = '*' THEN fields
                  WHEN position('customer_operation' in fields) > 0 THEN fields
                  ELSE fields || ',customer_operation' END,
    permissions = CASE
      WHEN action IN ('read','update') THEN '{"_or":[{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"customer_operation":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json
      ELSE permissions END
WHERE collection = 'payment_allocations'
  AND policy IN ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202');

UPDATE directus_permissions
SET fields = CASE WHEN fields = '*' THEN fields
                  WHEN position('allocated_amount' in fields) > 0 THEN fields
                  ELSE fields || ',allocated_amount,payment_due' END
WHERE collection = 'customer_operations';

UPDATE directus_permissions
SET validation = '{"_or":[{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"customer":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"customer_company":{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}}]}'::json
WHERE collection = 'order_payments'
  AND action = 'create'
  AND policy IN ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202');

UPDATE directus_permissions
SET validation = '{"payment":{"access_manager_user":{"_eq":"$CURRENT_USER"}}}'::json
WHERE collection = 'payment_allocations'
  AND action = 'create'
  AND policy IN ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202');

CREATE OR REPLACE FUNCTION refresh_customer_reconciliation()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM customer_reconciliation;
  DELETE FROM customer_reconciliation_items;

  INSERT INTO customer_reconciliation (
    id, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name,
    order_sum, paid_amount, payment_due, overpayment,
    customer_debt_to_us, our_debt_to_customer, reconciliation_result,
    entry_type, client_operation, operation_type, direction, description
  )
  SELECT
    o.id, o.id, o.order_number, o.date, o.deadline,
    o.customer, c.name, o.customer_company, cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), 'Без заказчика'),
    o.manager_employee, e.full_name, o.order_status, os.name,
    COALESCE(o.order_sum, 0), COALESCE(o.paid_amount, 0), COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    GREATEST(COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    GREATEST(-COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    CASE WHEN COALESCE(o.payment_due, 0) > 0 THEN 'Клиент должен'
         WHEN COALESCE(o.payment_due, 0) < 0 THEN 'Мы должны'
         ELSE 'Расчет закрыт' END,
    'order', NULL, NULL, NULL, NULL
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status;

  INSERT INTO customer_reconciliation (
    id, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name,
    order_sum, paid_amount, payment_due, overpayment,
    customer_debt_to_us, our_debt_to_customer, reconciliation_result,
    entry_type, client_operation, operation_type, direction, description
  )
  SELECT
    -co.id, NULL, 'ОП-' || lpad(co.id::text, 5, '0'), co.operation_date, NULL,
    co.customer, c.name, co.customer_company, cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), 'Без заказчика'),
    co.manager_employee, e.full_name, NULL,
    CASE co.status WHEN 'confirmed' THEN 'Подтверждена' WHEN 'draft' THEN 'Черновик' ELSE 'Отменена' END,
    CASE WHEN co.direction = 'customer_owes_us' THEN co.amount ELSE 0 END,
    COALESCE(co.allocated_amount, 0),
    CASE WHEN co.direction = 'customer_owes_us' THEN COALESCE(co.payment_due, co.amount)
         ELSE -COALESCE(co.payment_due, co.amount) END,
    CASE WHEN co.direction = 'we_owe_customer' THEN COALESCE(co.payment_due, co.amount)
         ELSE GREATEST(COALESCE(co.allocated_amount, 0) - co.amount, 0) END,
    CASE WHEN co.direction = 'customer_owes_us' THEN COALESCE(co.payment_due, co.amount) ELSE 0 END,
    CASE WHEN co.direction = 'we_owe_customer' THEN COALESCE(co.payment_due, co.amount) ELSE 0 END,
    CASE WHEN COALESCE(co.payment_due, co.amount) = 0 THEN 'Расчет закрыт'
         WHEN co.direction = 'customer_owes_us' THEN 'Клиент должен'
         ELSE 'Мы должны' END,
    'operation', co.id, co.operation_type, co.direction, co.description
  FROM customer_operations co
  LEFT JOIN customers c ON c.id = co.customer
  LEFT JOIN customer_companies cc ON cc.id = co.customer_company
  LEFT JOIN employees e ON e.id = co.manager_employee
  WHERE co.status = 'confirmed';

  INSERT INTO customer_reconciliation_items (
    id, order_item, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name, production_status_name,
    product_name, quantity, price_per_unit, item_sum,
    order_sum, paid_amount, payment_due, overpayment, reconciliation_result
  )
  SELECT
    oi.id, oi.id, o.id, o.order_number, o.date, COALESCE(oi.deadline, o.deadline),
    o.customer, c.name, o.customer_company, cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), 'Без заказчика'),
    o.manager_employee, e.full_name, o.order_status, os.name, ps.name,
    oi.product_name, COALESCE(oi.quantity, 0), COALESCE(oi.price_per_unit, 0),
    COALESCE(oi.order_sum, COALESCE(oi.quantity, 0) * COALESCE(oi.price_per_unit, 0)),
    COALESCE(o.order_sum, 0), COALESCE(o.paid_amount, 0), COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    CASE WHEN COALESCE(o.payment_due, 0) > 0 THEN 'Клиент должен'
         WHEN COALESCE(o.payment_due, 0) < 0 THEN 'Мы должны'
         ELSE 'Расчет закрыт' END
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  LEFT JOIN production_statuses ps ON ps.id = oi.production_status;
END;
$$;

SELECT symbolika_recalc_customer_operation_balance(id) FROM customers;
SELECT symbolika_recalc_company_operation_balance(id) FROM customer_companies;
SELECT refresh_customer_reconciliation();

COMMIT;

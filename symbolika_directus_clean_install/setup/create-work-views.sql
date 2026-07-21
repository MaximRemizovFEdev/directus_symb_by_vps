-- Symbolika work views for focused Directus collections.
-- Run from repository root:
-- docker exec -i symbolika-db psql -U directus -d directus < symbolika_directus_clean_install/setup/create-work-views.sql

BEGIN;

DROP TRIGGER IF EXISTS production_work_update ON production_work;
DROP TRIGGER IF EXISTS screen_printing_work_update ON screen_printing_work;
DROP TRIGGER IF EXISTS office_issue_push_update ON office_issue;
DROP TRIGGER IF EXISTS office_issue_archive_push_update ON office_issue_archive;
DROP TRIGGER IF EXISTS production_work_push_update ON production_work;
DROP TRIGGER IF EXISTS screen_printing_work_push_update ON screen_printing_work;
DROP TRIGGER IF EXISTS contractor_work_push_update ON contractor_work;
DROP TRIGGER IF EXISTS symbolika_sync_office_issue ON orders;
DROP TRIGGER IF EXISTS symbolika_sync_work_order ON orders;
DROP TRIGGER IF EXISTS symbolika_sync_work_item ON orders_items;
DROP TRIGGER IF EXISTS symbolika_sync_office_issue_item ON orders_items;
DROP TRIGGER IF EXISTS office_issue_item_push_update ON office_issue_items;
DROP TRIGGER IF EXISTS office_items_in_office_push_update ON office_items_in_office;
DROP TRIGGER IF EXISTS symbolika_sync_work_contractor ON contractors;
DROP TRIGGER IF EXISTS symbolika_apply_category_contractors ON orders_items;
DROP TRIGGER IF EXISTS symbolika_sync_work_routing_rule ON product_routing_rules;
DROP TRIGGER IF EXISTS symbolika_sync_contractor_work_user ON contractors;
DROP TRIGGER IF EXISTS symbolika_sync_order_payment_access ON order_payments;
DROP TRIGGER IF EXISTS symbolika_sync_order_payments_access_for_order ON orders;
DROP TRIGGER IF EXISTS symbolika_recalc_order_payment_on_payment ON order_payments;
DROP TRIGGER IF EXISTS symbolika_recalc_order_payment_on_allocation ON payment_allocations;
DROP TRIGGER IF EXISTS symbolika_recalc_order_payment_on_item ON orders_items;
DROP TRIGGER IF EXISTS symbolika_recalc_order_payment_on_order ON orders;
DROP TRIGGER IF EXISTS symbolika_orders_items_order_link ON orders_items;
DROP TRIGGER IF EXISTS symbolika_order_payments_order_link ON order_payments;
DROP TRIGGER IF EXISTS symbolika_payment_allocations_order_link ON payment_allocations;
DROP TRIGGER IF EXISTS symbolika_office_items_in_office_order_link ON office_items_in_office;
DROP TRIGGER IF EXISTS symbolika_production_work_order_link ON production_work;
DROP TRIGGER IF EXISTS symbolika_screen_printing_work_order_link ON screen_printing_work;
DROP TRIGGER IF EXISTS symbolika_contractor_work_order_link ON contractor_work;
DROP TRIGGER IF EXISTS symbolika_apply_item_status_from_production ON orders_items;
DROP TRIGGER IF EXISTS symbolika_recalc_order_status_from_items ON orders_items;
DROP TRIGGER IF EXISTS symbolika_apply_order_status_to_items ON orders;

DO $$
DECLARE
  obj record;
BEGIN
  FOR obj IN
    SELECT c.relname, c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('office_issue', 'office_issue_items', 'office_issue_archive', 'office_issue_archive_items', 'office_items_in_office', 'production_work', 'screen_printing_work', 'contractor_work')
  LOOP
    IF obj.relkind = 'v' THEN
      EXECUTE format('DROP VIEW %I CASCADE', obj.relname);
    ELSE
      EXECUTE format('DROP TABLE %I CASCADE', obj.relname);
    END IF;
  END LOOP;
END;
$$;

CREATE TABLE IF NOT EXISTS symbolika_push_subscriptions (
  id serial PRIMARY KEY,
  "user" uuid NOT NULL,
  endpoint text NOT NULL UNIQUE,
  subscription jsonb NOT NULL,
  user_agent text,
  last_error text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DO $$
BEGIN
  IF to_regclass('public.customer_company_links') IS NOT NULL THEN
    DELETE FROM customer_company_links
     WHERE customer IS NULL
        OR customer_companies IS NULL;

    IF EXISTS (
      SELECT 1
        FROM information_schema.table_constraints
       WHERE table_schema = 'public'
         AND table_name = 'customer_company_links'
         AND constraint_name = 'customer_company_links_customer_foreign'
    ) THEN
      ALTER TABLE customer_company_links
        DROP CONSTRAINT customer_company_links_customer_foreign;
    END IF;

    IF EXISTS (
      SELECT 1
        FROM information_schema.table_constraints
       WHERE table_schema = 'public'
         AND table_name = 'customer_company_links'
         AND constraint_name = 'customer_company_links_customer_companies_foreign'
    ) THEN
      ALTER TABLE customer_company_links
        DROP CONSTRAINT customer_company_links_customer_companies_foreign;
    END IF;

    ALTER TABLE customer_company_links
      ADD CONSTRAINT customer_company_links_customer_foreign
      FOREIGN KEY (customer) REFERENCES customers(id) ON DELETE CASCADE;

    ALTER TABLE customer_company_links
      ADD CONSTRAINT customer_company_links_customer_companies_foreign
      FOREIGN KEY (customer_companies) REFERENCES customer_companies(id) ON DELETE CASCADE;
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS office_issue (
  id integer PRIMARY KEY,
  order_number character varying(255),
  date date,
  deadline date,
  customer integer,
  customer_name character varying(255),
  customer_phone character varying(255),
  customer_company integer,
  customer_company_name character varying(255),
  manager_employee integer,
  manager_name character varying(255),
  order_status integer,
  order_status_name character varying(255),
  office_status character varying(255),
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2),
  office_payment_due numeric(10,2),
  add_payment numeric(10,2),
  overpayment numeric(10,2),
  payment_type integer,
  payment_comment text
);

CREATE TABLE IF NOT EXISTS office_issue_items (
  id integer PRIMARY KEY,
  office_issue integer,
  product_name character varying(255),
  quantity numeric(10,0),
  office_status character varying(255)
);

CREATE TABLE IF NOT EXISTS office_issue_archive (LIKE office_issue INCLUDING ALL);
CREATE TABLE IF NOT EXISTS office_issue_archive_items (LIKE office_issue_items INCLUDING ALL);

CREATE TABLE IF NOT EXISTS office_items_in_office (
  id integer PRIMARY KEY,
  "order" integer,
  office_issue integer,
  order_number character varying(255),
  customer integer,
  customer_name character varying(255),
  customer_company integer,
  customer_company_name character varying(255),
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  office_status character varying(255)
);

ALTER TABLE office_items_in_office ADD COLUMN IF NOT EXISTS office_issue integer;
ALTER TABLE office_items_in_office ADD COLUMN IF NOT EXISTS customer_name character varying(255);
ALTER TABLE office_items_in_office ADD COLUMN IF NOT EXISTS customer_company_name character varying(255);
ALTER TABLE office_issue ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE office_issue_archive ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE office_items_in_office ADD COLUMN IF NOT EXISTS order_link integer;

ALTER TABLE employees ADD COLUMN IF NOT EXISTS phone character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS access_manager_user uuid;
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS access_shipping_method character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS order_number_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS customer_name_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS customer_company_name_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE payment_allocations ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS application_method integer;
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS detail_mode character varying(255) DEFAULT 'subcategory';
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_product_category integer REFERENCES product_categories(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_product_subcategory integer REFERENCES product_subcategories(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS has_own_view boolean DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS directus_user uuid REFERENCES directus_users(id) ON DELETE SET NULL;
ALTER TABLE product_categories DROP COLUMN IF EXISTS default_contractor_1;
ALTER TABLE product_categories DROP COLUMN IF EXISTS default_contractor_2;

CREATE TABLE IF NOT EXISTS product_application_methods (
  id serial PRIMARY KEY,
  name character varying(255) NOT NULL,
  sort integer,
  is_active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS product_routing_rules (
  id serial PRIMARY KEY,
  name character varying(255),
  product_category integer REFERENCES product_categories(id) ON DELETE CASCADE,
  product_subcategory integer REFERENCES product_subcategories(id) ON DELETE CASCADE,
  application_method integer REFERENCES product_application_methods(id) ON DELETE CASCADE,
  contractor_1 integer REFERENCES contractors(id) ON DELETE SET NULL,
  contractor_2 integer REFERENCES contractors(id) ON DELETE SET NULL,
  priority integer DEFAULT 100,
  is_active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS production_work (
  id integer PRIMARY KEY,
  "order" integer,
  customer integer,
  customer_company integer,
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  technical_task_text text,
  production_comment text,
  url character varying(255),
  production_status integer,
  deadline timestamp without time zone
);

CREATE TABLE IF NOT EXISTS screen_printing_work (
  id integer PRIMARY KEY,
  "order" integer,
  customer integer,
  customer_company integer,
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  technical_task_text text,
  production_comment text,
  url character varying(255),
  production_status integer,
  deadline timestamp without time zone
);

CREATE TABLE IF NOT EXISTS contractor_work (
  id integer PRIMARY KEY,
  order_item integer,
  contractor integer,
  contractor_slot integer,
  contractor_has_own_view boolean,
  access_user uuid,
  "order" integer,
  customer integer,
  customer_company integer,
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  technical_task_text text,
  production_comment text,
  url character varying(255),
  production_status integer,
  deadline timestamp without time zone
);

ALTER TABLE production_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS production_comment text;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS production_comment text;
ALTER TABLE contractor_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE contractor_work ADD COLUMN IF NOT EXISTS production_comment text;

CREATE OR REPLACE FUNCTION set_symbolika_order_link()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.order_link := NEW."order";
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_orders_items_order_link
BEFORE INSERT OR UPDATE OF "order" ON orders_items
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE OR REPLACE FUNCTION apply_category_contractors_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  matched_contractors integer[];
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.product_category IS DISTINCT FROM OLD.product_category
     OR NEW.product_subcategory IS DISTINCT FROM OLD.product_subcategory
     OR NEW.application_method IS DISTINCT FROM OLD.application_method THEN
    SELECT ARRAY[rule_match.contractor_1, rule_match.contractor_2]
      INTO matched_contractors
      FROM (
        SELECT
          r.contractor_1,
          r.contractor_2,
          (
            CASE WHEN r.product_subcategory IS NOT NULL THEN 2 ELSE 0 END +
            CASE WHEN r.application_method IS NOT NULL THEN 2 ELSE 0 END +
            CASE WHEN r.product_category IS NOT NULL THEN 1 ELSE 0 END
          ) AS specificity,
          COALESCE(r.priority, 100) AS priority,
          r.id
        FROM product_routing_rules r
        WHERE COALESCE(r.is_active, true) = true
          AND r.product_category = NEW.product_category
          AND (r.product_subcategory IS NULL OR r.product_subcategory = NEW.product_subcategory)
          AND (r.application_method IS NULL OR r.application_method = NEW.application_method)
          AND (r.contractor_1 IS NOT NULL OR r.contractor_2 IS NOT NULL)
        ORDER BY specificity DESC, priority, id
        LIMIT 1
      ) rule_match;

    IF matched_contractors IS NULL THEN
      SELECT array_agg(id ORDER BY priority, id)
        INTO matched_contractors
        FROM (
          SELECT c.id, 1 AS priority
          FROM contractors c
          WHERE NEW.product_subcategory IS NOT NULL
            AND c.default_product_subcategory = NEW.product_subcategory
          UNION
          SELECT c.id, 2 AS priority
          FROM contractors c
          WHERE NEW.product_category IS NOT NULL
            AND c.default_product_category = NEW.product_category
        ) fallback_matches;
    END IF;

    NEW.contractor_1 := matched_contractors[1];
    NEW.contractor_2 := matched_contractors[2];
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_apply_category_contractors
BEFORE INSERT OR UPDATE OF product_category, product_subcategory, application_method ON orders_items
FOR EACH ROW
EXECUTE FUNCTION apply_category_contractors_trigger();

CREATE OR REPLACE FUNCTION sync_work_routing_rule_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  affected_category integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    affected_category := OLD.product_category;
  ELSE
    affected_category := NEW.product_category;
  END IF;

  UPDATE orders_items
     SET product_category = product_category
   WHERE affected_category IS NULL
      OR product_category = affected_category;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER symbolika_sync_work_routing_rule
AFTER INSERT OR UPDATE OR DELETE ON product_routing_rules
FOR EACH ROW
EXECUTE FUNCTION sync_work_routing_rule_trigger();

CREATE TRIGGER symbolika_order_payments_order_link
BEFORE INSERT OR UPDATE OF "order" ON order_payments
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE TRIGGER symbolika_payment_allocations_order_link
BEFORE INSERT OR UPDATE OF "order" ON payment_allocations
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE TRIGGER symbolika_office_items_in_office_order_link
BEFORE INSERT OR UPDATE OF "order" ON office_items_in_office
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE TRIGGER symbolika_production_work_order_link
BEFORE INSERT OR UPDATE OF "order" ON production_work
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE TRIGGER symbolika_screen_printing_work_order_link
BEFORE INSERT OR UPDATE OF "order" ON screen_printing_work
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE TRIGGER symbolika_contractor_work_order_link
BEFORE INSERT OR UPDATE OF "order" ON contractor_work
FOR EACH ROW
EXECUTE FUNCTION set_symbolika_order_link();

CREATE OR REPLACE FUNCTION sync_office_issue_order(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM office_issue WHERE id = order_id;
  DELETE FROM office_issue_archive WHERE id = order_id;

  INSERT INTO office_issue (
    id, order_number, date, deadline, customer, customer_name, customer_phone,
    customer_company, customer_company_name, manager_employee, manager_name,
    order_status, order_status_name, office_status, order_sum, paid_amount,
    payment_due, office_payment_due, add_payment, overpayment, payment_type,
    payment_comment
  )
  SELECT
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    c.name,
    c.phone,
    o.customer_company,
    cc.name,
    o.manager_employee,
    e.full_name,
    o.order_status,
    os.name,
    o.office_status,
    o.order_sum,
    o.paid_amount,
    o.payment_due,
    o.office_payment_due,
    NULL::numeric(10,2),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    NULL::integer,
    NULL::text
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE o.id = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(o.office_status, 'not_in_office') <> 'issued';

  INSERT INTO office_issue_archive (
    id, order_number, date, deadline, customer, customer_name, customer_phone,
    customer_company, customer_company_name, manager_employee, manager_name,
    order_status, order_status_name, office_status, order_sum, paid_amount,
    payment_due, office_payment_due, add_payment, overpayment, payment_type,
    payment_comment
  )
  SELECT
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    c.name,
    c.phone,
    o.customer_company,
    cc.name,
    o.manager_employee,
    e.full_name,
    o.order_status,
    os.name,
    o.office_status,
    o.order_sum,
    o.paid_amount,
    o.payment_due,
    o.office_payment_due,
    NULL::numeric(10,2),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    NULL::integer,
    NULL::text
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE o.id = order_id
    AND o.shipping_method = 'office_pickup'
    AND o.office_status = 'issued';

  UPDATE office_issue
  SET order_link = id
  WHERE id = order_id;

  UPDATE office_issue_archive
  SET order_link = id
  WHERE id = order_id;
END;
$$;

CREATE OR REPLACE FUNCTION sync_office_issue_items(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM office_issue_items WHERE office_issue = order_id;
  DELETE FROM office_issue_archive_items WHERE office_issue = order_id;

  INSERT INTO office_issue_items (
    id, office_issue, product_name, quantity, office_status
  )
  SELECT
    oi.id,
    oi."order",
    oi.product_name,
    oi.quantity,
    oi.office_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(o.office_status, 'not_in_office') <> 'issued';

  INSERT INTO office_issue_archive_items (
    id, office_issue, product_name, quantity, office_status
  )
  SELECT
    oi.id,
    oi."order",
    oi.product_name,
    oi.quantity,
    oi.office_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND o.office_status = 'issued';
END;
$$;

CREATE OR REPLACE FUNCTION sync_office_items_in_office(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM office_items_in_office WHERE id = item_id;

  INSERT INTO office_items_in_office (
    id, "order", office_issue, order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
    product_name, quantity, office_status
  )
  SELECT
    oi.id,
    oi."order",
    o.id,
    o.order_number,
    o.customer,
    c.name,
    o.customer_company,
    cc.name,
    o.manager_employee,
    oi.product_name,
    oi.quantity,
    oi.office_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  WHERE oi.id = item_id
    AND oi.office_status = 'in_office';
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_office_status(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  items_count integer;
  all_issued boolean;
  all_in_office boolean;
  has_not_in_office boolean;
  next_status character varying(255);
BEGIN
  SELECT COUNT(*) INTO items_count
  FROM orders_items
  WHERE "order" = order_id;

  IF items_count = 0 THEN
    RETURN;
  END IF;

  SELECT
    bool_and(office_status = 'issued'),
    bool_and(office_status IN ('in_office', 'issued')),
    bool_or(COALESCE(office_status, 'not_in_office') = 'not_in_office')
  INTO all_issued, all_in_office, has_not_in_office
  FROM orders_items
  WHERE "order" = order_id;

  IF all_issued THEN
    next_status := 'issued';
  ELSIF has_not_in_office THEN
    next_status := 'not_in_office';
  ELSIF all_in_office THEN
    next_status := 'in_office';
  ELSE
    next_status := 'not_in_office';
  END IF;

  UPDATE orders
     SET office_status = next_status
   WHERE id = order_id
     AND office_status IS DISTINCT FROM next_status;

  PERFORM sync_office_issue_order(order_id);
  PERFORM sync_office_issue_items(order_id);
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_order_status_id(status_name text)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
  SELECT id
  FROM order_statuses
  WHERE name = status_name
  ORDER BY id
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION symbolika_item_status_from_production(status_id integer)
RETURNS character varying
LANGUAGE sql
STABLE
AS $$
  SELECT CASE ps.name
    WHEN U&'\0412 \0440\0430\0431\043e\0442\0435' THEN 'in_work'
    WHEN U&'\0413\043e\0442\043e\0432' THEN 'ready'
    WHEN U&'\041e\0442\043c\0435\043d\0435\043d' THEN 'cancelled'
    WHEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN 'layout_revision'
    ELSE NULL
  END
  FROM production_statuses ps
  WHERE ps.id = status_id
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION symbolika_normalize_item_status(status_value character varying)
RETURNS character varying
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE status_value
    WHEN 'waiting_layout' THEN 'new'
    WHEN 'send_to_work' THEN 'in_work'
    WHEN 'sent_to_work' THEN 'in_work'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    ELSE COALESCE(status_value, 'new')
  END
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_order_status_from_items(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  items_count integer;
  next_status_name text;
  next_status_id integer;
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO items_count
  FROM orders_items
  WHERE "order" = order_id;

  IF items_count = 0 THEN
    RETURN;
  END IF;

  WITH normalized AS (
    SELECT symbolika_normalize_item_status(item_status) AS item_status
    FROM orders_items
    WHERE "order" = order_id
  )
  SELECT CASE
    WHEN bool_and(item_status = 'cancelled') THEN U&'\041e\0442\043c\0435\043d\0435\043d'
    WHEN bool_and(item_status = 'delivered') THEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
    WHEN bool_and(item_status = 'ready') THEN U&'\0413\043e\0442\043e\0432'
    WHEN bool_or(item_status = 'layout_revision') THEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
    WHEN bool_or(item_status = 'in_work') THEN U&'\0412 \0440\0430\0431\043e\0442\0435'
    WHEN bool_or(item_status = 'approval') THEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
    ELSE U&'\041d\043e\0432\044b\0439'
  END
  INTO next_status_name
  FROM normalized;

  next_status_id := symbolika_order_status_id(next_status_name);

  IF next_status_id IS NOT NULL THEN
    UPDATE orders
       SET order_status = next_status_id
     WHERE id = order_id
       AND order_status IS DISTINCT FROM next_status_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_item_status_from_production_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_item_status character varying;
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.production_status IS DISTINCT FROM OLD.production_status THEN
    next_item_status := symbolika_item_status_from_production(NEW.production_status);
  ELSE
    next_item_status := NULL;
  END IF;

  IF next_item_status IS NOT NULL THEN
    NEW.item_status := next_item_status;
  ELSE
    NEW.item_status := symbolika_normalize_item_status(NEW.item_status);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_order_status_from_items_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM symbolika_recalc_order_status_from_items(OLD."order");
    RETURN OLD;
  END IF;

  PERFORM symbolika_recalc_order_status_from_items(NEW."order");

  IF TG_OP = 'UPDATE' AND OLD."order" IS DISTINCT FROM NEW."order" THEN
    PERFORM symbolika_recalc_order_status_from_items(OLD."order");
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_order_status_to_items_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  status_name text;
  next_item_status character varying;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT name INTO status_name
  FROM order_statuses
  WHERE id = NEW.order_status;

  next_item_status := CASE status_name
    WHEN U&'\041d\043e\0432\044b\0439' THEN 'new'
    WHEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435' THEN 'approval'
    WHEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN 'layout_revision'
    WHEN U&'\0412 \0440\0430\0431\043e\0442\0435' THEN 'in_work'
    WHEN U&'\0413\043e\0442\043e\0432' THEN 'ready'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    WHEN U&'\041e\0442\043c\0435\043d\0435\043d' THEN 'cancelled'
    ELSE NULL
  END;

  IF next_item_status IS NOT NULL THEN
    UPDATE orders_items
       SET item_status = next_item_status
     WHERE "order" = NEW.id
       AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM next_item_status;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_office_issue_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  item record;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM office_issue WHERE id = OLD.id;
    DELETE FROM office_issue_archive WHERE id = OLD.id;
    DELETE FROM office_issue_items WHERE office_issue = OLD.id;
    DELETE FROM office_issue_archive_items WHERE office_issue = OLD.id;
    DELETE FROM office_items_in_office WHERE "order" = OLD.id;
    RETURN OLD;
  END IF;

  PERFORM sync_office_issue_order(NEW.id);
  PERFORM sync_office_issue_items(NEW.id);

  FOR item IN SELECT id FROM orders_items WHERE "order" = NEW.id LOOP
    PERFORM sync_office_items_in_office(item.id);
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_office_issue_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM office_issue_items WHERE id = OLD.id;
    DELETE FROM office_issue_archive_items WHERE id = OLD.id;
    DELETE FROM office_items_in_office WHERE id = OLD.id;
    PERFORM recalc_order_office_status(OLD."order");
    RETURN OLD;
  END IF;

  PERFORM sync_office_issue_items(NEW."order");
  PERFORM sync_office_items_in_office(NEW.id);
  PERFORM recalc_order_office_status(NEW."order");
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION push_office_item_status_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  order_id integer;
BEGIN
  UPDATE orders_items
     SET office_status = NEW.office_status
   WHERE id = NEW.id
     AND office_status IS DISTINCT FROM NEW.office_status
   RETURNING "order" INTO order_id;

  IF order_id IS NULL THEN
    SELECT "order" INTO order_id
    FROM orders_items
    WHERE id = NEW.id;
  END IF;

  IF order_id IS NOT NULL THEN
    PERFORM recalc_order_office_status(order_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION push_office_issue_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE orders
     SET office_status = NEW.office_status
   WHERE id = NEW.id
     AND office_status IS DISTINCT FROM NEW.office_status;

  IF NEW.office_status IN ('in_office', 'issued', 'not_in_office') THEN
    UPDATE orders_items
       SET office_status = NEW.office_status
     WHERE "order" = NEW.id
       AND office_status IS DISTINCT FROM NEW.office_status;
  END IF;

  IF COALESCE(NEW.add_payment, 0) > 0 THEN
    INSERT INTO order_payments (
      "order", customer, customer_company, amount, payment_date, payment_type,
      payment_direction, allocation_mode, comment
    )
    SELECT
      o.id,
      o.customer,
      o.customer_company,
      NEW.add_payment,
      CURRENT_DATE,
      NEW.payment_type,
      'incoming',
      'to_order',
      NEW.payment_comment
    FROM orders o
    WHERE o.id = NEW.id;
  END IF;

  UPDATE orders o
     SET paid_amount = totals.paid_amount,
         payment_due = COALESCE(o.order_sum, 0) - totals.paid_amount,
         office_payment_due = CASE
           WHEN o.payment_on_receipt THEN COALESCE(o.order_sum, 0) - totals.paid_amount
           ELSE 0
         END
    FROM (
      SELECT COALESCE(SUM(pa.amount), 0)::numeric(10,2) AS paid_amount
      FROM payment_allocations pa
      WHERE pa."order" = NEW.id
    ) totals
   WHERE o.id = NEW.id;

  PERFORM sync_office_issue_order(NEW.id);
  PERFORM sync_office_issue_items(NEW.id);

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_work_item(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM production_work WHERE id = item_id;
  DELETE FROM screen_printing_work WHERE id = item_id;
  DELETE FROM contractor_work WHERE order_item = item_id;

  INSERT INTO production_work (
    id, "order", customer, customer_company, manager_employee,
    product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
  )
  SELECT
    oi.id, oi."order", o.customer, o.customer_company, o.manager_employee,
    oi.product_name, oi.quantity, oi.technical_task_text, oi.production_comment, oi.url, oi.production_status, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (c1.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%' OR c2.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%');

  INSERT INTO screen_printing_work (
    id, "order", customer, customer_company, manager_employee,
    product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
  )
  SELECT
    oi.id, oi."order", o.customer, o.customer_company, o.manager_employee,
    oi.product_name, oi.quantity, oi.technical_task_text, oi.production_comment, oi.url, oi.production_status, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%' OR c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%');

  INSERT INTO contractor_work (
    id, order_item, contractor, contractor_slot, contractor_has_own_view, access_user,
    "order", customer, customer_company, manager_employee,
    product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
  )
  SELECT
    oi.id * 10 + contractor_slots.slot,
    oi.id,
    contractor_slots.contractor_id,
    contractor_slots.slot,
    c.has_own_view,
    c.directus_user,
    oi."order",
    o.customer,
    o.customer_company,
    o.manager_employee,
    oi.product_name,
    oi.quantity,
    oi.technical_task_text,
    oi.production_comment,
    oi.url,
    oi.production_status,
    oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  CROSS JOIN LATERAL (
    VALUES (1, oi.contractor_1), (2, oi.contractor_2)
  ) AS contractor_slots(slot, contractor_id)
  JOIN contractors c ON c.id = contractor_slots.contractor_id
  WHERE oi.id = item_id
    AND contractor_slots.contractor_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION sync_work_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM production_work WHERE id = OLD.id;
    DELETE FROM screen_printing_work WHERE id = OLD.id;
    DELETE FROM contractor_work WHERE order_item = OLD.id;
    RETURN OLD;
  END IF;

  PERFORM sync_work_item(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_work_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  item record;
BEGIN
  FOR item IN SELECT id FROM orders_items WHERE "order" = NEW.id LOOP
    PERFORM sync_work_item(item.id);
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_work_contractor_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  item record;
BEGIN
  FOR item IN
    SELECT id FROM orders_items
    WHERE contractor_1 = NEW.id OR contractor_2 = NEW.id
  LOOP
    PERFORM sync_work_item(item.id);
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_contractor_work_user_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE contractor_work
     SET contractor_has_own_view = NEW.has_own_view,
         access_user = NEW.directus_user
   WHERE contractor = NEW.id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION push_work_status_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'contractor_work' THEN
    UPDATE orders_items
       SET production_status = NEW.production_status,
           production_comment = NEW.production_comment
     WHERE id = NEW.order_item
       AND (production_status IS DISTINCT FROM NEW.production_status
            OR production_comment IS DISTINCT FROM NEW.production_comment);
  ELSE
    UPDATE orders_items
       SET production_status = NEW.production_status,
           production_comment = NEW.production_comment
     WHERE id = NEW.id
       AND (production_status IS DISTINCT FROM NEW.production_status
            OR production_comment IS DISTINCT FROM NEW.production_comment);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_order_payment_access(payment_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE order_payments op
     SET access_manager_user = e.directus_user,
         access_shipping_method = o.shipping_method,
         order_number_display = o.order_number,
         customer_name_display = c.name,
         customer_company_name_display = cc.name
    FROM orders o
    LEFT JOIN employees e ON e.id = o.manager_employee
    LEFT JOIN customers c ON c.id = o.customer
    LEFT JOIN customer_companies cc ON cc.id = o.customer_company
   WHERE op.id = payment_id
     AND op."order" = o.id;
END;
$$;

CREATE OR REPLACE FUNCTION sync_order_payment_access_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM sync_order_payment_access(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_order_payments_access_for_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  payment record;
BEGIN
  FOR payment IN
    SELECT id FROM order_payments WHERE "order" = NEW.id
  LOOP
    PERFORM sync_order_payment_access(payment.id);
  END LOOP;

  RETURN NEW;
END;
$$;

UPDATE order_payments op
   SET access_manager_user = e.directus_user,
       access_shipping_method = o.shipping_method,
       order_number_display = o.order_number,
       customer_name_display = c.name,
       customer_company_name_display = cc.name
  FROM orders o
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
 WHERE op."order" = o.id;

CREATE TRIGGER office_issue_push_update
AFTER UPDATE OF office_status, add_payment, payment_type, payment_comment ON office_issue
FOR EACH ROW
EXECUTE FUNCTION push_office_issue_update();

CREATE TRIGGER office_issue_item_push_update
AFTER UPDATE OF office_status ON office_issue_items
FOR EACH ROW
EXECUTE FUNCTION push_office_item_status_update();

CREATE TRIGGER office_items_in_office_push_update
AFTER UPDATE OF office_status ON office_items_in_office
FOR EACH ROW
EXECUTE FUNCTION push_office_item_status_update();

CREATE TRIGGER production_work_push_update
AFTER UPDATE OF production_status, production_comment ON production_work
FOR EACH ROW
EXECUTE FUNCTION push_work_status_update();

CREATE TRIGGER screen_printing_work_push_update
AFTER UPDATE OF production_status, production_comment ON screen_printing_work
FOR EACH ROW
EXECUTE FUNCTION push_work_status_update();

CREATE TRIGGER symbolika_sync_office_issue
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_office_issue_trigger();

CREATE TRIGGER symbolika_sync_office_issue_item
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_office_issue_item_trigger();

CREATE TRIGGER symbolika_apply_item_status_from_production
BEFORE INSERT OR UPDATE OF item_status, production_status ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_item_status_from_production_trigger();

CREATE TRIGGER symbolika_recalc_order_status_from_items
AFTER INSERT OR UPDATE OF item_status, production_status, "order" OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_recalc_order_status_from_items_trigger();

CREATE TRIGGER symbolika_apply_order_status_to_items
AFTER INSERT OR UPDATE OF order_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_order_status_to_items_trigger();

CREATE TRIGGER symbolika_sync_work_order
AFTER UPDATE OF customer, customer_company, manager_employee ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_work_order_trigger();

CREATE TRIGGER symbolika_sync_order_payment_access
AFTER INSERT OR UPDATE OF "order" ON order_payments
FOR EACH ROW
EXECUTE FUNCTION sync_order_payment_access_trigger();

CREATE TRIGGER symbolika_sync_order_payments_access_for_order
AFTER UPDATE OF manager_employee, shipping_method ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_order_payments_access_for_order_trigger();

CREATE OR REPLACE FUNCTION recalc_order_payment_totals(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF order_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT pg_try_advisory_xact_lock(hashtext('recalc_order_payment_totals'), order_id) THEN
    RETURN;
  END IF;

  UPDATE order_payments op
     SET allocated_amount = COALESCE(allocated.total, 0),
         unallocated_amount = COALESCE(op.amount, 0) - COALESCE(allocated.total, 0)
    FROM (
      SELECT payment, COALESCE(SUM(amount), 0)::numeric(10,2) AS total
      FROM payment_allocations
      GROUP BY payment
    ) allocated
   WHERE op.id = allocated.payment
     AND op."order" = order_id;

  UPDATE order_payments op
     SET allocated_amount = 0,
         unallocated_amount = COALESCE(op.amount, 0)
   WHERE op."order" = order_id
     AND NOT EXISTS (
       SELECT 1
       FROM payment_allocations pa
       WHERE pa.payment = op.id
     );

  UPDATE orders o
     SET order_sum = COALESCE(item_totals.order_sum, 0),
         paid_amount = COALESCE(payment_totals.paid_amount, 0),
         payment_due = COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0),
         office_payment_due = CASE
           WHEN o.payment_on_receipt THEN COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0)
           ELSE 0
         END
    FROM (
      SELECT COALESCE(SUM(order_sum), 0)::numeric(10,2) AS order_sum
      FROM orders_items
      WHERE "order" = order_id
    ) item_totals,
    (
      SELECT COALESCE(SUM(amount), 0)::numeric(10,2) AS paid_amount
      FROM payment_allocations
      WHERE "order" = order_id
    ) payment_totals
  WHERE o.id = order_id;

  PERFORM sync_office_issue_order(order_id);
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_payment_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW."order" IS NOT NULL
       AND COALESCE(NEW.amount, 0) > 0
       AND COALESCE(NEW.allocation_mode, 'to_order') = 'to_order'
       AND NOT EXISTS (
         SELECT 1
         FROM payment_allocations pa
         WHERE pa.payment = NEW.id
           AND pa."order" = NEW."order"
       ) THEN
      INSERT INTO payment_allocations (payment, "order", amount, comment)
      VALUES (
        NEW.id,
        NEW."order",
        NEW.amount,
        U&'\0410\0432\0442\043e\043c\0430\0442\0438\0447\0435\0441\043a\043e\0435 \0440\0430\0441\043f\0440\0435\0434\0435\043b\0435\043d\0438\0435'
      );
    END IF;

    PERFORM recalc_order_payment_totals(NEW."order");
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM recalc_order_payment_totals(OLD."order");
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_allocation_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM recalc_order_payment_totals(NEW."order");
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM recalc_order_payment_totals(OLD."order");
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM recalc_order_payment_totals(NEW."order");
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM recalc_order_payment_totals(OLD."order");
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION recalc_order_payment_on_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM recalc_order_payment_totals(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_recalc_order_payment_on_payment
AFTER INSERT OR UPDATE OF "order", amount, allocation_mode OR DELETE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION recalc_order_payment_on_payment_trigger();

CREATE TRIGGER symbolika_recalc_order_payment_on_allocation
AFTER INSERT OR UPDATE OR DELETE ON payment_allocations
FOR EACH ROW
EXECUTE FUNCTION recalc_order_payment_on_allocation_trigger();

CREATE TRIGGER symbolika_recalc_order_payment_on_item
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION recalc_order_payment_on_item_trigger();

CREATE TRIGGER symbolika_recalc_order_payment_on_order
AFTER UPDATE OF payment_on_receipt ON orders
FOR EACH ROW
EXECUTE FUNCTION recalc_order_payment_on_order_trigger();

CREATE TRIGGER symbolika_sync_work_item
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_work_item_trigger();

CREATE TRIGGER symbolika_sync_work_contractor
AFTER UPDATE OF name, has_own_view, directus_user, default_product_category, default_product_subcategory ON contractors
FOR EACH ROW
EXECUTE FUNCTION sync_work_contractor_trigger();

CREATE TRIGGER symbolika_sync_contractor_work_user
AFTER UPDATE OF has_own_view, directus_user ON contractors
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_work_user_trigger();

CREATE TRIGGER contractor_work_push_update
AFTER UPDATE OF production_status, production_comment ON contractor_work
FOR EACH ROW
EXECUTE FUNCTION push_work_status_update();

DELETE FROM office_issue;
DELETE FROM office_issue_archive;
INSERT INTO office_issue (
  id, order_number, date, deadline, customer, customer_name, customer_phone,
  customer_company, customer_company_name, manager_employee, manager_name,
  order_status, order_status_name, office_status, order_sum, paid_amount,
  payment_due, office_payment_due, add_payment, overpayment, payment_type,
  payment_comment
)
SELECT
  o.id,
  o.order_number,
  o.date,
  o.deadline,
  o.customer,
  c.name,
  c.phone,
  o.customer_company,
  cc.name,
  o.manager_employee,
  e.full_name,
  o.order_status,
  os.name,
  o.office_status,
  o.order_sum,
  o.paid_amount,
  o.payment_due,
  o.office_payment_due,
  NULL::numeric(10,2),
  GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
  NULL::integer,
  NULL::text
FROM orders o
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN employees e ON e.id = o.manager_employee
LEFT JOIN order_statuses os ON os.id = o.order_status
WHERE o.shipping_method = 'office_pickup'
  AND COALESCE(o.office_status, 'not_in_office') <> 'issued';

INSERT INTO office_issue_archive (
  id, order_number, date, deadline, customer, customer_name, customer_phone,
  customer_company, customer_company_name, manager_employee, manager_name,
  order_status, order_status_name, office_status, order_sum, paid_amount,
  payment_due, office_payment_due, add_payment, overpayment, payment_type,
  payment_comment
)
SELECT
  o.id,
  o.order_number,
  o.date,
  o.deadline,
  o.customer,
  c.name,
  c.phone,
  o.customer_company,
  cc.name,
  o.manager_employee,
  e.full_name,
  o.order_status,
  os.name,
  o.office_status,
  o.order_sum,
  o.paid_amount,
  o.payment_due,
  o.office_payment_due,
  NULL::numeric(10,2),
  GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
  NULL::integer,
  NULL::text
FROM orders o
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN employees e ON e.id = o.manager_employee
LEFT JOIN order_statuses os ON os.id = o.order_status
WHERE o.shipping_method = 'office_pickup'
  AND o.office_status = 'issued';

UPDATE office_issue
SET order_link = id;

UPDATE office_issue_archive
SET order_link = id;

DELETE FROM office_issue_items;
DELETE FROM office_issue_archive_items;
INSERT INTO office_issue_items (
  id, office_issue, product_name, quantity, office_status
)
SELECT
  oi.id,
  oi."order",
  oi.product_name,
  oi.quantity,
  oi.office_status
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
WHERE o.shipping_method = 'office_pickup'
  AND COALESCE(o.office_status, 'not_in_office') <> 'issued';

INSERT INTO office_issue_archive_items (
  id, office_issue, product_name, quantity, office_status
)
SELECT
  oi.id,
  oi."order",
  oi.product_name,
  oi.quantity,
  oi.office_status
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
WHERE o.shipping_method = 'office_pickup'
  AND o.office_status = 'issued';

DELETE FROM office_items_in_office;
INSERT INTO office_items_in_office (
  id, "order", office_issue, order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
  product_name, quantity, office_status
)
SELECT
  oi.id,
  oi."order",
  o.id,
  o.order_number,
  o.customer,
  c.name,
  o.customer_company,
  cc.name,
  o.manager_employee,
  oi.product_name,
  oi.quantity,
  oi.office_status
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
WHERE oi.office_status = 'in_office';

DELETE FROM production_work;
DELETE FROM screen_printing_work;
DELETE FROM contractor_work;
INSERT INTO production_work (
  id, "order", customer, customer_company, manager_employee,
  product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
)
SELECT
  oi.id, oi."order", o.customer, o.customer_company, o.manager_employee,
  oi.product_name, oi.quantity, oi.technical_task_text, oi.production_comment, oi.url, oi.production_status, oi.deadline
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
WHERE c1.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
   OR c2.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%';

INSERT INTO screen_printing_work (
  id, "order", customer, customer_company, manager_employee,
  product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
)
SELECT
  oi.id, oi."order", o.customer, o.customer_company, o.manager_employee,
  oi.product_name, oi.quantity, oi.technical_task_text, oi.production_comment, oi.url, oi.production_status, oi.deadline
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
WHERE c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
   OR c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%';

INSERT INTO contractor_work (
  id, order_item, contractor, contractor_slot, contractor_has_own_view, access_user,
  "order", customer, customer_company, manager_employee,
  product_name, quantity, technical_task_text, production_comment, url, production_status, deadline
)
SELECT
  oi.id * 10 + contractor_slots.slot,
  oi.id,
  contractor_slots.contractor_id,
  contractor_slots.slot,
  c.has_own_view,
  c.directus_user,
  oi."order",
  o.customer,
  o.customer_company,
  o.manager_employee,
  oi.product_name,
  oi.quantity,
  oi.technical_task_text,
  oi.production_comment,
  oi.url,
  oi.production_status,
  oi.deadline
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
CROSS JOIN LATERAL (
  VALUES (1, oi.contractor_1), (2, oi.contractor_2)
) AS contractor_slots(slot, contractor_id)
JOIN contractors c ON c.id = contractor_slots.contractor_id
WHERE contractor_slots.contractor_id IS NOT NULL;

UPDATE orders_items
SET order_link = "order";

UPDATE order_payments
SET order_link = "order";

UPDATE payment_allocations
SET order_link = "order";

UPDATE office_items_in_office
SET order_link = "order";

UPDATE production_work
SET order_link = "order";

UPDATE screen_printing_work
SET order_link = "order";

UPDATE contractor_work
SET order_link = "order";

DELETE FROM directus_permissions
WHERE collection IN ('office_issue', 'office_issue_items', 'office_issue_archive', 'office_issue_archive_items', 'office_items_in_office', 'production_work', 'screen_printing_work', 'contractor_work');

DELETE FROM directus_relations
WHERE many_collection IN ('office_issue', 'office_issue_items', 'office_issue_archive', 'office_issue_archive_items', 'office_items_in_office', 'production_work', 'screen_printing_work', 'contractor_work')
   OR one_collection IN ('office_issue', 'office_issue_items', 'office_issue_archive', 'office_issue_archive_items', 'office_items_in_office', 'production_work', 'screen_printing_work', 'contractor_work');

DELETE FROM directus_fields
WHERE collection IN ('office_issue', 'office_issue_items', 'office_issue_archive', 'office_issue_archive_items', 'office_items_in_office', 'production_work', 'screen_printing_work', 'contractor_work');

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, translations,
  archive_app_filter, accountability, sort, collapse, versioning
) VALUES
  (
    'office_issue', 'storefront',
    'Р—Р°РєР°Р·С‹ СЃРѕ СЃРїРѕСЃРѕР±РѕРј РѕС‚РіСЂСѓР·РєРё "Р’С‹РґР°С‡Р° РІ РѕС„РёСЃРµ".',
    '{{order_number}}', false, false,
    '[{"language":"ru-RU","translation":"Р’С‹РґР°С‡Р° РІ РѕС„РёСЃРµ"}]'::json,
    true, 'all', 21, 'open', false
  ),
  (
    'office_issue_items', 'list_alt',
    'РЎР»СѓР¶РµР±РЅС‹Р№ СЃРїРёСЃРѕРє РїРѕР·РёС†РёР№ РґР»СЏ РєРѕР»Р»РµРєС†РёРё "Р’С‹РґР°С‡Р° РІ РѕС„РёСЃРµ".',
    '{{product_name}}', true, false,
    '[{"language":"ru-RU","translation":"РџРѕР·РёС†РёРё РІС‹РґР°С‡Рё РІ РѕС„РёСЃРµ"}]'::json,
    true, 'all', 21, 'open', false
  ),
  (
    'office_items_in_office', 'inventory',
    'РџРѕР·РёС†РёРё Р·Р°РєР°Р·РѕРІ, РєРѕС‚РѕСЂС‹Рµ СЃРµР№С‡Р°СЃ РЅР°С…РѕРґСЏС‚СЃСЏ РІ РѕС„РёСЃРµ.',
    '{{product_name}}', false, false,
    '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·С‹ РІ РѕС„РёСЃРµ"}]'::json,
    true, 'all', 22, 'open', false
  ),
  (
    'office_issue_archive', 'archive',
    'Archive of issued office pickup orders.',
    '{{order_number}}', false, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\0440\0445\0438\0432 \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435'))::json,
    true, 'all', 23, 'open', false
  ),
  (
    'office_issue_archive_items', 'list_alt',
    'Archive order items for issued office pickup orders.',
    '{{product_name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \0430\0440\0445\0438\0432\0430 \0432\044b\0434\0430\0447\0438'))::json,
    true, 'all', 23, 'open', false
  ),
  (
    'production_work', 'engineering',
    'РџРѕР·РёС†РёРё Р·Р°РєР°Р·РѕРІ, РіРґРµ РѕРґРёРЅ РёР· РєРѕРЅС‚СЂР°РіРµРЅС‚РѕРІ СЃРІСЏР·Р°РЅ СЃ РїСЂРѕРёР·РІРѕРґСЃС‚РІРѕРј.',
    '{{product_name}}', false, false,
    '[{"language":"ru-RU","translation":"РџСЂРѕРёР·РІРѕРґСЃС‚РІРѕ"}]'::json,
    true, 'all', 24, 'open', false
  ),
  (
    'screen_printing_work', 'format_paint',
    'РџРѕР·РёС†РёРё Р·Р°РєР°Р·РѕРІ, РіРґРµ РѕРґРёРЅ РёР· РєРѕРЅС‚СЂР°РіРµРЅС‚РѕРІ СЃРІСЏР·Р°РЅ СЃ С€РµР»РєРѕРіСЂР°С„РёРµР№.',
    '{{product_name}}', false, false,
    '[{"language":"ru-RU","translation":"РЁРµР»РєРѕРіСЂР°С„РёСЏ"}]'::json,
    true, 'all', 25, 'open', false
  ),
  (
    'product_application_methods', 'format_paint',
    'Application methods used to route order items and later choose technical task templates.',
    '{{name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\0438\0434\044b \043d\0430\043d\0435\0441\0435\043d\0438\044f'))::json,
    true, 'all', 26, 'open', false
  ),
  (
    'product_routing_rules', 'account_tree',
    'Rules that assign contractors to order items by category, subcategory and application method.',
    '{{name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0430\0432\0438\043b\0430 \043c\0430\0440\0448\0440\0443\0442\0438\0437\0430\0446\0438\0438'))::json,
    true, 'all', 27, 'open', false
  ),
  (
    'contractor_work', 'assignment_ind',
    'External contractor work queue filtered by contractor user.',
    '{{product_name}}', false, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0420\0430\0431\043e\0442\0430 \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\0430'))::json,
    true, 'all', 28, 'open', false
  )
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  translations = EXCLUDED.translations,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse;

UPDATE directus_collections
SET hidden = true
WHERE collection IN (
  'employee_positions',
  'employees',
  'contractors',
  'tech',
  'order_item_specs',
  'payment_types',
  'order_statuses',
  'production_statuses',
  'warehouse_items',
  'warehouse_categories',
  'tax_settings',
  'product_categories',
  'product_subcategories',
  'product_application_methods',
  'product_routing_rules',
  'contractor_payments'
);

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('office_issue', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('office_issue', 'office_summary', 'alias,no-data,group', 'group-detail', '{"start":"open"}'::json, NULL, NULL, false, false, 1, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0432\043e\0434\043a\0430'))::json, false, false),
  ('office_issue', 'office_positions', 'alias,no-data,group', 'group-detail', '{"start":"open"}'::json, NULL, NULL, false, false, 2, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \043a \0432\044b\0434\0430\0447\0435'))::json, false, false),
  ('office_issue', 'office_customer', 'alias,no-data,group', 'group-detail', '{"start":"closed"}'::json, NULL, NULL, false, false, 3, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\0438\0435\043d\0442 \0438 \0441\0440\043e\043a\0438'))::json, false, false),
  ('office_issue', 'office_payment', 'alias,no-data,group', 'group-detail', '{"start":"closed"}'::json, NULL, NULL, false, false, 4, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\0430'))::json, false, false),
  ('office_issue', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 19, 'half-right', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('office_issue', 'order_number', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', '[{"language":"ru-RU","translation":"РќРѕРјРµСЂ Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_issue', 'date', NULL, 'datetime', NULL, NULL, NULL, true, false, 3, 'half', '[{"language":"ru-RU","translation":"Р”Р°С‚Р° Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_issue', 'deadline', NULL, 'datetime', NULL, NULL, NULL, true, false, 4, 'half', '[{"language":"ru-RU","translation":"РЎСЂРѕРє"}]'::json, false, true),
  ('office_issue', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 5, 'half', '[{"language":"ru-RU","translation":"РљР»РёРµРЅС‚"}]'::json, false, true),
  ('office_issue', 'customer_name', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', '[{"language":"ru-RU","translation":"РљР»РёРµРЅС‚"}]'::json, false, true),
  ('office_issue', 'customer_phone', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', '[{"language":"ru-RU","translation":"РўРµР»РµС„РѕРЅ РєР»РёРµРЅС‚Р°"}]'::json, false, true),
  ('office_issue', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 7, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('office_issue', 'customer_company_name', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('office_issue', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 8, 'half', '[{"language":"ru-RU","translation":"РњРµРЅРµРґР¶РµСЂ"}]'::json, false, true),
  ('office_issue', 'manager_name', NULL, 'input', NULL, NULL, NULL, true, true, 8, 'half', '[{"language":"ru-RU","translation":"РњРµРЅРµРґР¶РµСЂ"}]'::json, false, true),
  ('office_issue', 'order_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 9, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_issue', 'order_status_name', NULL, 'input', NULL, NULL, NULL, true, false, 9, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_issue', 'office_status', NULL, 'symbolika-autosave-select', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 10, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),
  ('office_issue', 'order_sum', NULL, 'input', NULL, NULL, NULL, true, false, 11, 'half', '[{"language":"ru-RU","translation":"РЎСѓРјРјР° Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_issue', 'paid_amount', NULL, 'input', NULL, NULL, NULL, true, false, 12, 'half', '[{"language":"ru-RU","translation":"РћРїР»Р°С‡РµРЅРѕ"}]'::json, false, true),
  ('office_issue', 'payment_due', NULL, 'input', NULL, NULL, NULL, true, false, 13, 'half', '[{"language":"ru-RU","translation":"РћСЃС‚Р°С‚РѕРє"}]'::json, false, true),
  ('office_issue', 'office_payment_due', NULL, 'input', NULL, NULL, NULL, true, false, 14, 'half', '[{"language":"ru-RU","translation":"Рљ РѕРїР»Р°С‚Рµ РІ РѕС„РёСЃРµ"}]'::json, false, true),
  ('office_issue', 'add_payment', NULL, 'input', NULL, NULL, NULL, false, false, 15, 'half', '[{"language":"ru-RU","translation":"Р”РѕР±Р°РІРёС‚СЊ РѕРїР»Р°С‚Сѓ"}]'::json, false, true),
  ('office_issue', 'overpayment', NULL, 'input', NULL, NULL, NULL, true, false, 16, 'half', '[{"language":"ru-RU","translation":"РџРµСЂРµРїР»Р°С‚Р° / Рє РІРѕР·РІСЂР°С‚Сѓ"}]'::json, false, true),
  ('office_issue', 'payment_type', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 17, 'half', '[{"language":"ru-RU","translation":"РўРёРї РѕРїР»Р°С‚С‹"}]'::json, false, true),
  ('office_issue', 'payment_comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 18, 'full', '[{"language":"ru-RU","translation":"РљРѕРјРјРµРЅС‚Р°СЂРёР№ Рє РѕРїР»Р°С‚Рµ"}]'::json, false, true),
  ('office_issue', 'order_items', 'o2m', 'list-o2m', '{"layout":"table","tableSpacing":"compact","fields":["product_name","quantity","office_status"],"enableCreate":false,"enableSelect":false}'::json, NULL, NULL, false, false, 19, 'full', '[{"language":"ru-RU","translation":"РџРѕР·РёС†РёРё Р·Р°РєР°Р·Р°"}]'::json, false, true),

  ('office_issue_items', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('office_issue_items', 'office_issue', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, true, 2, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·"}]'::json, false, true),
  ('office_issue_items', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', '[{"language":"ru-RU","translation":"РќР°РёРјРµРЅРѕРІР°РЅРёРµ"}]'::json, false, true),
  ('office_issue_items', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', '[{"language":"ru-RU","translation":"РљРѕР»РёС‡РµСЃС‚РІРѕ"}]'::json, false, true),
  ('office_issue_items', 'office_status', NULL, 'symbolika-autosave-select', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office","icon":"location_off"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office","icon":"done"},{"text":"Р’С‹РґР°РЅ","value":"issued","icon":"done_all"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 5, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),

  ('office_items_in_office', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('office_items_in_office', 'order_link', NULL, 'input', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('office_items_in_office', 'order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, true, 2, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·"}]'::json, false, true),
  ('office_items_in_office', 'order_number', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', '[{"language":"ru-RU","translation":"РќРѕРјРµСЂ Р·Р°РєР°Р·Р°"}]'::json, false, true),
  ('office_items_in_office', 'office_issue', 'm2o', 'symbolika-office-issue-link', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, false, 3, 'half', '[{"language":"ru-RU","translation":"РџРµСЂРµР№С‚Рё РІ Р·Р°РєР°Р·"}]'::json, false, true),
  ('office_items_in_office', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 4, 'half', '[{"language":"ru-RU","translation":"РљР»РёРµРЅС‚"}]'::json, false, true),
  ('office_items_in_office', 'customer_name', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', '[{"language":"ru-RU","translation":"РљР»РёРµРЅС‚"}]'::json, false, true),
  ('office_items_in_office', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 5, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('office_items_in_office', 'customer_company_name', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('office_items_in_office', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 6, 'half', '[{"language":"ru-RU","translation":"РњРµРЅРµРґР¶РµСЂ"}]'::json, false, true),
  ('office_items_in_office', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', '[{"language":"ru-RU","translation":"РќР°РёРјРµРЅРѕРІР°РЅРёРµ"}]'::json, false, true),
  ('office_items_in_office', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 8, 'half', '[{"language":"ru-RU","translation":"РљРѕР»РёС‡РµСЃС‚РІРѕ"}]'::json, false, true),
  ('office_items_in_office', 'office_status', NULL, 'symbolika-autosave-select', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office","icon":"location_off"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office","icon":"done"},{"text":"Р’С‹РґР°РЅ","value":"issued","icon":"done_all"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 9, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),

  ('production_work', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('production_work', 'order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, false, 2, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·"}]'::json, false, true),
  ('production_work', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('production_work', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}} {{phone}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 3, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·С‡РёРє"}]'::json, false, true),
  ('production_work', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 4, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('production_work', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 5, 'half', '[{"language":"ru-RU","translation":"РњРµРЅРµРґР¶РµСЂ"}]'::json, false, true),
  ('production_work', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', '[{"language":"ru-RU","translation":"РќР°РёРјРµРЅРѕРІР°РЅРёРµ РїРѕР·РёС†РёРё"}]'::json, false, true),
  ('production_work', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', '[{"language":"ru-RU","translation":"РљРѕР»РёС‡РµСЃС‚РІРѕ"}]'::json, false, true),
  ('production_work', 'deadline', NULL, 'datetime', NULL, NULL, NULL, true, false, 8, 'half', '[{"language":"ru-RU","translation":"РЎСЂРѕРє РїРѕР·РёС†РёРё"}]'::json, false, true),
  ('production_work', 'technical_task_text', NULL, 'input-multiline', NULL, NULL, NULL, true, false, 9, 'full', '[{"language":"ru-RU","translation":"РўР—"}]'::json, false, true),
  ('production_work', 'production_comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 10, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'))::json, false, true),
  ('production_work', 'url', NULL, 'input', '{"iconLeft":"web_traffic"}'::json, NULL, NULL, true, false, 11, 'full', '[{"language":"ru-RU","translation":"РЎСЃС‹Р»РєР° РЅР° РјР°РєРµС‚"}]'::json, false, true),
  ('production_work', 'production_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 12, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РїСЂРѕРёР·РІРѕРґСЃС‚РІР°"}]'::json, false, true),

  ('screen_printing_work', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('screen_printing_work', 'order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, false, 2, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·"}]'::json, false, true),
  ('screen_printing_work', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('screen_printing_work', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}} {{phone}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 3, 'half', '[{"language":"ru-RU","translation":"Р—Р°РєР°Р·С‡РёРє"}]'::json, false, true),
  ('screen_printing_work', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 4, 'half', '[{"language":"ru-RU","translation":"РљРѕРјРїР°РЅРёСЏ"}]'::json, false, true),
  ('screen_printing_work', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 5, 'half', '[{"language":"ru-RU","translation":"РњРµРЅРµРґР¶РµСЂ"}]'::json, false, true),
  ('screen_printing_work', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', '[{"language":"ru-RU","translation":"РќР°РёРјРµРЅРѕРІР°РЅРёРµ РїРѕР·РёС†РёРё"}]'::json, false, true),
  ('screen_printing_work', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', '[{"language":"ru-RU","translation":"РљРѕР»РёС‡РµСЃС‚РІРѕ"}]'::json, false, true),
  ('screen_printing_work', 'deadline', NULL, 'datetime', NULL, NULL, NULL, true, false, 8, 'half', '[{"language":"ru-RU","translation":"РЎСЂРѕРє РїРѕР·РёС†РёРё"}]'::json, false, true),
  ('screen_printing_work', 'technical_task_text', NULL, 'input-multiline', NULL, NULL, NULL, true, false, 9, 'full', '[{"language":"ru-RU","translation":"РўР—"}]'::json, false, true),
  ('screen_printing_work', 'production_comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 10, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'))::json, false, true),
  ('screen_printing_work', 'url', NULL, 'input', '{"iconLeft":"web_traffic"}'::json, NULL, NULL, true, false, 11, 'full', '[{"language":"ru-RU","translation":"РЎСЃС‹Р»РєР° РЅР° РјР°РєРµС‚"}]'::json, false, true),
  ('screen_printing_work', 'production_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 12, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РїСЂРѕРёР·РІРѕРґСЃС‚РІР°"}]'::json, false, true),

  ('contractor_work', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('contractor_work', 'order_item', 'm2o', 'select-dropdown-m2o', '{"template":"{{product_name}}"}'::json, 'related-values', '{"template":"{{product_name}}"}'::json, true, true, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\044f'))::json, false, true),
  ('contractor_work', 'contractor', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442'))::json, false, true),
  ('contractor_work', 'contractor_slot', NULL, 'numeric', NULL, NULL, NULL, true, true, 4, 'half', NULL, false, true),
  ('contractor_work', 'contractor_has_own_view', NULL, 'boolean', NULL, NULL, NULL, true, true, 5, 'half', NULL, false, true),
  ('contractor_work', 'access_user', NULL, 'input', NULL, NULL, NULL, true, true, 6, 'half', NULL, false, true),
  ('contractor_work', 'order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437'))::json, false, true),
  ('contractor_work', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('contractor_work', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437\0447\0438\043a'))::json, false, true),
  ('contractor_work', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043f\0430\043d\0438\044f'))::json, false, true),
  ('contractor_work', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\043d\0435\0434\0436\0435\0440'))::json, false, true),
  ('contractor_work', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 12, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'))::json, false, true),
  ('contractor_work', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 13, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'))::json, false, true),
  ('contractor_work', 'deadline', NULL, 'datetime', NULL, NULL, NULL, true, false, 14, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0440\043e\043a'))::json, false, true),
  ('contractor_work', 'production_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 15, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430'))::json, false, true),
  ('contractor_work', 'url', NULL, 'input', '{"iconLeft":"web_traffic"}'::json, NULL, NULL, true, false, 16, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'))::json, false, true),
  ('contractor_work', 'technical_task_text', NULL, 'input-multiline', NULL, NULL, NULL, true, false, 17, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0417'))::json, false, true),
  ('contractor_work', 'production_comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 18, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'))::json, false, true);

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'office_issue_archive',
  field,
  special,
  CASE WHEN field IN ('office_status', 'add_payment', 'payment_type', 'payment_comment') THEN 'input' ELSE interface END,
  CASE WHEN field IN ('office_status', 'add_payment', 'payment_type', 'payment_comment') THEN NULL ELSE options END,
  display,
  display_options,
  true,
  hidden,
  sort,
  width,
  translations,
  required,
  searchable
FROM directus_fields
WHERE collection = 'office_issue';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'office_issue_archive_items',
  field,
  special,
  'input',
  NULL,
  display,
  display_options,
  true,
  hidden,
  sort,
  width,
  translations,
  required,
  searchable
FROM directus_fields
WHERE collection = 'office_issue_items';

UPDATE directus_fields
SET interface = 'select-dropdown-m2o',
    options = '{"template":"{{order_number}}"}'::json,
    display = 'related-values',
    display_options = '{"template":"{{order_number}}"}'::json
WHERE collection = 'office_issue_archive_items'
  AND field = 'office_issue';

UPDATE directus_fields
SET hidden = true
WHERE collection = 'office_issue_archive'
  AND field IN ('add_payment', 'payment_type', 'payment_comment');

DELETE FROM directus_fields
WHERE collection = 'employees'
  AND field = 'phone';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES (
  'employees', 'phone', NULL, 'input', NULL, NULL, NULL,
  false, false, 4, 'full',
  '[{"language":"ru-RU","translation":"РўРµР»РµС„РѕРЅ"}]'::json,
  false, true
);

UPDATE directus_fields
SET translations = json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0435\043b\0435\0444\043e\043d'))::json
WHERE collection = 'employees'
  AND field = 'phone';

DELETE FROM directus_fields
WHERE (collection = 'product_categories' AND field IN ('default_contractor_1', 'default_contractor_2'))
   OR (collection = 'contractors' AND field IN ('has_own_view', 'directus_user', 'default_product_category', 'default_product_subcategory'))
   OR (collection = 'product_categories' AND field = 'detail_mode')
   OR (collection = 'product_application_methods' AND field IN ('id', 'name', 'sort', 'is_active'))
   OR (collection = 'product_routing_rules' AND field IN ('id', 'name', 'product_category', 'product_subcategory', 'application_method', 'contractor_1', 'contractor_2', 'priority', 'is_active'));

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  (
    'contractors', 'has_own_view', 'cast-boolean', 'boolean',
    NULL, NULL, NULL,
    false, false, 7, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0432\043e\0435 \043f\0440\0435\0434\0441\0442\0430\0432\043b\0435\043d\0438\0435'))::json,
    false, true
  ),
  (
    'contractors', 'directus_user', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{first_name}} {{last_name}} {{email}}"}'::json, 'related-values', '{"template":"{{first_name}} {{last_name}} {{email}}"}'::json,
    false, false, 8, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\043b\044c\0437\043e\0432\0430\0442\0435\043b\044c Directus'))::json,
    false, true
  ),
  (
    'contractors', 'default_product_category', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json,
    false, false, 9, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f \043f\043e \0443\043c\043e\043b\0447\0430\043d\0438\044e'))::json,
    false, true
  ),
  (
    'contractors', 'default_product_subcategory', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json,
    false, false, 10, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f \043f\043e \0443\043c\043e\043b\0447\0430\043d\0438\044e'))::json,
    false, true
  ),
  (
    'product_categories', 'detail_mode', NULL, 'select-dropdown',
    json_build_object('choices', json_build_array(
      json_build_object('text', U&'\0411\0435\0437 \0434\0435\0442\0430\043b\0438\0437\0430\0446\0438\0438', 'value', 'none'),
      json_build_object('text', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f', 'value', 'subcategory'),
      json_build_object('text', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f', 'value', 'application_method')
    ))::json,
    'labels',
    json_build_object('choices', json_build_array(
      json_build_object('text', U&'\0411\0435\0437 \0434\0435\0442\0430\043b\0438\0437\0430\0446\0438\0438', 'value', 'none'),
      json_build_object('text', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f', 'value', 'subcategory'),
      json_build_object('text', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f', 'value', 'application_method')
    ))::json,
    false, false, 5, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0438\043f \0434\0435\0442\0430\043b\0438\0437\0430\0446\0438\0438'))::json,
    false, true
  ),
  ('product_application_methods', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('product_application_methods', 'name', NULL, 'input', NULL, NULL, NULL, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0437\0432\0430\043d\0438\0435'))::json, true, true),
  ('product_application_methods', 'sort', NULL, 'input', NULL, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0440\0442\0438\0440\043e\0432\043a\0430'))::json, false, true),
  ('product_application_methods', 'is_active', 'cast-boolean', 'boolean', NULL, NULL, NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\043a\0442\0438\0432\043d\043e'))::json, false, true),
  ('product_routing_rules', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('product_routing_rules', 'name', NULL, 'input', NULL, NULL, NULL, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0437\0432\0430\043d\0438\0435'))::json, false, true),
  ('product_routing_rules', 'product_category', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f'))::json, true, true),
  ('product_routing_rules', 'product_subcategory', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f'))::json, false, true),
  ('product_routing_rules', 'application_method', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f'))::json, false, true),
  ('product_routing_rules', 'contractor_1', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442 1'))::json, false, true),
  ('product_routing_rules', 'contractor_2', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442 2'))::json, false, true),
  ('product_routing_rules', 'priority', NULL, 'input', NULL, NULL, NULL, false, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0438\043e\0440\0438\0442\0435\0442'))::json, false, true),
  ('product_routing_rules', 'is_active', 'cast-boolean', 'boolean', NULL, NULL, NULL, false, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\043a\0442\0438\0432\043d\043e'))::json, false, true)
  ;

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES
  ('office_issue', 'manager_employee', 'employees', NULL, 'nullify'),
  ('office_issue', 'customer', 'customers', NULL, 'nullify'),
  ('office_issue', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('office_issue', 'order_status', 'order_statuses', NULL, 'nullify'),
  ('office_issue', 'payment_type', 'payment_types', NULL, 'nullify'),
  ('office_issue_items', 'office_issue', 'office_issue', 'order_items', 'nullify'),
  ('office_issue_archive', 'manager_employee', 'employees', NULL, 'nullify'),
  ('office_issue_archive', 'customer', 'customers', NULL, 'nullify'),
  ('office_issue_archive', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('office_issue_archive', 'order_status', 'order_statuses', NULL, 'nullify'),
  ('office_issue_archive', 'payment_type', 'payment_types', NULL, 'nullify'),
  ('office_issue_archive_items', 'office_issue', 'office_issue_archive', 'order_items', 'nullify'),
  ('office_items_in_office', 'order', 'orders', NULL, 'nullify'),
  ('office_items_in_office', 'office_issue', 'office_issue', NULL, 'nullify'),
  ('office_items_in_office', 'customer', 'customers', NULL, 'nullify'),
  ('office_items_in_office', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('office_items_in_office', 'manager_employee', 'employees', NULL, 'nullify'),

  ('production_work', 'order', 'orders', NULL, 'nullify'),
  ('production_work', 'customer', 'customers', NULL, 'nullify'),
  ('production_work', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('production_work', 'manager_employee', 'employees', NULL, 'nullify'),
  ('production_work', 'production_status', 'production_statuses', NULL, 'nullify'),

  ('screen_printing_work', 'order', 'orders', NULL, 'nullify'),
  ('screen_printing_work', 'customer', 'customers', NULL, 'nullify'),
  ('screen_printing_work', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('screen_printing_work', 'manager_employee', 'employees', NULL, 'nullify'),
  ('screen_printing_work', 'production_status', 'production_statuses', NULL, 'nullify'),

  ('contractor_work', 'order_item', 'orders_items', NULL, 'nullify'),
  ('contractor_work', 'contractor', 'contractors', NULL, 'nullify'),
  ('contractor_work', 'order', 'orders', NULL, 'nullify'),
  ('contractor_work', 'customer', 'customers', NULL, 'nullify'),
  ('contractor_work', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('contractor_work', 'manager_employee', 'employees', NULL, 'nullify'),
  ('contractor_work', 'production_status', 'production_statuses', NULL, 'nullify');

DELETE FROM directus_relations
WHERE many_collection = 'product_categories'
  AND many_field IN ('default_contractor_1', 'default_contractor_2');

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
)
SELECT rel.many_collection, rel.many_field, rel.one_collection, rel.one_field, rel.one_deselect_action
FROM (
  VALUES
    ('contractors', 'directus_user', 'directus_users', NULL, 'nullify'),
    ('contractors', 'default_product_category', 'product_categories', NULL, 'nullify'),
    ('contractors', 'default_product_subcategory', 'product_subcategories', NULL, 'nullify'),
    ('orders_items', 'application_method', 'product_application_methods', NULL, 'nullify'),
    ('product_routing_rules', 'product_category', 'product_categories', NULL, 'cascade'),
    ('product_routing_rules', 'product_subcategory', 'product_subcategories', NULL, 'cascade'),
    ('product_routing_rules', 'application_method', 'product_application_methods', NULL, 'cascade'),
    ('product_routing_rules', 'contractor_1', 'contractors', NULL, 'nullify'),
    ('product_routing_rules', 'contractor_2', 'contractors', NULL, 'nullify')
) AS rel(many_collection, many_field, one_collection, one_field, one_deselect_action)
WHERE NOT EXISTS (
  SELECT 1
    FROM directus_relations dr
   WHERE dr.many_collection = rel.many_collection
     AND dr.many_field = rel.many_field
);

DELETE FROM directus_fields
WHERE collection = 'order_payments'
  AND field IN (
    'order_link',
    'access_manager_user',
    'access_shipping_method',
    'order_number_display',
    'customer_name_display',
    'customer_company_name_display'
  );

DELETE FROM directus_fields
WHERE collection IN ('orders_items', 'payment_allocations')
  AND field IN ('order_link', 'application_method');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
VALUES
  ('order_payments', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('order_payments', 'order_number_display', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437'))::json, false, true),
  ('order_payments', 'customer_name_display', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\0438\0435\043d\0442'))::json, false, true),
  ('order_payments', 'customer_company_name_display', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043f\0430\043d\0438\044f'))::json, false, true),
  ('order_payments', 'access_manager_user', NULL, 'input', NULL, NULL, NULL, true, true, 1000, 'half', '[{"language":"ru-RU","translation":"Access Manager User"}]'::json, false, false),
  ('order_payments', 'access_shipping_method', NULL, 'input', NULL, NULL, NULL, true, true, 1001, 'half', '[{"language":"ru-RU","translation":"Access Shipping Method"}]'::json, false, false);

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('orders_items', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true),
  ('orders_items', 'application_method', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 16, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f'))::json, false, true),
  ('payment_allocations', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true);

INSERT INTO directus_roles (id, name, icon, description, parent)
VALUES
  ('00000000-0000-4000-8000-000000000304', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 'format_paint', U&'\0412\043d\0443\0442\0440\0435\043d\043d\0435\0435 \043f\043e\0434\0440\0430\0437\0434\0435\043b\0435\043d\0438\0435: \0448\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', NULL),
  ('00000000-0000-4000-8000-000000000307', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442', 'assignment_ind', U&'\0412\043d\0435\0448\043d\0438\0439 \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442', NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  description = EXCLUDED.description;

INSERT INTO directus_policies (id, name, icon, description, ip_access, enforce_tfa, admin_access, app_access)
VALUES
  ('00000000-0000-4000-8000-000000000206', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \2014 \0431\0435\0437 \0444\0438\043d\0430\043d\0441\043e\0432', 'format_paint', U&'\0414\043e\0441\0442\0443\043f \0442\043e\043b\044c\043a\043e \043a \043f\0440\0435\0434\0441\0442\0430\0432\043b\0435\043d\0438\044e \0448\0435\043b\043a\043e\0433\0440\0430\0444\0438\0438', NULL, false, false, true),
  ('00000000-0000-4000-8000-000000000207', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442 - \0441\0432\043e\0438 \0440\0430\0431\043e\0442\044b', 'assignment_ind', U&'\0412\043d\0435\0448\043d\0438\0439 \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442 \0432\0438\0434\0438\0442 \0442\043e\043b\044c\043a\043e \0441\0432\043e\0438 \043f\043e\0437\0438\0446\0438\0438', NULL, false, false, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  description = EXCLUDED.description,
  admin_access = EXCLUDED.admin_access,
  app_access = EXCLUDED.app_access;

UPDATE directus_policies
SET name = U&'\041f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e - \0431\0435\0437 \0444\0438\043d\0430\043d\0441\043e\0432',
    icon = 'engineering',
    description = U&'\0414\043e\0441\0442\0443\043f \0442\043e\043b\044c\043a\043e \043a \043f\0440\0435\0434\0441\0442\0430\0432\043b\0435\043d\0438\044e \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430',
    app_access = true
WHERE id = '00000000-0000-4000-8000-000000000204';

INSERT INTO directus_access (id, role, "user", policy, sort)
SELECT gen_random_uuid(), access_role, NULL::uuid, access_policy, access_sort
FROM (
  VALUES
    ('b08d79e9-b55d-4105-b9e7-e5b782b91056'::uuid, '00000000-0000-4000-8000-000000000204'::uuid, 1),
    ('00000000-0000-4000-8000-000000000304'::uuid, '00000000-0000-4000-8000-000000000206'::uuid, 1),
    ('00000000-0000-4000-8000-000000000307'::uuid, '00000000-0000-4000-8000-000000000207'::uuid, 1)
) AS access(access_role, access_policy, access_sort)
WHERE NOT EXISTS (
  SELECT 1
    FROM directus_access da
   WHERE da.role = access.access_role
     AND da.policy = access.access_policy
);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT target.collection, target.action, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (
  VALUES
    ('office_issue', 'read'),
    ('office_issue', 'update'),
    ('office_issue_items', 'read'),
    ('office_issue_items', 'update'),
    ('office_issue_archive', 'read'),
    ('office_issue_archive_items', 'read'),
    ('office_items_in_office', 'read'),
    ('office_items_in_office', 'update'),
    ('production_work', 'read'),
    ('production_work', 'update'),
    ('screen_printing_work', 'read'),
    ('screen_printing_work', 'update'),
    ('contractor_work', 'read'),
    ('contractor_work', 'update'),
    ('product_application_methods', 'create'),
    ('product_application_methods', 'read'),
    ('product_application_methods', 'update'),
    ('product_application_methods', 'delete'),
    ('product_routing_rules', 'create'),
    ('product_routing_rules', 'read'),
    ('product_routing_rules', 'update'),
    ('product_routing_rules', 'delete')
) AS target(collection, action)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('office_issue', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue_items', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue_items', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue_archive', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue_archive_items', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_items_in_office', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_items_in_office', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_application_methods', 'create', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_application_methods', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_application_methods', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_application_methods', 'delete', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_routing_rules', 'create', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_routing_rules', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_routing_rules', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('product_routing_rules', 'delete', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('office_issue', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue', 'update', '{}'::json, NULL, NULL, 'id,office_summary,office_customer,office_payment,office_positions,office_status,add_payment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_items', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_archive', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_archive_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_items_in_office', 'read', '{}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_items_in_office', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000203'),
  ('employee_positions', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000203'),

  ('office_issue', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue', 'update', '{}'::json, NULL, NULL, 'id,office_summary,office_customer,office_payment,office_positions,office_status,add_payment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_archive', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_archive_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_items_in_office', 'read', '{}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_items_in_office', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'read', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_items', 'update', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_archive', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_archive_items', 'read', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_items_in_office', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_items_in_office', 'update', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000202'),

  ('production_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('production_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('production_work', 'read', '{}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,product_name,quantity,deadline,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000204'),
  ('production_work', 'update', '{}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000204'),

  ('screen_printing_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('screen_printing_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('screen_printing_work', 'read', '{}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,product_name,quantity,deadline,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000206'),
  ('screen_printing_work', 'update', '{}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000206'),

  ('contractor_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('contractor_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('contractor_work', 'read', '{"_and":[{"contractor_has_own_view":{"_eq":true}},{"access_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,contractor,product_name,quantity,deadline,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000207'),
  ('contractor_work', 'update', '{"_and":[{"contractor_has_own_view":{"_eq":true}},{"access_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000207');

UPDATE directus_permissions
   SET fields = 'id,office_summary,office_customer,office_payment,office_positions,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items'
 WHERE collection = 'office_issue'
   AND action = 'read'
   AND fields IS NOT NULL
   AND fields <> '*';

UPDATE directus_permissions
   SET fields = 'id,office_summary,office_customer,office_payment,office_positions,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items'
 WHERE collection = 'office_issue_archive'
   AND action = 'read'
   AND fields IS NOT NULL
   AND fields <> '*';

DELETE FROM directus_permissions
 WHERE policy = '00000000-0000-4000-8000-000000000203'
   AND collection IN ('orders', 'orders_items');

DELETE FROM directus_permissions
 WHERE policy = '00000000-0000-4000-8000-000000000203'
   AND collection = 'payment_types'
   AND action = 'read';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('payment_types', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000203');

DELETE FROM directus_permissions
 WHERE collection = 'directus_notifications'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000207'
   );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'directus_notifications',
       action,
       '{"recipient":{"_eq":"$CURRENT_USER"}}'::json,
       NULL,
       NULL,
       CASE
         WHEN action = 'read' THEN 'id,status,recipient,subject,message,collection,item,timestamp'
         ELSE 'status'
       END,
       policy::uuid
FROM (
  VALUES
    ('read', '00000000-0000-4000-8000-000000000201'),
    ('update', '00000000-0000-4000-8000-000000000201'),
    ('read', '00000000-0000-4000-8000-000000000202'),
    ('update', '00000000-0000-4000-8000-000000000202'),
    ('read', '00000000-0000-4000-8000-000000000203'),
    ('update', '00000000-0000-4000-8000-000000000203'),
    ('read', '00000000-0000-4000-8000-000000000204'),
    ('update', '00000000-0000-4000-8000-000000000204'),
    ('read', '00000000-0000-4000-8000-000000000206'),
    ('update', '00000000-0000-4000-8000-000000000206'),
    ('read', '00000000-0000-4000-8000-000000000207'),
    ('update', '00000000-0000-4000-8000-000000000207')
) AS notification_permissions(action, policy);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection, 'read', '{}'::json, NULL, NULL, '*', policy::uuid
FROM (
  VALUES
    ('product_categories', '00000000-0000-4000-8000-000000000201'),
    ('product_subcategories', '00000000-0000-4000-8000-000000000201'),
    ('product_application_methods', '00000000-0000-4000-8000-000000000201'),
    ('product_categories', '00000000-0000-4000-8000-000000000202'),
    ('product_subcategories', '00000000-0000-4000-8000-000000000202'),
    ('product_application_methods', '00000000-0000-4000-8000-000000000202'),
    ('product_categories', '00000000-0000-4000-8000-000000000203'),
    ('product_subcategories', '00000000-0000-4000-8000-000000000203'),
    ('product_application_methods', '00000000-0000-4000-8000-000000000203')
) AS refs(collection, policy);

DELETE FROM directus_permissions
 WHERE policy IN (
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203'
  )
   AND collection IN ('order_payments', 'payment_allocations')
   AND action = 'update';

DELETE FROM directus_permissions
 WHERE policy = '00000000-0000-4000-8000-000000000201'
   AND collection IN ('customers', 'customer_companies', 'customer_company_links');

DELETE FROM directus_permissions
 WHERE policy IN (
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203'
  )
   AND collection IN ('customers', 'customer_companies', 'customer_company_links');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('customers', 'create', '{}'::json, NULL, NULL, 'name,phone,email,manager,company,comment', '00000000-0000-4000-8000-000000000201'),
  ('customers', 'read', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('customers', 'update', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'name,phone,email,company,comment', '00000000-0000-4000-8000-000000000201'),
  ('customer_companies', 'create', '{}'::json, NULL, NULL, 'name,phone,email,manager,comment', '00000000-0000-4000-8000-000000000201'),
  ('customer_companies', 'read', '{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('customer_company_links', 'read', '{"customer":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('customers', 'create', '{}'::json, NULL, NULL, 'name,phone,email,manager,company,comment', '00000000-0000-4000-8000-000000000202'),
  ('customers', 'read', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202'),
  ('customers', 'update', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'name,phone,email,company,comment', '00000000-0000-4000-8000-000000000202'),
  ('customer_companies', 'create', '{}'::json, NULL, NULL, 'name,phone,email,manager,comment', '00000000-0000-4000-8000-000000000202'),
  ('customer_companies', 'read', '{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202'),
  ('customer_company_links', 'read', '{"customer":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('order_payments', 'update', '{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'order,customer,customer_company,amount,payment_date,payment_type,payment_direction,allocation_mode,comment', '00000000-0000-4000-8000-000000000202'),
  ('payment_allocations', 'update', '{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'payment,order,amount,comment', '00000000-0000-4000-8000-000000000202'),
  ('order_payments', 'update', '{"order":{"shipping_method":{"_eq":"office_pickup"}}}'::json, NULL, NULL, 'order,customer,customer_company,amount,payment_date,payment_type,payment_direction,allocation_mode,comment', '00000000-0000-4000-8000-000000000203'),
  ('payment_allocations', 'update', '{"order":{"shipping_method":{"_eq":"office_pickup"}}}'::json, NULL, NULL, 'payment,order,amount,comment', '00000000-0000-4000-8000-000000000203');

UPDATE directus_permissions
   SET fields = '*'
 WHERE collection IN ('order_payments', 'payment_allocations')
   AND action IN ('read', 'update')
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203'
   );

UPDATE directus_permissions
   SET permissions = '{"_or":[{"access_manager_user":{"_eq":"$CURRENT_USER"}},{"access_shipping_method":{"_eq":"office_pickup"}}]}'::json
 WHERE collection = 'order_payments'
   AND action = 'read'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   );

UPDATE directus_permissions
   SET fields = 'id,order,order_link,amount,order_number_display,customer_name_display,customer_company_name_display,payment_date,payment_type,payment_direction,allocation_mode,allocated_amount,unallocated_amount,comment'
 WHERE collection = 'order_payments'
   AND action = 'read'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203'
   );

UPDATE directus_permissions
   SET permissions = '{"access_manager_user":{"_eq":"$CURRENT_USER"}}'::json
 WHERE collection = 'order_payments'
   AND action = 'update'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   );

UPDATE directus_permissions
   SET permissions = '{}'::json
 WHERE collection = 'order_payments'
   AND action IN ('read', 'update')
   AND policy = '00000000-0000-4000-8000-000000000203';

UPDATE directus_permissions
   SET permissions = '{}'::json
 WHERE collection = 'payment_allocations'
   AND action IN ('read', 'update')
   AND policy = '00000000-0000-4000-8000-000000000203';

UPDATE directus_permissions
   SET fields = fields || ',payments'
 WHERE collection = 'orders'
   AND action IN ('create', 'update')
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   )
   AND fields IS NOT NULL
   AND fields <> '*'
   AND fields NOT LIKE '%payments%';

UPDATE directus_permissions
   SET fields = fields || ',order_number'
 WHERE collection = 'orders'
   AND action IN ('create', 'update')
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   )
   AND fields IS NOT NULL
   AND fields <> '*'
   AND fields NOT LIKE '%order_number%';

UPDATE directus_permissions
   SET fields = fields || ',manager_employee'
 WHERE collection = 'orders'
   AND action IN ('create', 'update')
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   )
   AND fields IS NOT NULL
   AND fields <> '*'
   AND fields NOT LIKE '%manager_employee%';

UPDATE directus_permissions
   SET fields = fields || ',payment'
 WHERE collection = 'orders'
   AND action IN ('create', 'read', 'update')
   AND fields IS NOT NULL
   AND fields <> '*'
   AND fields NOT LIKE '%payment%';

UPDATE directus_permissions
   SET fields = replace(replace(fields, ',payment', ''), ',finance', '')
 WHERE collection = 'orders'
   AND policy = '00000000-0000-4000-8000-000000000204'
   AND fields IS NOT NULL
   AND fields <> '*';

UPDATE directus_permissions
   SET fields = 'id,full_name,position,phone'
 WHERE collection = 'employees'
   AND action = 'read'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204'
   );

UPDATE directus_permissions
   SET fields = CASE
     WHEN action = 'read' THEN 'id,accordion-redqc5,main,item,tech,order,order_link,product_name,quantity,price_per_unit,order_sum,product_category,product_subcategory,application_method,item_status,production_status,deadline,production_comment,technical_task_text,manager_employee,shipping_method,office_status,url'
     ELSE 'accordion-redqc5,main,item,tech,order,product_name,quantity,price_per_unit,order_sum,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url'
   END
 WHERE collection = 'orders_items'
   AND action IN ('create', 'read', 'update')
   AND fields IS NOT NULL
   AND fields <> '*'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   );

UPDATE directus_permissions
   SET presets = jsonb_set(coalesce(presets::jsonb, '{}'::jsonb), '{production_status}', '7'::jsonb)::json
 WHERE collection = 'orders_items'
   AND action = 'create'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
   );

UPDATE directus_permissions
   SET fields = CASE
     WHEN action = 'read' THEN 'id,accordion-redqc5,main,item,tech,order,product_name,quantity,product_category,product_subcategory,application_method,item_status,production_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url'
     ELSE 'production_status,production_comment'
   END
 WHERE collection = 'orders_items'
   AND action IN ('read', 'update')
   AND fields IS NOT NULL
   AND fields <> '*'
   AND policy = '00000000-0000-4000-8000-000000000204';

DELETE FROM directus_permissions
 WHERE collection = 'employees'
   AND action IN ('create', 'update', 'delete')
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204'
   );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'employees', 'read', '{}'::json, NULL, NULL, 'id,full_name,position,phone', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204')
) AS p(policy_id)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions dp
  WHERE dp.collection = 'employees'
    AND dp.action = 'read'
    AND dp.policy = p.policy_id::uuid
);

DELETE FROM directus_permissions a
USING directus_permissions b
WHERE a.id > b.id
  AND a.collection = b.collection
  AND a.action = b.action
  AND a.policy = b.policy
  AND COALESCE(a.fields, '') = COALESCE(b.fields, '')
  AND COALESCE(a.permissions::text, '') = COALESCE(b.permissions::text, '');

UPDATE directus_settings
SET default_language = 'ru-RU'
WHERE id = 1;

UPDATE directus_users
SET language = 'ru-RU'
WHERE language IS DISTINCT FROM 'ru-RU';

UPDATE directus_settings
SET custom_css = trim(
  COALESCE(
    NULLIF(
      regexp_replace(
        COALESCE(custom_css, ''),
        $re$/\* Symbolika readonly fields \*/(.|\n|\r)*/\* End Symbolika readonly fields \*/$re$,
        '',
        'g'
      ),
      ''
    ) || E'\n\n',
    ''
  ) || $css$
/* Symbolika readonly fields */
body .field.readonly > .interface :is(.v-select, .v-input, .v-textarea),
body .field.disabled > .interface :is(.v-select, .v-input, .v-textarea),
body :is(
  [data-collection="orders"][data-field="order_number"],
  [data-collection="orders"][data-field="manager_employee"],
  [data-collection="orders"][data-field="order_sum"],
  [data-collection="orders"][data-field="paid_amount"],
  [data-collection="orders"][data-field="payment_due"],
  [data-collection="orders"][data-field="office_payment_due"],
  [data-collection="orders"][data-field="items_total_cost"],
  [data-collection="orders"][data-field="items_tax_sum"],
  [data-collection="orders"][data-field="items_manager_commission_sum"],
  [data-collection="orders"][data-field="profit_sum"],
  [data-collection="orders"][data-field="margin_percent"],
  [data-collection="office_issue"][data-field="order_number"],
  [data-collection="office_issue"][data-field="date"],
  [data-collection="office_issue"][data-field="deadline"],
  [data-collection="office_issue"][data-field="customer_name"],
  [data-collection="office_issue"][data-field="customer_phone"],
  [data-collection="office_issue"][data-field="customer_company_name"],
  [data-collection="office_issue"][data-field="manager_employee"],
  [data-collection="office_issue"][data-field="order_status_name"],
  [data-collection="office_issue"][data-field="order_sum"],
  [data-collection="office_issue"][data-field="paid_amount"],
  [data-collection="office_issue"][data-field="payment_due"],
  [data-collection="office_issue"][data-field="office_payment_due"],
  [data-collection="office_issue"][data-field="overpayment"],
  [data-collection="office_issue_items"][data-field="product_name"],
  [data-collection="office_issue_items"][data-field="quantity"],
  [data-collection="office_items_in_office"][data-field="order_number"],
  [data-collection="office_items_in_office"][data-field="customer_name"],
  [data-collection="office_items_in_office"][data-field="customer_company_name"],
  [data-collection="office_items_in_office"][data-field="manager_employee"],
  [data-collection="office_items_in_office"][data-field="product_name"],
  [data-collection="office_items_in_office"][data-field="quantity"],
  [data-collection="customers"][data-field="orders_total_sum"],
  [data-collection="customers"][data-field="payments_total_in"],
  [data-collection="customers"][data-field="refunds_total_out"],
  [data-collection="customers"][data-field="balance"],
  [data-collection="customers"][data-field="debt_to_us"],
  [data-collection="customers"][data-field="our_debt_to_customer"],
  [data-collection="customer_companies"][data-field="orders_total_sum"],
  [data-collection="customer_companies"][data-field="payments_total_in"],
  [data-collection="customer_companies"][data-field="refunds_total_out"],
  [data-collection="customer_companies"][data-field="balance"],
  [data-collection="customer_companies"][data-field="debt_to_us"],
  [data-collection="customer_companies"][data-field="our_debt_to_customer"]
) > .interface :is(.v-select, .v-input, .v-textarea) {
  color: var(--theme--foreground-subdued) !important;
  -webkit-text-fill-color: var(--theme--foreground-subdued) !important;
  background-color: var(--theme--form--field--input--background-subdued) !important;
  border-color: var(--theme--border-color-subdued) !important;
  opacity: .72 !important;
  cursor: not-allowed !important;
  overflow: hidden !important;
}

body :is(
  [data-collection="office_issue"][data-field="date"],
  [data-collection="office_issue"][data-field="deadline"],
  [data-collection="office_items_in_office"][data-field="manager_employee"]
) > .interface .v-list-item.disabled {
  color: var(--theme--foreground-subdued) !important;
  -webkit-text-fill-color: var(--theme--foreground-subdued) !important;
  background-color: var(--theme--form--field--input--background-subdued) !important;
  border-color: var(--theme--border-color-subdued) !important;
  opacity: .72 !important;
  cursor: not-allowed !important;
}

body .field.readonly > .interface :is(.v-select, .v-input, .v-textarea) :is(.input, .append, .prepend, input, textarea, button),
body .field.disabled > .interface :is(.v-select, .v-input, .v-textarea) :is(.input, .append, .prepend, input, textarea, button),
body :is(
  [data-collection="orders"][data-field="order_number"],
  [data-collection="orders"][data-field="manager_employee"],
  [data-collection="orders"][data-field="order_sum"],
  [data-collection="orders"][data-field="paid_amount"],
  [data-collection="orders"][data-field="payment_due"],
  [data-collection="orders"][data-field="office_payment_due"],
  [data-collection="orders"][data-field="items_total_cost"],
  [data-collection="orders"][data-field="items_tax_sum"],
  [data-collection="orders"][data-field="items_manager_commission_sum"],
  [data-collection="orders"][data-field="profit_sum"],
  [data-collection="orders"][data-field="margin_percent"],
  [data-collection="office_issue"][data-field="order_number"],
  [data-collection="office_issue"][data-field="date"],
  [data-collection="office_issue"][data-field="deadline"],
  [data-collection="office_issue"][data-field="customer_name"],
  [data-collection="office_issue"][data-field="customer_phone"],
  [data-collection="office_issue"][data-field="customer_company_name"],
  [data-collection="office_issue"][data-field="manager_employee"],
  [data-collection="office_issue"][data-field="order_status_name"],
  [data-collection="office_issue"][data-field="order_sum"],
  [data-collection="office_issue"][data-field="paid_amount"],
  [data-collection="office_issue"][data-field="payment_due"],
  [data-collection="office_issue"][data-field="office_payment_due"],
  [data-collection="office_issue"][data-field="overpayment"],
  [data-collection="office_issue_items"][data-field="product_name"],
  [data-collection="office_issue_items"][data-field="quantity"],
  [data-collection="office_items_in_office"][data-field="order_number"],
  [data-collection="office_items_in_office"][data-field="customer_name"],
  [data-collection="office_items_in_office"][data-field="customer_company_name"],
  [data-collection="office_items_in_office"][data-field="manager_employee"],
  [data-collection="office_items_in_office"][data-field="product_name"],
  [data-collection="office_items_in_office"][data-field="quantity"],
  [data-collection="customers"][data-field="orders_total_sum"],
  [data-collection="customers"][data-field="payments_total_in"],
  [data-collection="customers"][data-field="refunds_total_out"],
  [data-collection="customers"][data-field="balance"],
  [data-collection="customers"][data-field="debt_to_us"],
  [data-collection="customers"][data-field="our_debt_to_customer"],
  [data-collection="customer_companies"][data-field="orders_total_sum"],
  [data-collection="customer_companies"][data-field="payments_total_in"],
  [data-collection="customer_companies"][data-field="refunds_total_out"],
  [data-collection="customer_companies"][data-field="balance"],
  [data-collection="customer_companies"][data-field="debt_to_us"],
  [data-collection="customer_companies"][data-field="our_debt_to_customer"]
) > .interface :is(.v-select, .v-input, .v-textarea) :is(.input, .append, .prepend, input, textarea, button) {
  color: var(--theme--foreground-subdued) !important;
  -webkit-text-fill-color: var(--theme--foreground-subdued) !important;
  background-color: transparent !important;
  opacity: 1 !important;
}

body .field :is(input[readonly], textarea[readonly], input:disabled, textarea:disabled)::placeholder {
  color: var(--theme--foreground-subdued) !important;
  opacity: .75 !important;
}

body .field .v-select .v-input > :is(.input, .append, .prepend) {
  background-color: transparent !important;
}

body .field .v-select .v-input > :is(.append, .prepend) {
  border-color: transparent !important;
}

@media (min-width: 1180px) {
  body [data-collection="orders"][data-field="payment_on_receipt"] {
    grid-column: 1 / 2 !important;
  }

  body [data-collection="orders"][data-field="payment_type"] {
    grid-column: 2 / 3 !important;
  }

  body [data-collection="orders"][data-field="payments"] {
    grid-column: 3 / -1 !important;
    inline-size: auto !important;
    width: auto !important;
  }

  body [data-collection="orders"][data-field="shipping_comment"] {
    grid-column: 3 / 5 !important;
    grid-column-start: 3 !important;
    grid-column-end: 5 !important;
    inline-size: auto !important;
    width: auto !important;
  }

  body .group-raw.full > .v-form.grid.with-fill > .field.half-right[data-collection="orders"][data-field="shipping_comment"] {
    grid-column: 3 / 5 !important;
    grid-column-start: 3 !important;
    grid-column-end: 5 !important;
    inline-size: auto !important;
    width: auto !important;
  }

  body [data-collection="orders"][data-field="comment"] {
    grid-column: 3 / 5 !important;
    grid-column-start: 3 !important;
    grid-column-end: 5 !important;
    inline-size: auto !important;
    width: auto !important;
  }

  body .v-detail.group-detail:has([data-collection="orders"][data-field="payments"])
    > .content
    > .v-form.grid.with-fill {
    grid-template-columns: repeat(4, minmax(0, 1fr)) !important;
  }
}

body [data-collection="orders"][data-field="shipping_comment"] .interface,
body [data-collection="orders"][data-field="shipping_comment"] :is(.v-textarea, .input, textarea) {
  block-size: 76px !important;
  height: 76px !important;
  min-block-size: 76px !important;
  min-height: 76px !important;
  max-block-size: 76px !important;
  max-height: 76px !important;
}

body [data-collection="orders"][data-field="comment"] .interface,
body [data-collection="orders"][data-field="comment"] :is(.v-textarea, .input, textarea) {
  block-size: 76px !important;
  height: 76px !important;
  min-block-size: 76px !important;
  min-height: 76px !important;
  max-block-size: 76px !important;
  max-height: 76px !important;
}

body .field:not(.readonly):not(.disabled):has(:is(input[required], textarea[required], [aria-required="true"])) > .interface :is(.v-select:not(.disabled), .v-input:not(.disabled), .v-textarea:not(.disabled)),
body .field:not(.readonly):not(.disabled):is([data-field="customer"], [data-field="amount"], [data-field="payment_date"], [data-field="payment_direction"], [data-field="allocation_mode"]) > .interface :is(.v-select:not(.disabled), .v-input:not(.disabled), .v-textarea:not(.disabled)) {
  border-color: var(--theme--primary) !important;
  box-shadow: 0 0 0 1px var(--theme--primary) inset !important;
}

body [data-collection="office_items_in_office"][data-field="office_issue"] .field-label {
  visibility: hidden !important;
  pointer-events: none !important;
}

body [data-collection="office_items_in_office"][data-field="office_issue"] .interface {
  display: flex !important;
  justify-content: flex-end !important;
}

body [data-collection="office_items_in_office"][data-field="office_issue"] .symbolika-office-issue-link {
  transform: translateY(8px);
}

body [data-collection="office_issue"][data-field="order_items"] td:has(.display-formatted[collection="office_issue_items"][field="product_name"]),
body [data-collection="office_issue"][data-field="order_items"] td:has(.display-formatted[collection="office_issue_items"][field="quantity"]) {
  background-color: var(--theme--form--field--input--background-subdued) !important;
}

body [data-collection="office_issue"][data-field="order_items"] .display-formatted[collection="office_issue_items"][field="product_name"],
body [data-collection="office_issue"][data-field="order_items"] .display-formatted[collection="office_issue_items"][field="quantity"],
body [data-collection="office_issue"][data-field="order_items"] .display-formatted[collection="office_issue_items"][field="product_name"] .value,
body [data-collection="office_issue"][data-field="order_items"] .display-formatted[collection="office_issue_items"][field="quantity"] .value {
  color: var(--theme--foreground-subdued) !important;
  -webkit-text-fill-color: var(--theme--foreground-subdued) !important;
}

body {
  --symbolika-dark-readonly-bg: #161b22;
  --symbolika-dark-readonly-text: #8f98a6;
  --symbolika-dark-readonly-border: #252c36;
}

body .field.readonly > .interface :is(.v-select, .v-input, .v-textarea),
body .field.disabled > .interface :is(.v-select, .v-input, .v-textarea),
body :is(
  [data-collection="orders"][data-field="order_number"],
  [data-collection="orders"][data-field="manager_employee"],
  [data-collection="orders"][data-field="order_sum"],
  [data-collection="orders"][data-field="paid_amount"],
  [data-collection="orders"][data-field="payment_due"],
  [data-collection="orders"][data-field="office_payment_due"],
  [data-collection="office_issue"][data-field="order_number"],
  [data-collection="office_issue"][data-field="date"],
  [data-collection="office_issue"][data-field="deadline"],
  [data-collection="office_issue"][data-field="customer_name"],
  [data-collection="office_issue"][data-field="customer_phone"],
  [data-collection="office_issue"][data-field="customer_company_name"],
  [data-collection="office_issue"][data-field="order_sum"],
  [data-collection="office_issue"][data-field="paid_amount"],
  [data-collection="office_issue"][data-field="payment_due"],
  [data-collection="office_issue"][data-field="office_payment_due"]
) > .interface :is(.v-select, .v-input, .v-textarea) {
  background-color: var(--symbolika-dark-readonly-bg) !important;
  border-color: var(--symbolika-dark-readonly-border) !important;
  color: var(--symbolika-dark-readonly-text) !important;
  -webkit-text-fill-color: var(--symbolika-dark-readonly-text) !important;
  opacity: 1 !important;
}

@media (min-width: 1180px) {
  body .v-form.grid.with-fill > .field.half[data-collection="orders"][data-field="comment"] {
    grid-column: 3 / 5 !important;
    grid-column-start: 3 !important;
    grid-column-end: 5 !important;
    inline-size: auto !important;
    width: auto !important;
  }
}
/* End Symbolika readonly fields */
$css$
)
WHERE id = 1;

UPDATE directus_settings
SET custom_css = trim(
  substring(custom_css from 1 for position('/* Symbolika readonly fields */' in custom_css) - 1)
  || E'\n/* Symbolika readonly fields moved to injected symbolika-admin-ui.css */'
  || substring(custom_css from position('/* End Symbolika readonly fields */' in custom_css) + length('/* End Symbolika readonly fields */'))
)
WHERE id = 1
  AND position('/* Symbolika readonly fields */' in custom_css) > 0
  AND position('/* End Symbolika readonly fields */' in custom_css) > 0;

-- Keep Russian labels safe from shell/codepage conversions.
UPDATE order_statuses
SET name = U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
WHERE name = U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435 \043c\0430\043a\0435\0442\0430';

INSERT INTO order_statuses (name, sort, is_active)
SELECT status_name, sort_value, true
FROM (VALUES
  (U&'\041d\043e\0432\044b\0439', 1),
  (U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 2),
  (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 3),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 4),
  (U&'\0413\043e\0442\043e\0432', 5),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 6),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 7)
) AS required_statuses(status_name, sort_value)
WHERE NOT EXISTS (
  SELECT 1
  FROM order_statuses os
  WHERE os.name = required_statuses.status_name
);

UPDATE order_statuses os
SET sort = required_statuses.sort_value,
    is_active = true
FROM (VALUES
  (U&'\041d\043e\0432\044b\0439', 1),
  (U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 2),
  (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 3),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 4),
  (U&'\0413\043e\0442\043e\0432', 5),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 6),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 7)
) AS required_statuses(status_name, sort_value)
WHERE os.name = required_statuses.status_name;

INSERT INTO production_statuses (name, sort, is_active)
SELECT U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 8, true
WHERE NOT EXISTS (
  SELECT 1
  FROM production_statuses
  WHERE name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
);

ALTER TABLE orders_items ALTER COLUMN production_status SET DEFAULT 7;

UPDATE orders_items
SET production_status = 7
WHERE production_status IS NULL;

UPDATE production_statuses
SET sort = CASE name
  WHEN U&'\041d\0435 \0432 \0440\0430\0431\043e\0442\0435' THEN 1
  WHEN U&'\0412 \0440\0430\0431\043e\0442\0435' THEN 2
  WHEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN 3
  WHEN U&'\0413\043e\0442\043e\0432' THEN 4
  WHEN U&'\041e\0442\043c\0435\043d\0435\043d' THEN 5
  ELSE sort
END,
is_active = true;

UPDATE orders_items
SET item_status = symbolika_normalize_item_status(item_status)
WHERE item_status IS DISTINCT FROM symbolika_normalize_item_status(item_status);

WITH categories(name, detail_mode, sort) AS (VALUES
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', 'subcategory', 10),
  (U&'\0411\0430\043d\043d\0435\0440\044b', 'none', 20),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', 'subcategory', 30),
  (U&'\041f\0412\0425 - \0442\0430\0431\043b\0438\0447\043a\0438', 'none', 40),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', 'application_method', 50),
  (U&'\0423\043f\0430\043a\043e\0432\043a\0430', 'subcategory', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', 'application_method', 70),
  (U&'\0422\043a\0430\043d\0438', 'subcategory', 80),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', 'subcategory', 90),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', 'application_method', 100)
)
INSERT INTO product_categories (name, detail_mode, sort, is_active)
SELECT name, detail_mode, sort, true
FROM categories c
WHERE NOT EXISTS (SELECT 1 FROM product_categories pc WHERE pc.name = c.name);

WITH categories(name, detail_mode, sort) AS (VALUES
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', 'subcategory', 10),
  (U&'\0411\0430\043d\043d\0435\0440\044b', 'none', 20),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', 'subcategory', 30),
  (U&'\041f\0412\0425 - \0442\0430\0431\043b\0438\0447\043a\0438', 'none', 40),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', 'application_method', 50),
  (U&'\0423\043f\0430\043a\043e\0432\043a\0430', 'subcategory', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', 'application_method', 70),
  (U&'\0422\043a\0430\043d\0438', 'subcategory', 80),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', 'subcategory', 90),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', 'application_method', 100)
)
UPDATE product_categories pc
SET detail_mode = c.detail_mode,
    sort = c.sort,
    is_active = true
FROM categories c
WHERE pc.name = c.name;

WITH subcategories(category_name, name, sort) AS (VALUES
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0413\0440\0430\043c\043e\0442\044b', 10),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0412\0438\0437\0438\0442\043a\0438', 20),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041b\0438\0441\0442\043e\0432\043a\0438', 30),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\043b\043e\043a\043d\043e\0442\044b', 40),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041a\0430\043b\0435\043d\0434\0430\0440\0438', 50),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0440\043e\0448\044e\0440\044b', 60),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0443\043a\043b\0435\0442\044b', 70),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', U&'\0415\0434\0438\043d\0438\0447\043d\044b\0435 \043d\0430\043a\043b\0435\0439\043a\0438', 10),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', U&'\0421\0442\0438\043a\0435\0440\043f\0430\043a\0438', 20),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', U&'\041d\0430\043a\043b\0435\0439\043a\0438 \043d\0430 \043c\043e\043d\0442\0430\0436\043a\0435', 30),
  (U&'\041d\0430\043a\043b\0435\0439\043a\0438', U&'\0423\0424-\0414\0422\0424', 40),
  (U&'\0423\043f\0430\043a\043e\0432\043a\0430', U&'\041f\0430\043a\0435\0442\044b \0431\0443\043c\0430\0436\043d\044b\0435', 10),
  (U&'\0423\043f\0430\043a\043e\0432\043a\0430', U&'\041f\0430\043a\0435\0442\044b \041f\0412\0414', 20),
  (U&'\0423\043f\0430\043a\043e\0432\043a\0430', U&'\041a\043e\0440\043e\0431\043a\0438', 30),
  (U&'\0422\043a\0430\043d\0438', U&'\0424\043b\0430\0433\0438 \0441\0442\0430\043d\0434\0430\0440\0442\043d\044b\0435', 10),
  (U&'\0422\043a\0430\043d\0438', U&'\0424\043b\0430\0433\0438 \043d\0435\0441\0442\0430\043d\0434\0430\0440\0442\043d\044b\0435', 20),
  (U&'\0422\043a\0430\043d\0438', U&'\0424\043b\0430\0433\0438 \0434\043b\044f \0432\0438\043d\0434\0435\0440\043e\0432', 30),
  (U&'\0422\043a\0430\043d\0438', U&'\0411\0430\043d\0434\0430\043d\044b', 40),
  (U&'\0422\043a\0430\043d\0438', U&'\041f\0440\043e\0447\0430\044f \043f\043e\043b\043d\043e\0446\0432\0435\0442\043d\0430\044f \043f\0435\0447\0430\0442\044c \043d\0430 \0442\043a\0430\043d\0438', 50),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', U&'\0420\043e\043b\0430\043f', 10),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', U&'\0412\0438\043d\0434\0435\0440', 20),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', U&'\0414\0436\043e\043a\0435\0440', 30),
  (U&'\041a\043e\043d\0441\0442\0440\0443\043a\0446\0438\0438', U&'\0411\0440\0443\0441', 40)
)
INSERT INTO product_subcategories (category, name, sort, is_active)
SELECT pc.id, s.name, s.sort, true
FROM subcategories s
JOIN product_categories pc ON pc.name = s.category_name
WHERE NOT EXISTS (
  SELECT 1
  FROM product_subcategories ps
  WHERE ps.category = pc.id
    AND ps.name = s.name
);

WITH methods(name, sort) AS (VALUES
  (U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', 10),
  (U&'\0421\0442\0440\0443\0439\043d\0430\044f \043f\0435\0447\0430\0442\044c', 20),
  (U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 30),
  (U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 40),
  (U&'\0422\0438\0441\043d\0435\043d\0438\0435', 50),
  (U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 60),
  (U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 70),
  (U&'\0423\0424-\0414\0422\0424 \043f\0435\0447\0430\0442\044c', 80),
  (U&'\0414\0422\0424-\043f\0435\0447\0430\0442\044c', 90),
  (U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', 100),
  (U&'\0412\044b\0448\0438\0432\043a\0430', 110),
  (U&'\041f\043b\0435\043d\043a\0430', 120),
  (U&'\041f\043e\0448\0438\0432', 130)
)
INSERT INTO product_application_methods (name, sort, is_active)
SELECT name, sort, true
FROM methods m
WHERE NOT EXISTS (SELECT 1 FROM product_application_methods pam WHERE pam.name = m.name);

INSERT INTO contractors (name, comment, has_own_view)
SELECT U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f',
       U&'\0412\043d\0443\0442\0440\0435\043d\043d\0435\0435 \043f\043e\0434\0440\0430\0437\0434\0435\043b\0435\043d\0438\0435 \0434\043b\044f \0448\0435\043b\043a\043e\0433\0440\0430\0444\0438\0438',
       true
WHERE NOT EXISTS (
  SELECT 1
    FROM contractors
   WHERE lower(name) = lower(U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f')
);

WITH route_seeds(category_name, method_name, contractor_pattern, priority) AS (VALUES
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', 10),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', 10),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', 10),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', U&'%\043f\0440\043e\0438\0437\0432\043e\0434%', 20),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', U&'%\043f\0440\043e\0438\0437\0432\043e\0434%', 20),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', U&'%\043f\0440\043e\0438\0437\0432\043e\0434%', 20),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\0414\0422\0424 \043f\0435\0447\0430\0442\044c', U&'%\043f\0440\043e\0438\0437\0432\043e\0434%', 20),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%', 10),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', U&'%\043f\0440\043e\0438\0437\0432\043e\0434%', 20)
)
INSERT INTO product_routing_rules (name, product_category, application_method, contractor_1, priority, is_active)
SELECT
  pc.name || ' / ' || pam.name,
  pc.id,
  pam.id,
  c.id,
  rs.priority,
  true
FROM route_seeds rs
JOIN product_categories pc ON pc.name = rs.category_name
JOIN product_application_methods pam ON pam.name = rs.method_name
JOIN LATERAL (
  SELECT id
  FROM contractors
  WHERE name ILIKE rs.contractor_pattern
  ORDER BY id
  LIMIT 1
) c ON true
WHERE NOT EXISTS (
  SELECT 1
  FROM product_routing_rules r
  WHERE r.product_category = pc.id
    AND r.application_method = pam.id
    AND r.product_subcategory IS NULL
);

DO $$
DECLARE
  order_row record;
BEGIN
  FOR order_row IN SELECT DISTINCT "order" AS id FROM orders_items WHERE "order" IS NOT NULL LOOP
    PERFORM symbolika_recalc_order_status_from_items(order_row.id);
  END LOOP;
END;
$$;

UPDATE directus_collections
SET translations = json_build_array(json_build_object('language','ru-RU','translation', label))::json
FROM (VALUES
  ('office_issue', U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'),
  ('office_items_in_office', U&'\0417\0430\043a\0430\0437\044b \0432 \043e\0444\0438\0441\0435'),
  ('office_issue_items', U&'\041f\043e\0437\0438\0446\0438\0438 \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435'),
  ('office_issue_archive', U&'\0410\0440\0445\0438\0432 \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435'),
  ('office_issue_archive_items', U&'\041f\043e\0437\0438\0446\0438\0438 \0430\0440\0445\0438\0432\0430 \0432\044b\0434\0430\0447\0438'),
  ('production_work', U&'\041f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  ('screen_printing_work', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'),
  ('contractor_work', U&'\0420\0430\0431\043e\0442\044b \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\0430')
) AS labels(collection_name, label)
WHERE directus_collections.collection = labels.collection_name;

WITH labels(collection_name, field_name, label) AS (VALUES
  ('office_issue', 'order_number', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430'),
  ('office_issue', 'order_link', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'),
  ('office_issue', 'date', U&'\0414\0430\0442\0430 \0437\0430\043a\0430\0437\0430'),
  ('office_issue', 'deadline', U&'\0421\0440\043e\043a'),
  ('office_issue', 'customer', U&'\041a\043b\0438\0435\043d\0442'),
  ('office_issue', 'customer_name', U&'\041a\043b\0438\0435\043d\0442'),
  ('office_issue', 'customer_phone', U&'\0422\0435\043b\0435\0444\043e\043d \043a\043b\0438\0435\043d\0442\0430'),
  ('office_issue', 'customer_company', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('office_issue', 'customer_company_name', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('office_issue', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('office_issue', 'manager_name', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('office_issue', 'order_status', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430'),
  ('office_issue', 'order_status_name', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430'),
  ('office_issue', 'office_status', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'),
  ('office_issue', 'order_sum', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430'),
  ('office_issue', 'paid_amount', U&'\041e\043f\043b\0430\0447\0435\043d\043e'),
  ('office_issue', 'payment_due', U&'\041e\0441\0442\0430\0442\043e\043a'),
  ('office_issue', 'office_payment_due', U&'\041a \043e\043f\043b\0430\0442\0435 \0432 \043e\0444\0438\0441\0435'),
  ('office_issue', 'add_payment', U&'\0414\043e\0431\0430\0432\0438\0442\044c \043e\043f\043b\0430\0442\0443'),
  ('office_issue', 'overpayment', U&'\041f\0435\0440\0435\043f\043b\0430\0442\0430 / \043a \0432\043e\0437\0432\0440\0430\0442\0443'),
  ('office_issue', 'payment_type', U&'\0422\0438\043f \043e\043f\043b\0430\0442\044b'),
  ('office_issue', 'payment_comment', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439 \043a \043e\043f\043b\0430\0442\0435'),
  ('office_issue', 'order_items', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_items', 'office_issue', U&'\0417\0430\043a\0430\0437'),
  ('office_issue_items', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('office_issue_items', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('office_issue_items', 'office_status', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'),
  ('office_issue_archive', 'order_number', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_archive', 'order_link', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'),
  ('office_issue_archive', 'date', U&'\0414\0430\0442\0430 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_archive', 'deadline', U&'\0421\0440\043e\043a'),
  ('office_issue_archive', 'customer_name', U&'\041a\043b\0438\0435\043d\0442'),
  ('office_issue_archive', 'customer_phone', U&'\0422\0435\043b\0435\0444\043e\043d \043a\043b\0438\0435\043d\0442\0430'),
  ('office_issue_archive', 'customer_company_name', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('office_issue_archive', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('office_issue_archive', 'order_status_name', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_archive', 'office_status', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'),
  ('office_issue_archive', 'order_sum', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_archive', 'paid_amount', U&'\041e\043f\043b\0430\0447\0435\043d\043e'),
  ('office_issue_archive', 'payment_due', U&'\041e\0441\0442\0430\0442\043e\043a'),
  ('office_issue_archive', 'office_payment_due', U&'\041a \043e\043f\043b\0430\0442\0435 \0432 \043e\0444\0438\0441\0435'),
  ('office_issue_archive', 'overpayment', U&'\041f\0435\0440\0435\043f\043b\0430\0442\0430 / \043a \0432\043e\0437\0432\0440\0430\0442\0443'),
  ('office_issue_archive', 'order_items', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\0430'),
  ('office_issue_archive_items', 'office_issue', U&'\0417\0430\043a\0430\0437'),
  ('office_issue_archive_items', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('office_issue_archive_items', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('office_issue_archive_items', 'office_status', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'),
  ('office_items_in_office', 'order', U&'\0417\0430\043a\0430\0437'),
  ('office_items_in_office', 'order_number', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430'),
  ('office_items_in_office', 'office_issue', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'),
  ('office_items_in_office', 'customer', U&'\041a\043b\0438\0435\043d\0442'),
  ('office_items_in_office', 'customer_name', U&'\041a\043b\0438\0435\043d\0442'),
  ('office_items_in_office', 'customer_company', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('office_items_in_office', 'customer_company_name', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('office_items_in_office', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('office_items_in_office', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('office_items_in_office', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('office_items_in_office', 'office_status', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'),
  ('production_work', 'order', U&'\0417\0430\043a\0430\0437'),
  ('production_work', 'customer', U&'\0417\0430\043a\0430\0437\0447\0438\043a'),
  ('production_work', 'customer_company', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('production_work', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('production_work', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435 \043f\043e\0437\0438\0446\0438\0438'),
  ('production_work', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('production_work', 'deadline', U&'\0421\0440\043e\043a \043f\043e\0437\0438\0446\0438\0438'),
  ('production_work', 'technical_task_text', U&'\0422\0417'),
  ('production_work', 'production_comment', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'),
  ('production_work', 'url', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'),
  ('production_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430'),
  ('screen_printing_work', 'order', U&'\0417\0430\043a\0430\0437'),
  ('screen_printing_work', 'customer', U&'\0417\0430\043a\0430\0437\0447\0438\043a'),
  ('screen_printing_work', 'customer_company', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('screen_printing_work', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('screen_printing_work', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435 \043f\043e\0437\0438\0446\0438\0438'),
  ('screen_printing_work', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('screen_printing_work', 'deadline', U&'\0421\0440\043e\043a \043f\043e\0437\0438\0446\0438\0438'),
  ('screen_printing_work', 'technical_task_text', U&'\0422\0417'),
  ('screen_printing_work', 'production_comment', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'),
  ('screen_printing_work', 'url', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'),
  ('screen_printing_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430'),
  ('contractors', 'has_own_view', U&'\0421\0432\043e\0435 \043f\0440\0435\0434\0441\0442\0430\0432\043b\0435\043d\0438\0435'),
  ('contractors', 'directus_user', U&'\041f\043e\043b\044c\0437\043e\0432\0430\0442\0435\043b\044c Directus'),
  ('contractors', 'default_product_category', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f \043f\043e \0443\043c\043e\043b\0447\0430\043d\0438\044e'),
  ('contractors', 'default_product_subcategory', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f \043f\043e \0443\043c\043e\043b\0447\0430\043d\0438\044e'),
  ('contractor_work', 'order', U&'\0417\0430\043a\0430\0437'),
  ('contractor_work', 'order_link', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'),
  ('contractor_work', 'contractor', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442'),
  ('contractor_work', 'customer', U&'\0417\0430\043a\0430\0437\0447\0438\043a'),
  ('contractor_work', 'customer_company', U&'\041a\043e\043c\043f\0430\043d\0438\044f'),
  ('contractor_work', 'manager_employee', U&'\041c\0435\043d\0435\0434\0436\0435\0440'),
  ('contractor_work', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('contractor_work', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('contractor_work', 'deadline', U&'\0421\0440\043e\043a'),
  ('contractor_work', 'technical_task_text', U&'\0422\0417'),
  ('contractor_work', 'production_comment', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'),
  ('contractor_work', 'url', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'),
  ('contractor_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430')
)
UPDATE directus_fields df
SET translations = json_build_array(json_build_object('language','ru-RU','translation', labels.label))::json
FROM labels
WHERE df.collection = labels.collection_name AND df.field = labels.field_name;

UPDATE directus_fields
SET readonly = false,
    hidden = false,
    interface = 'input-multiline',
    translations = json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0417'))::json
WHERE collection = 'orders_items'
  AND field = 'technical_task_text';

UPDATE directus_fields
SET options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued')
    ))::json,
    display_options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued')
    ))::json
WHERE collection IN ('office_issue','office_issue_items','office_issue_archive','office_issue_archive_items','office_items_in_office') AND field = 'office_status';

UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office', 'foreground', '#F8FAFC', 'background', '#64748B'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office', 'foreground', '#111827', 'background', '#F59E0B'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued', 'foreground', '#F8FAFC', 'background', '#16A34A')
    ))::json
WHERE collection IN ('orders','orders_items','office_issue','office_issue_items','office_issue_archive','office_issue_archive_items','office_items_in_office','my_orders_in_work','my_orders_completed','my_orders_unpaid')
  AND field = 'office_status';

UPDATE directus_fields
SET options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\043e\0432\044b\0439', 'value', 'new'),
      jsonb_build_object('text', U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 'value', 'approval'),
      jsonb_build_object('text', U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 'value', 'layout_revision'),
      jsonb_build_object('text', U&'\0412 \0440\0430\0431\043e\0442\0435', 'value', 'in_work'),
      jsonb_build_object('text', U&'\0413\043e\0442\043e\0432', 'value', 'ready'),
      jsonb_build_object('text', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 'value', 'delivered'),
      jsonb_build_object('text', U&'\041e\0442\043c\0435\043d\0435\043d', 'value', 'cancelled')
    ))::json,
    display = 'labels',
    display_options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\043e\0432\044b\0439', 'value', 'new', 'foreground', '#111827', 'background', '#FBBF24'),
      jsonb_build_object('text', U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 'value', 'approval', 'foreground', '#111827', 'background', '#FBBF24'),
      jsonb_build_object('text', U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 'value', 'layout_revision', 'foreground', '#F8FAFC', 'background', '#A855F7'),
      jsonb_build_object('text', U&'\0412 \0440\0430\0431\043e\0442\0435', 'value', 'in_work', 'foreground', '#F8FAFC', 'background', '#3B82F6'),
      jsonb_build_object('text', U&'\0413\043e\0442\043e\0432', 'value', 'ready', 'foreground', '#F8FAFC', 'background', '#16A34A'),
      jsonb_build_object('text', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 'value', 'delivered', 'foreground', '#F8FAFC', 'background', '#0F766E'),
      jsonb_build_object('text', U&'\041e\0442\043c\0435\043d\0435\043d', 'value', 'cancelled', 'foreground', '#F8FAFC', 'background', '#DC2626')
    ))::json
WHERE collection = 'orders_items'
  AND field = 'item_status';

WITH order_status_choices AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'text', name,
      'value', id,
      'foreground', CASE
        WHEN name IN (U&'\041d\043e\0432\044b\0439', U&'\0413\043e\0442\043e\0432') THEN '#111827'
        ELSE '#F8FAFC'
      END,
      'background', CASE
        WHEN name = U&'\041d\043e\0432\044b\0439' THEN '#FBBF24'
        WHEN name = U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435' THEN '#F59E0B'
        WHEN name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN '#A855F7'
        WHEN name = U&'\0412 \0440\0430\0431\043e\0442\0435' THEN '#3B82F6'
        WHEN name = U&'\0413\043e\0442\043e\0432' THEN '#22C55E'
        WHEN name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN '#16A34A'
        WHEN name = U&'\041e\0442\043c\0435\043d\0435\043d' THEN '#DC2626'
        ELSE '#64748B'
      END
    )
    ORDER BY COALESCE(sort, id), id
  ) AS choices
  FROM order_statuses
)
UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', order_status_choices.choices)::json
FROM order_status_choices
WHERE collection IN ('orders', 'office_issue', 'my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid', 'customer_reconciliation')
  AND field = 'order_status';

WITH production_status_choices AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'text', name,
      'value', id,
      'foreground', CASE
        WHEN name = U&'\0413\043e\0442\043e\0432' THEN '#111827'
        ELSE '#F8FAFC'
      END,
      'background', CASE
        WHEN name = U&'\041d\0435 \0432 \0440\0430\0431\043e\0442\0435' THEN '#64748B'
        WHEN name = U&'\0412 \0440\0430\0431\043e\0442\0435' THEN '#3B82F6'
        WHEN name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN '#A855F7'
        WHEN name = U&'\0413\043e\0442\043e\0432' THEN '#FBBF24'
        WHEN name = U&'\041e\0442\043c\0435\043d\0435\043d' THEN '#DC2626'
        ELSE '#0F766E'
      END
    )
    ORDER BY COALESCE(sort, id), id
  ) AS choices
  FROM production_statuses
)
UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', production_status_choices.choices)::json
FROM production_status_choices
WHERE collection IN (
  'orders_items',
  'production_work',
  'screen_printing_work',
  'contractor_work',
  'my_orders_in_work_items',
  'my_orders_completed_items',
  'my_orders_unpaid_items'
)
  AND field = 'production_status';

DROP TRIGGER IF EXISTS symbolika_sync_orders_overview_order ON orders;
DROP TRIGGER IF EXISTS symbolika_sync_orders_overview_item ON orders_items;
DROP TRIGGER IF EXISTS symbolika_sync_my_order_buckets_order ON orders;
DROP TRIGGER IF EXISTS symbolika_sync_my_order_buckets_item ON orders_items;
DROP TRIGGER IF EXISTS symbolika_sync_my_order_buckets_payment ON order_payments;
DROP TRIGGER IF EXISTS symbolika_refresh_orders_due_on_user_page ON directus_users;

DO $$
DECLARE
  obj record;
BEGIN
  FOR obj IN
    SELECT c.relname, c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'orders_due_today',
        'orders_due_this_week',
        'orders_due_next_week',
        'orders_due_this_month',
        'orders_due_urgent',
        'orders_due_next_month'
      )
  LOOP
    IF obj.relkind = 'v' THEN
      EXECUTE format('DROP VIEW %I CASCADE', obj.relname);
    END IF;
  END LOOP;
END;
$$;

CREATE TABLE IF NOT EXISTS orders_overview (
  id integer PRIMARY KEY,
  order_link integer,
  order_number character varying(255),
  date timestamp without time zone,
  deadline timestamp without time zone,
  customer_display character varying(255),
  manager_name character varying(255),
  shipping_method character varying(255),
  shipping_method_name character varying(255),
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2)
);

CREATE TABLE IF NOT EXISTS orders_overview_items (
  id integer PRIMARY KEY,
  orders_overview integer,
  product_name character varying(255),
  quantity integer
);

CREATE TABLE IF NOT EXISTS customer_reconciliation (
  id integer PRIMARY KEY,
  order_link integer,
  order_number character varying(255),
  date timestamp without time zone,
  deadline timestamp without time zone,
  customer integer,
  customer_name character varying(255),
  customer_company integer,
  customer_company_name character varying(255),
  counterparty_name character varying(255),
  manager_employee integer,
  manager_name character varying(255),
  order_status integer,
  order_status_name character varying(255),
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2),
  overpayment numeric(10,2),
  customer_debt_to_us numeric(10,2),
  our_debt_to_customer numeric(10,2),
  reconciliation_result character varying(255)
);

CREATE TABLE IF NOT EXISTS orders_due_today (LIKE orders_overview INCLUDING ALL);
CREATE TABLE IF NOT EXISTS orders_due_this_week (LIKE orders_overview INCLUDING ALL);
CREATE TABLE IF NOT EXISTS orders_due_next_week (LIKE orders_overview INCLUDING ALL);
CREATE TABLE IF NOT EXISTS orders_due_this_month (LIKE orders_overview INCLUDING ALL);
CREATE TABLE IF NOT EXISTS orders_due_urgent (LIKE orders_overview INCLUDING ALL);
CREATE TABLE IF NOT EXISTS orders_due_next_month (LIKE orders_overview INCLUDING ALL);

CREATE TABLE IF NOT EXISTS my_orders_in_work (
  id integer PRIMARY KEY,
  order_link integer,
  order_number character varying(255),
  date timestamp without time zone,
  deadline timestamp without time zone,
  customer_display character varying(255),
  manager_employee integer,
  manager_name character varying(255),
  order_status integer,
  order_status_name character varying(255),
  office_status character varying(255),
  shipping_method character varying(255),
  shipping_method_name character varying(255),
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2)
);

CREATE TABLE IF NOT EXISTS my_orders_completed (LIKE my_orders_in_work INCLUDING ALL);
CREATE TABLE IF NOT EXISTS my_orders_unpaid (LIKE my_orders_in_work INCLUDING ALL);

CREATE TABLE IF NOT EXISTS my_orders_in_work_items (
  id integer PRIMARY KEY,
  bucket_order integer,
  product_name character varying(255),
  quantity integer,
  deadline timestamp without time zone,
  item_status character varying(255),
  production_status integer,
  office_status character varying(255)
);

CREATE TABLE IF NOT EXISTS my_orders_completed_items (LIKE my_orders_in_work_items INCLUDING ALL);
CREATE TABLE IF NOT EXISTS my_orders_unpaid_items (LIKE my_orders_in_work_items INCLUDING ALL);

ALTER TABLE my_orders_in_work_items ADD COLUMN IF NOT EXISTS deadline timestamp without time zone;
ALTER TABLE my_orders_in_work_items ADD COLUMN IF NOT EXISTS item_status character varying(255);
ALTER TABLE my_orders_in_work_items ADD COLUMN IF NOT EXISTS production_status integer;
ALTER TABLE my_orders_in_work_items ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE my_orders_completed_items ADD COLUMN IF NOT EXISTS deadline timestamp without time zone;
ALTER TABLE my_orders_completed_items ADD COLUMN IF NOT EXISTS item_status character varying(255);
ALTER TABLE my_orders_completed_items ADD COLUMN IF NOT EXISTS production_status integer;
ALTER TABLE my_orders_completed_items ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE my_orders_unpaid_items ADD COLUMN IF NOT EXISTS deadline timestamp without time zone;
ALTER TABLE my_orders_unpaid_items ADD COLUMN IF NOT EXISTS item_status character varying(255);
ALTER TABLE my_orders_unpaid_items ADD COLUMN IF NOT EXISTS production_status integer;
ALTER TABLE my_orders_unpaid_items ADD COLUMN IF NOT EXISTS office_status character varying(255);

CREATE TABLE IF NOT EXISTS my_orders_in_work_payments (
  id integer PRIMARY KEY,
  bucket_order integer,
  amount numeric(10,2),
  allocated_amount numeric(10,2),
  unallocated_amount numeric(10,2),
  payment_date date,
  payment_type_name character varying(255),
  comment text
);

CREATE TABLE IF NOT EXISTS my_orders_completed_payments (LIKE my_orders_in_work_payments INCLUDING ALL);
CREATE TABLE IF NOT EXISTS my_orders_unpaid_payments (LIKE my_orders_in_work_payments INCLUDING ALL);

ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS customer_debt_to_us numeric(10,2);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS our_debt_to_customer numeric(10,2);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS reconciliation_result character varying(255);
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS order_link integer;

CREATE OR REPLACE FUNCTION refresh_orders_due_tables()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM orders_due_today;
  DELETE FROM orders_due_this_week;
  DELETE FROM orders_due_next_week;
  DELETE FROM orders_due_this_month;
  DELETE FROM orders_due_urgent;
  DELETE FROM orders_due_next_month;

  INSERT INTO orders_due_urgent
  SELECT *
  FROM orders_overview
  WHERE deadline < CURRENT_DATE + INTERVAL '1 day';

  INSERT INTO orders_due_today
  SELECT *
  FROM orders_overview
  WHERE deadline >= CURRENT_DATE
    AND deadline < CURRENT_DATE + INTERVAL '1 day';

  INSERT INTO orders_due_this_week
  SELECT *
  FROM orders_overview
  WHERE deadline >= date_trunc('week', CURRENT_DATE)::date
    AND deadline < date_trunc('week', CURRENT_DATE)::date + INTERVAL '7 days';

  INSERT INTO orders_due_next_week
  SELECT *
  FROM orders_overview
  WHERE deadline >= date_trunc('week', CURRENT_DATE)::date + INTERVAL '7 days'
    AND deadline < date_trunc('week', CURRENT_DATE)::date + INTERVAL '14 days';

  INSERT INTO orders_due_this_month
  SELECT *
  FROM orders_overview
  WHERE deadline >= date_trunc('month', CURRENT_DATE)::date
    AND deadline < date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month';

  INSERT INTO orders_due_next_month
  SELECT *
  FROM orders_overview
  WHERE deadline >= date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
    AND deadline < date_trunc('month', CURRENT_DATE)::date + INTERVAL '2 months';
END;
$$;

CREATE OR REPLACE FUNCTION refresh_customer_reconciliation()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM customer_reconciliation;

  INSERT INTO customer_reconciliation (
    id, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name,
    order_sum, paid_amount, payment_due, overpayment,
    customer_debt_to_us, our_debt_to_customer, reconciliation_result
  )
  SELECT
    o.id,
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    c.name,
    o.customer_company,
    cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
    o.manager_employee,
    e.full_name,
    o.order_status,
    os.name,
    COALESCE(o.order_sum, 0),
    COALESCE(o.paid_amount, 0),
    COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    GREATEST(COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    GREATEST(-COALESCE(o.payment_due, 0), 0)::numeric(10,2),
    CASE
      WHEN COALESCE(o.payment_due, 0) > 0 THEN U&'\041a\043b\0438\0435\043d\0442 \0434\043e\043b\0436\0435\043d'
      WHEN COALESCE(o.payment_due, 0) < 0 THEN U&'\041c\044b \0434\043e\043b\0436\043d\044b'
      ELSE U&'\0420\0430\0441\0447\0435\0442 \0437\0430\043a\0440\044b\0442'
    END
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status;
END;
$$;

CREATE OR REPLACE FUNCTION sync_my_order_buckets(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  order_row record;
  is_completed boolean;
  is_unpaid boolean;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('sync_my_order_buckets'), order_id) THEN
    RETURN;
  END IF;

  DELETE FROM my_orders_in_work_items
  WHERE bucket_order = order_id OR id IN (SELECT oi.id FROM orders_items oi WHERE oi."order" = order_id);
  DELETE FROM my_orders_completed_items
  WHERE bucket_order = order_id OR id IN (SELECT oi.id FROM orders_items oi WHERE oi."order" = order_id);
  DELETE FROM my_orders_unpaid_items
  WHERE bucket_order = order_id OR id IN (SELECT oi.id FROM orders_items oi WHERE oi."order" = order_id);
  DELETE FROM my_orders_in_work_payments
  WHERE bucket_order = order_id OR id IN (SELECT op.id FROM order_payments op WHERE op."order" = order_id);
  DELETE FROM my_orders_completed_payments
  WHERE bucket_order = order_id OR id IN (SELECT op.id FROM order_payments op WHERE op."order" = order_id);
  DELETE FROM my_orders_unpaid_payments
  WHERE bucket_order = order_id OR id IN (SELECT op.id FROM order_payments op WHERE op."order" = order_id);
  DELETE FROM my_orders_in_work WHERE id = order_id;
  DELETE FROM my_orders_completed WHERE id = order_id;
  DELETE FROM my_orders_unpaid WHERE id = order_id;

  SELECT
    o.*,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430') AS customer_display,
    e.full_name AS manager_name,
    os.name AS order_status_name,
    CASE o.shipping_method
      WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
      WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
      WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
      ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
    END AS shipping_method_name
  INTO order_row
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE o.id = order_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  is_completed := order_row.office_status = 'issued'
    OR order_row.order_status_name IN (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', U&'\041e\0442\043c\0435\043d\0435\043d');
  is_unpaid := COALESCE(order_row.payment_due, 0) > 0;

  IF is_completed THEN
    INSERT INTO my_orders_completed (
      id, order_number, date, deadline, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name,
      order_sum, paid_amount, payment_due
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due
    );
  ELSE
    INSERT INTO my_orders_in_work (
      id, order_number, date, deadline, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name,
      order_sum, paid_amount, payment_due
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due
    );
  END IF;

  IF is_unpaid THEN
    INSERT INTO my_orders_unpaid (
      id, order_number, date, deadline, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name,
      order_sum, paid_amount, payment_due
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due
    );
  END IF;

  UPDATE my_orders_completed
  SET order_link = id
  WHERE id = order_id;

  UPDATE my_orders_in_work
  SET order_link = id
  WHERE id = order_id;

  UPDATE my_orders_unpaid
  SET order_link = id
  WHERE id = order_id;

  INSERT INTO my_orders_completed_items (
    id, bucket_order, product_name, quantity, deadline, item_status, production_status, office_status
  )
  SELECT oi.id, oi."order", oi.product_name, oi.quantity, oi.deadline, oi.item_status, oi.production_status, oi.office_status
  FROM orders_items oi
  WHERE oi."order" = order_id AND is_completed
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    deadline = EXCLUDED.deadline,
    item_status = EXCLUDED.item_status,
    production_status = EXCLUDED.production_status,
    office_status = EXCLUDED.office_status;

  INSERT INTO my_orders_in_work_items (
    id, bucket_order, product_name, quantity, deadline, item_status, production_status, office_status
  )
  SELECT oi.id, oi."order", oi.product_name, oi.quantity, oi.deadline, oi.item_status, oi.production_status, oi.office_status
  FROM orders_items oi
  WHERE oi."order" = order_id AND NOT is_completed
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    deadline = EXCLUDED.deadline,
    item_status = EXCLUDED.item_status,
    production_status = EXCLUDED.production_status,
    office_status = EXCLUDED.office_status;

  INSERT INTO my_orders_unpaid_items (
    id, bucket_order, product_name, quantity, deadline, item_status, production_status, office_status
  )
  SELECT oi.id, oi."order", oi.product_name, oi.quantity, oi.deadline, oi.item_status, oi.production_status, oi.office_status
  FROM orders_items oi
  WHERE oi."order" = order_id AND is_unpaid
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    deadline = EXCLUDED.deadline,
    item_status = EXCLUDED.item_status,
    production_status = EXCLUDED.production_status,
    office_status = EXCLUDED.office_status;

  INSERT INTO my_orders_completed_payments (
    id, bucket_order, amount, allocated_amount, unallocated_amount, payment_date, payment_type_name, comment
  )
  SELECT
    op.id,
    op."order",
    op.amount,
    op.allocated_amount,
    op.unallocated_amount,
    op.payment_date,
    pt.name,
    op.comment
  FROM order_payments op
  LEFT JOIN payment_types pt ON pt.id = op.payment_type
  WHERE op."order" = order_id AND is_completed
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    amount = EXCLUDED.amount,
    allocated_amount = EXCLUDED.allocated_amount,
    unallocated_amount = EXCLUDED.unallocated_amount,
    payment_date = EXCLUDED.payment_date,
    payment_type_name = EXCLUDED.payment_type_name,
    comment = EXCLUDED.comment;

  INSERT INTO my_orders_in_work_payments (
    id, bucket_order, amount, allocated_amount, unallocated_amount, payment_date, payment_type_name, comment
  )
  SELECT
    op.id,
    op."order",
    op.amount,
    op.allocated_amount,
    op.unallocated_amount,
    op.payment_date,
    pt.name,
    op.comment
  FROM order_payments op
  LEFT JOIN payment_types pt ON pt.id = op.payment_type
  WHERE op."order" = order_id AND NOT is_completed
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    amount = EXCLUDED.amount,
    allocated_amount = EXCLUDED.allocated_amount,
    unallocated_amount = EXCLUDED.unallocated_amount,
    payment_date = EXCLUDED.payment_date,
    payment_type_name = EXCLUDED.payment_type_name,
    comment = EXCLUDED.comment;

  INSERT INTO my_orders_unpaid_payments (
    id, bucket_order, amount, allocated_amount, unallocated_amount, payment_date, payment_type_name, comment
  )
  SELECT
    op.id,
    op."order",
    op.amount,
    op.allocated_amount,
    op.unallocated_amount,
    op.payment_date,
    pt.name,
    op.comment
  FROM order_payments op
  LEFT JOIN payment_types pt ON pt.id = op.payment_type
  WHERE op."order" = order_id AND is_unpaid
  ON CONFLICT (id) DO UPDATE SET
    bucket_order = EXCLUDED.bucket_order,
    amount = EXCLUDED.amount,
    allocated_amount = EXCLUDED.allocated_amount,
    unallocated_amount = EXCLUDED.unallocated_amount,
    payment_date = EXCLUDED.payment_date,
    payment_type_name = EXCLUDED.payment_type_name,
    comment = EXCLUDED.comment;
END;
$$;

CREATE OR REPLACE FUNCTION sync_my_order_buckets_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM my_orders_in_work_items WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_completed_items WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_unpaid_items WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_in_work_payments WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_completed_payments WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_unpaid_payments WHERE bucket_order = OLD.id;
    DELETE FROM my_orders_in_work WHERE id = OLD.id;
    DELETE FROM my_orders_completed WHERE id = OLD.id;
    DELETE FROM my_orders_unpaid WHERE id = OLD.id;
    RETURN OLD;
  END IF;

  PERFORM sync_my_order_buckets(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_my_order_buckets_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM sync_my_order_buckets(OLD."order");
    RETURN OLD;
  END IF;

  PERFORM sync_my_order_buckets(NEW."order");
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_my_order_buckets_payment_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD."order" IS NOT NULL THEN
      PERFORM sync_my_order_buckets(OLD."order");
    END IF;
    RETURN OLD;
  END IF;

  IF NEW."order" IS NOT NULL THEN
    PERFORM sync_my_order_buckets(NEW."order");
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD."order" IS NOT NULL
     AND OLD."order" IS DISTINCT FROM NEW."order" THEN
    PERFORM sync_my_order_buckets(OLD."order");
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_orders_overview(order_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM orders_overview_items WHERE orders_overview = order_id;
  DELETE FROM orders_overview WHERE id = order_id;

  INSERT INTO orders_overview (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due
  )
  SELECT
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
    e.full_name,
    o.shipping_method,
    CASE o.shipping_method
      WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
      WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
      WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
      ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
    END,
    o.order_sum,
    o.paid_amount,
    o.payment_due
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  WHERE o.id = order_id;

  UPDATE orders_overview
  SET order_link = id
  WHERE id = order_id;

  INSERT INTO orders_overview_items (
    id, orders_overview, product_name, quantity
  )
  SELECT
    oi.id,
    oi."order",
    oi.product_name,
    oi.quantity
  FROM orders_items oi
  WHERE oi."order" = order_id
    AND EXISTS (SELECT 1 FROM orders_overview oo WHERE oo.id = order_id);

  PERFORM refresh_orders_due_tables();
  PERFORM refresh_customer_reconciliation();
END;
$$;

CREATE OR REPLACE FUNCTION sync_orders_overview_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  item record;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM orders_overview_items WHERE orders_overview = OLD.id;
    DELETE FROM orders_overview WHERE id = OLD.id;
    RETURN OLD;
  END IF;

  PERFORM sync_orders_overview(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_orders_overview_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM orders_overview_items WHERE id = OLD.id;
    PERFORM sync_orders_overview(OLD."order");
    RETURN OLD;
  END IF;

  PERFORM sync_orders_overview(NEW."order");
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_sync_orders_overview_order
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_orders_overview_order_trigger();

CREATE TRIGGER symbolika_sync_orders_overview_item
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_orders_overview_item_trigger();

CREATE TRIGGER symbolika_sync_my_order_buckets_order
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_my_order_buckets_order_trigger();

CREATE TRIGGER symbolika_sync_my_order_buckets_item
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_my_order_buckets_item_trigger();

CREATE TRIGGER symbolika_sync_my_order_buckets_payment
AFTER INSERT OR UPDATE OR DELETE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION sync_my_order_buckets_payment_trigger();

CREATE OR REPLACE FUNCTION refresh_orders_due_on_user_page_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM refresh_orders_due_tables();
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_refresh_orders_due_on_user_page
AFTER UPDATE OF last_page ON directus_users
FOR EACH ROW
WHEN (OLD.last_page IS DISTINCT FROM NEW.last_page)
EXECUTE FUNCTION refresh_orders_due_on_user_page_trigger();

DELETE FROM orders_overview_items;
DELETE FROM orders_overview;
INSERT INTO orders_overview (
  id, order_number, date, deadline, customer_display, manager_name,
  shipping_method, shipping_method_name, order_sum, paid_amount, payment_due
)
SELECT
  o.id,
  o.order_number,
  o.date,
  o.deadline,
  COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
  e.full_name,
  o.shipping_method,
  CASE o.shipping_method
    WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
    WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
    WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
    ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
  END,
  o.order_sum,
  o.paid_amount,
  o.payment_due
FROM orders o
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN employees e ON e.id = o.manager_employee;

UPDATE orders_overview
SET order_link = id;

INSERT INTO orders_overview_items (
  id, orders_overview, product_name, quantity
)
SELECT
  oi.id,
  oi."order",
  oi.product_name,
  oi.quantity
FROM orders_items oi
WHERE EXISTS (SELECT 1 FROM orders_overview oo WHERE oo.id = oi."order");

SELECT refresh_orders_due_tables();
SELECT refresh_customer_reconciliation();

DELETE FROM my_orders_in_work_items;
DELETE FROM my_orders_completed_items;
DELETE FROM my_orders_unpaid_items;
DELETE FROM my_orders_in_work_payments;
DELETE FROM my_orders_completed_payments;
DELETE FROM my_orders_unpaid_payments;
DELETE FROM my_orders_in_work;
DELETE FROM my_orders_completed;
DELETE FROM my_orders_unpaid;

SELECT sync_my_order_buckets(id)
FROM orders;

UPDATE directus_collections
SET translations = '[{"language":"ru-RU","translation":"\u041c\u043e\u0438 \u0437\u0430\u043a\u0430\u0437\u044b"}]'::json
WHERE collection = 'orders';

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, translations,
  archive_app_filter, accountability, sort, "group", collapse, versioning
) VALUES
  ('orders_overview', 'assignment', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u0417\u0430\u043a\u0430\u0437\u044b"}]'::json, true, 'all', 1, NULL, 'open', false),
  ('orders_due_urgent', 'priority_high', NULL, '{{order_number}}', false, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\0413\043e\0440\044f\0449\0438\0435 \0437\0430\043a\0430\0437\044b'))::json, true, 'all', 1, 'orders_overview', 'open', false),
  ('orders_due_today', 'today', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u0421\u0435\u0433\u043e\u0434\u043d\u044f"}]'::json, true, 'all', 2, 'orders_overview', 'open', false),
  ('orders_due_this_week', 'calendar_view_week', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u041d\u0430 \u044d\u0442\u043e\u0439 \u043d\u0435\u0434\u0435\u043b\u0435"}]'::json, true, 'all', 3, 'orders_overview', 'open', false),
  ('orders_due_next_week', 'next_week', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u041d\u0430 \u0441\u043b\u0435\u0434\u0443\u044e\u0449\u0435\u0439 \u043d\u0435\u0434\u0435\u043b\u0435"}]'::json, true, 'all', 4, 'orders_overview', 'open', false),
  ('orders_due_this_month', 'calendar_month', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u0412 \u044d\u0442\u043e\u043c \u043c\u0435\u0441\u044f\u0446\u0435"}]'::json, true, 'all', 5, 'orders_overview', 'open', false),
  ('orders_due_next_month', 'event_upcoming', NULL, '{{order_number}}', false, false, '[{"language":"ru-RU","translation":"\u0412 \u0441\u043b\u0435\u0434\u0443\u044e\u0449\u0435\u043c \u043c\u0435\u0441\u044f\u0446\u0435"}]'::json, true, 'all', 6, 'orders_overview', 'open', false),
  ('orders_overview_items', 'format_list_bulleted', NULL, '{{product_name}}', true, false, '[{"language":"ru-RU","translation":"\u041f\u043e\u0437\u0438\u0446\u0438\u0438 \u0441\u0432\u043e\u0434\u043a\u0438 \u0437\u0430\u043a\u0430\u0437\u043e\u0432"}]'::json, true, 'all', 1, NULL, 'open', false),
  ('customer_reconciliation', 'request_quote', NULL, '{{order_number}}', false, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0432\0435\0440\043a\0430 \043f\043e \043a\043b\0438\0435\043d\0442\0430\043c'))::json, true, 'all', 7, 'orders_overview', 'open', false),
  ('my_orders_in_work', 'work_history', NULL, '{{order_number}}', false, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437\044b \0432 \0440\0430\0431\043e\0442\0435'))::json, true, 'all', 1, 'orders', 'open', false),
  ('my_orders_completed', 'task_alt', NULL, '{{order_number}}', false, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\0432\0435\0440\0448\0435\043d\043d\044b\0435 \0437\0430\043a\0430\0437\044b'))::json, true, 'all', 2, 'orders', 'open', false),
  ('my_orders_unpaid', 'payments', NULL, '{{order_number}}', false, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0435 \0437\0430\043a\0430\0437\044b'))::json, true, 'all', 3, 'orders', 'open', false),
  ('my_orders_in_work_items', 'format_list_bulleted', NULL, '{{product_name}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\043e\0432 \0432 \0440\0430\0431\043e\0442\0435'))::json, true, 'all', 1, NULL, 'open', false),
  ('my_orders_completed_items', 'format_list_bulleted', NULL, '{{product_name}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\0432\0435\0440\0448\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432'))::json, true, 'all', 1, NULL, 'open', false),
  ('my_orders_unpaid_items', 'format_list_bulleted', NULL, '{{product_name}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \043d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432'))::json, true, 'all', 1, NULL, 'open', false),
  ('my_orders_in_work_payments', 'payments', NULL, '{{amount}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\044b \0437\0430\043a\0430\0437\043e\0432 \0432 \0440\0430\0431\043e\0442\0435'))::json, true, 'all', 1, NULL, 'open', false),
  ('my_orders_completed_payments', 'payments', NULL, '{{amount}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\044b \0437\0430\0432\0435\0440\0448\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432'))::json, true, 'all', 1, NULL, 'open', false),
  ('my_orders_unpaid_payments', 'payments', NULL, '{{amount}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\044b \043d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432'))::json, true, 'all', 1, NULL, 'open', false)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  translations = EXCLUDED.translations,
  sort = EXCLUDED.sort,
  "group" = EXCLUDED."group",
  collapse = EXCLUDED.collapse;

DELETE FROM directus_fields
WHERE collection IN (
  'orders_overview',
  'orders_due_today',
  'orders_due_this_week',
  'orders_due_next_week',
  'orders_due_this_month',
  'orders_due_urgent',
  'orders_due_next_month',
  'customer_reconciliation',
  'orders_overview_items',
  'my_orders_in_work',
  'my_orders_completed',
  'my_orders_unpaid',
  'my_orders_in_work_items',
  'my_orders_completed_items',
  'my_orders_unpaid_items',
  'my_orders_in_work_payments',
  'my_orders_completed_payments',
  'my_orders_unpaid_payments'
);

WITH summary_collections(collection_name) AS (VALUES
  ('orders_overview'),
  ('orders_due_today'),
  ('orders_due_this_week'),
  ('orders_due_next_week'),
  ('orders_due_this_month'),
  ('orders_due_urgent'),
  ('orders_due_next_month')
),
summary_fields(field_name, interface_name, sort_order, width_value, label, hidden_value) AS (VALUES
  ('id', 'numeric', 1, 'full', NULL, true),
  ('order_link', 'symbolika-order-link', 2, 'half', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437', false),
  ('order_number', 'input', 3, 'half', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430', false),
  ('date', 'datetime', 4, 'half', U&'\0414\0430\0442\0430', false),
  ('deadline', 'datetime', 5, 'half', U&'\0421\0440\043e\043a', false),
  ('customer_display', 'input', 6, 'half', U&'\0417\0430\043a\0430\0437\0447\0438\043a', false),
  ('manager_name', 'input', 7, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440 \0437\0430\043a\0430\0437\0430', false),
  ('shipping_method', 'input', 8, 'half', U&'\0421\043f\043e\0441\043e\0431 \043e\0442\0433\0440\0443\0437\043a\0438', true),
  ('shipping_method_name', 'input', 9, 'half', U&'\0413\0434\0435 \0432\044b\0434\0430\0447\0430', false),
  ('order_sum', 'input', 10, 'half', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430', false),
  ('paid_amount', 'input', 11, 'half', U&'\0421\0443\043c\043c\0430 \043e\043f\043b\0430\0442\044b', false),
  ('payment_due', 'input', 12, 'half', U&'\0421\0443\043c\043c\0430 \0434\043e\043f\043b\0430\0442\044b', false),
  ('order_items', 'list-o2m', 13, 'full', U&'\041f\043e\0437\0438\0446\0438\0438', false)
)
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  summary_collections.collection_name,
  summary_fields.field_name,
  CASE WHEN summary_fields.field_name = 'order_items' THEN 'o2m' ELSE NULL END,
  summary_fields.interface_name,
  CASE WHEN summary_fields.field_name = 'order_items'
    THEN '{"layout":"table","tableSpacing":"compact","fields":["product_name","quantity"],"enableCreate":false,"enableSelect":false}'::json
    ELSE NULL
  END,
  NULL,
  NULL,
  true,
  summary_fields.hidden_value,
  summary_fields.sort_order,
  summary_fields.width_value,
  CASE WHEN summary_fields.label IS NULL
    THEN NULL
    ELSE json_build_array(json_build_object('language','ru-RU','translation', summary_fields.label))::json
  END,
  false,
  true
FROM summary_collections
CROSS JOIN summary_fields;

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'customer_reconciliation',
  fields.field_name,
  fields.special_value,
  fields.interface_name,
  fields.options_value,
  fields.display_value,
  fields.display_options_value,
  true,
  fields.hidden_value,
  fields.sort_order,
  fields.width_value,
  CASE WHEN fields.label IS NULL
    THEN NULL
    ELSE json_build_array(json_build_object('language','ru-RU','translation', fields.label))::json
  END,
  false,
  true
FROM (VALUES
  ('id', NULL, 'numeric', NULL::json, NULL, NULL::json, 1, 'full', NULL, true),
  ('order_link', NULL, 'symbolika-order-link', NULL::json, NULL, NULL::json, 2, 'half', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437', false),
  ('order_number', NULL, 'input', NULL::json, NULL, NULL::json, 3, 'half', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430', false),
  ('counterparty_name', NULL, 'input', NULL::json, NULL, NULL::json, 4, 'half', U&'\0417\0430\043a\0430\0437\0447\0438\043a', false),
  ('customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, 5, 'half', U&'\041a\043b\0438\0435\043d\0442', false),
  ('customer_name', NULL, 'input', NULL::json, NULL, NULL::json, 6, 'half', U&'\0418\043c\044f \043a\043b\0438\0435\043d\0442\0430', true),
  ('customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, 7, 'half', U&'\041a\043e\043c\043f\0430\043d\0438\044f', false),
  ('customer_company_name', NULL, 'input', NULL::json, NULL, NULL::json, 8, 'half', U&'\041d\0430\0437\0432\0430\043d\0438\0435 \043a\043e\043c\043f\0430\043d\0438\0438', true),
  ('manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, 9, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', false),
  ('manager_name', NULL, 'input', NULL::json, NULL, NULL::json, 10, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', true),
  ('date', NULL, 'datetime', NULL::json, NULL, NULL::json, 11, 'half', U&'\0414\0430\0442\0430', false),
  ('deadline', NULL, 'datetime', NULL::json, NULL, NULL::json, 12, 'half', U&'\0421\0440\043e\043a', false),
  ('order_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'labels', NULL::json, 13, 'half', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430', false),
  ('order_status_name', NULL, 'input', NULL::json, NULL, NULL::json, 14, 'half', U&'\0421\0442\0430\0442\0443\0441', true),
  ('order_sum', NULL, 'input', NULL::json, NULL, NULL::json, 15, 'half', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430', false),
  ('paid_amount', NULL, 'input', NULL::json, NULL, NULL::json, 16, 'half', U&'\041e\043f\043b\0430\0447\0435\043d\043e', false),
  ('payment_due', NULL, 'input', NULL::json, NULL, NULL::json, 17, 'half', U&'\041e\0441\0442\0430\0442\043e\043a', false),
  ('overpayment', NULL, 'input', NULL::json, NULL, NULL::json, 18, 'half', U&'\041f\0435\0440\0435\043f\043b\0430\0442\0430', false),
  ('customer_debt_to_us', NULL, 'input', NULL::json, NULL, NULL::json, 19, 'half', U&'\041a\043b\0438\0435\043d\0442 \0434\043e\043b\0436\0435\043d', false),
  ('our_debt_to_customer', NULL, 'input', NULL::json, NULL, NULL::json, 20, 'half', U&'\041c\044b \0434\043e\043b\0436\043d\044b', false),
  ('reconciliation_result', NULL, 'input', NULL::json, NULL, NULL::json, 21, 'half', U&'\0418\0442\043e\0433 \0441\0432\0435\0440\043a\0438', false)
) AS fields(field_name, special_value, interface_name, options_value, display_value, display_options_value, sort_order, width_value, label, hidden_value);

WITH my_collections(collection_name) AS (VALUES
  ('my_orders_in_work'),
  ('my_orders_completed'),
  ('my_orders_unpaid')
),
my_fields(field_name, interface_name, sort_order, width_value, label, hidden_value, special_value, display_value, display_options_value) AS (VALUES
  ('id', 'numeric', 1, 'full', NULL, true, NULL, NULL, NULL::json),
  ('order_link', 'symbolika-order-link', 2, 'half', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437', false, NULL, NULL, NULL::json),
  ('order_number', 'input', 3, 'half', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430', false, NULL, NULL, NULL::json),
  ('date', 'datetime', 4, 'half', U&'\0414\0430\0442\0430', false, NULL, NULL, NULL::json),
  ('deadline', 'datetime', 5, 'half', U&'\0421\0440\043e\043a', false, NULL, NULL, NULL::json),
  ('customer_display', 'input', 6, 'half', U&'\0417\0430\043a\0430\0437\0447\0438\043a', false, NULL, NULL, NULL::json),
  ('manager_employee', 'select-dropdown-m2o', 7, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', false, 'm2o', 'related-values', '{"template":"{{full_name}}"}'::json),
  ('manager_name', 'input', 8, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', true, NULL, NULL, NULL::json),
  ('order_status', 'select-dropdown', 9, 'half', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430', false, NULL, 'labels', NULL::json),
  ('order_status_name', 'input', 10, 'half', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430', true, NULL, NULL, NULL::json),
  ('office_status', 'select-dropdown', 11, 'half', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430', false, NULL, 'labels', NULL::json),
  ('shipping_method', 'select-dropdown', 12, 'half', U&'\0421\043f\043e\0441\043e\0431 \043e\0442\0433\0440\0443\0437\043a\0438', true, NULL, NULL, NULL::json),
  ('shipping_method_name', 'input', 13, 'half', U&'\0421\043f\043e\0441\043e\0431 \043e\0442\0433\0440\0443\0437\043a\0438', false, NULL, NULL, NULL::json),
  ('order_items', 'list-o2m', 14, 'full', U&'\041f\043e\0437\0438\0446\0438\0438', false, 'o2m', NULL, NULL::json),
  ('payments', 'list-o2m', 15, 'full', U&'\041e\043f\043b\0430\0442\044b', false, 'o2m', NULL, NULL::json),
  ('order_sum', 'input', 16, 'half', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430', false, NULL, NULL, NULL::json),
  ('paid_amount', 'input', 17, 'half', U&'\041e\043f\043b\0430\0447\0435\043d\043e', false, NULL, NULL, NULL::json),
  ('payment_due', 'input', 18, 'half', U&'\041e\0441\0442\0430\0442\043e\043a', false, NULL, NULL, NULL::json)
)
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  my_collections.collection_name,
  my_fields.field_name,
  my_fields.special_value,
  my_fields.interface_name,
  CASE WHEN my_fields.field_name = 'order_items'
    THEN '{"layout":"table","tableSpacing":"compact","fields":["product_name","quantity","deadline","item_status","production_status","office_status"],"enableCreate":false,"enableSelect":false}'::json
    WHEN my_fields.field_name = 'payments'
    THEN '{"layout":"table","tableSpacing":"compact","fields":["payment_date","amount","payment_type_name","allocated_amount"],"enableCreate":false,"enableSelect":false}'::json
    WHEN my_fields.field_name = 'manager_employee'
    THEN '{"template":"{{full_name}}"}'::json
    WHEN my_fields.field_name = 'order_status'
    THEN '{"template":"{{name}}"}'::json
    ELSE NULL
  END,
  my_fields.display_value,
  my_fields.display_options_value,
  true,
  my_fields.hidden_value,
  my_fields.sort_order,
  my_fields.width_value,
  CASE WHEN my_fields.label IS NULL
    THEN NULL
    ELSE json_build_array(json_build_object('language','ru-RU','translation', my_fields.label))::json
  END,
  false,
  true
FROM my_collections
CROSS JOIN my_fields;

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('orders_overview_items', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('orders_overview_items', 'orders_overview', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, true, true, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437'))::json, false, true),
  ('orders_overview_items', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'))::json, false, true),
  ('orders_overview_items', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'))::json, false, true);

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  collections.collection_name,
  fields.field_name,
  fields.special_value,
  fields.interface_name,
  fields.options_value,
  fields.display_value,
  fields.display_options_value,
  true,
  fields.hidden_value,
  fields.sort_order,
  fields.width_value,
  CASE WHEN fields.label IS NULL
    THEN NULL
    ELSE json_build_array(json_build_object('language','ru-RU','translation', fields.label))::json
  END,
  false,
  true
FROM (VALUES
  ('my_orders_in_work_items'),
  ('my_orders_completed_items'),
  ('my_orders_unpaid_items')
) AS collections(collection_name)
CROSS JOIN (VALUES
  ('id', NULL, 'numeric', NULL::json, NULL, NULL::json, 1, 'full', NULL, true),
  ('bucket_order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, 2, 'half', U&'\0417\0430\043a\0430\0437', true),
  ('product_name', NULL, 'input', NULL::json, NULL, NULL::json, 3, 'half', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435', false),
  ('quantity', NULL, 'input', NULL::json, NULL, NULL::json, 4, 'half', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e', false),
  ('deadline', NULL, 'datetime', NULL::json, NULL, NULL::json, 5, 'half', U&'\0421\0440\043e\043a \043f\043e\0437\0438\0446\0438\0438', false),
  ('item_status', NULL, 'select-dropdown', NULL::json, 'labels', NULL::json, 6, 'half', U&'\0421\0442\0430\0442\0443\0441 \043f\043e\0437\0438\0446\0438\0438', false),
  ('production_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'labels', NULL::json, 7, 'half', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430', false),
  ('office_status', NULL, 'select-dropdown', NULL::json, 'labels', NULL::json, 8, 'half', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430', false)
) AS fields(field_name, special_value, interface_name, options_value, display_value, display_options_value, sort_order, width_value, label, hidden_value);

UPDATE directus_fields target
SET options = source.options,
    display = source.display,
    display_options = source.display_options
FROM directus_fields source
WHERE source.collection = 'orders_items'
  AND source.field = target.field
  AND target.collection IN ('my_orders_in_work_items', 'my_orders_completed_items', 'my_orders_unpaid_items')
  AND target.field IN ('deadline', 'item_status', 'production_status', 'office_status');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  collections.collection_name,
  fields.field_name,
  fields.special_value,
  fields.interface_name,
  fields.options_value,
  fields.display_value,
  fields.display_options_value,
  true,
  fields.hidden_value,
  fields.sort_order,
  fields.width_value,
  CASE WHEN fields.label IS NULL
    THEN NULL
    ELSE json_build_array(json_build_object('language','ru-RU','translation', fields.label))::json
  END,
  false,
  true
FROM (VALUES
  ('my_orders_in_work_payments'),
  ('my_orders_completed_payments'),
  ('my_orders_unpaid_payments')
) AS collections(collection_name)
CROSS JOIN (VALUES
  ('id', NULL, 'numeric', NULL::json, NULL, NULL::json, 1, 'full', NULL, true),
  ('bucket_order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, 2, 'half', U&'\0417\0430\043a\0430\0437', true),
  ('payment_date', NULL, 'datetime', NULL::json, NULL, NULL::json, 3, 'half', U&'\0414\0430\0442\0430 \043f\043b\0430\0442\0435\0436\0430', false),
  ('amount', NULL, 'input', NULL::json, NULL, NULL::json, 4, 'half', U&'\0421\0443\043c\043c\0430 \043f\043b\0430\0442\0435\0436\0430', false),
  ('payment_type_name', NULL, 'input', NULL::json, NULL, NULL::json, 5, 'half', U&'\0422\0438\043f \043e\043f\043b\0430\0442\044b', false),
  ('allocated_amount', NULL, 'input', NULL::json, NULL, NULL::json, 6, 'half', U&'\0420\0430\0441\043f\0440\0435\0434\0435\043b\0435\043d\043e', false),
  ('unallocated_amount', NULL, 'input', NULL::json, NULL, NULL::json, 7, 'half', U&'\041d\0435 \0440\0430\0441\043f\0440\0435\0434\0435\043b\0435\043d\043e', false),
  ('comment', NULL, 'input-multiline', NULL::json, NULL, NULL::json, 8, 'full', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439', false)
) AS fields(field_name, special_value, interface_name, options_value, display_value, display_options_value, sort_order, width_value, label, hidden_value);

DELETE FROM directus_relations
WHERE (many_collection = 'orders_overview_items' AND many_field = 'orders_overview')
   OR (many_collection IN ('my_orders_in_work_items', 'my_orders_completed_items', 'my_orders_unpaid_items') AND many_field = 'bucket_order')
   OR (many_collection IN ('my_orders_in_work_items', 'my_orders_completed_items', 'my_orders_unpaid_items') AND many_field = 'production_status')
   OR (many_collection IN ('my_orders_in_work_payments', 'my_orders_completed_payments', 'my_orders_unpaid_payments') AND many_field = 'bucket_order')
   OR (many_collection = 'customer_reconciliation' AND many_field IN ('customer', 'customer_company', 'manager_employee', 'order_status'))
   OR many_collection IN ('my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid');

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES
  ('orders_overview_items', 'orders_overview', 'orders_overview', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_urgent', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_today', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_this_week', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_next_week', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_this_month', 'order_items', 'nullify'),
  ('orders_overview_items', 'orders_overview', 'orders_due_next_month', 'order_items', 'nullify'),
  ('my_orders_in_work', 'manager_employee', 'employees', NULL, 'nullify'),
  ('my_orders_completed', 'manager_employee', 'employees', NULL, 'nullify'),
  ('my_orders_unpaid', 'manager_employee', 'employees', NULL, 'nullify'),
  ('my_orders_in_work_items', 'bucket_order', 'my_orders_in_work', 'order_items', 'nullify'),
  ('my_orders_completed_items', 'bucket_order', 'my_orders_completed', 'order_items', 'nullify'),
  ('my_orders_unpaid_items', 'bucket_order', 'my_orders_unpaid', 'order_items', 'nullify'),
  ('my_orders_in_work_items', 'production_status', 'production_statuses', NULL, 'nullify'),
  ('my_orders_completed_items', 'production_status', 'production_statuses', NULL, 'nullify'),
  ('my_orders_unpaid_items', 'production_status', 'production_statuses', NULL, 'nullify'),
  ('my_orders_in_work_payments', 'bucket_order', 'my_orders_in_work', 'payments', 'nullify'),
  ('my_orders_completed_payments', 'bucket_order', 'my_orders_completed', 'payments', 'nullify'),
  ('my_orders_unpaid_payments', 'bucket_order', 'my_orders_unpaid', 'payments', 'nullify'),
  ('customer_reconciliation', 'customer', 'customers', NULL, 'nullify'),
  ('customer_reconciliation', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('customer_reconciliation', 'manager_employee', 'employees', NULL, 'nullify'),
  ('customer_reconciliation', 'order_status', 'order_statuses', NULL, 'nullify');

UPDATE directus_fields
SET display = 'related-values',
    display_options = '{"template":"{{product_name}} × {{quantity}}"}'::json
WHERE collection IN ('office_issue','office_issue_archive','my_orders_in_work','my_orders_completed','my_orders_unpaid')
  AND field = 'order_items';

UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office', 'foreground', '#F8FAFC', 'background', '#64748B'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office', 'foreground', '#111827', 'background', '#F59E0B'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued', 'foreground', '#F8FAFC', 'background', '#16A34A')
    ))::json
WHERE collection IN ('my_orders_in_work','my_orders_completed','my_orders_unpaid')
  AND field = 'office_status';

UPDATE directus_fields
SET interface = 'select-dropdown',
    options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued')
    ))::json,
    display = 'labels',
    display_options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office', 'foreground', '#F8FAFC', 'background', '#64748B'),
      jsonb_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office', 'foreground', '#111827', 'background', '#F59E0B'),
      jsonb_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued', 'foreground', '#F8FAFC', 'background', '#16A34A')
    ))::json
WHERE collection IN ('my_orders_in_work','my_orders_completed','my_orders_unpaid','office_issue_archive')
  AND field = 'office_status';

UPDATE directus_fields
SET interface = 'select-dropdown',
    options = jsonb_build_object('choices', jsonb_build_array(
      jsonb_build_object('text', U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435', 'value', 'office_pickup'),
      jsonb_build_object('text', U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443', 'value', 'client_delivery'),
      jsonb_build_object('text', U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f', 'value', 'transport_company')
    ))::json
WHERE collection IN ('my_orders_in_work','my_orders_completed','my_orders_unpaid','orders_overview','orders_due_urgent','orders_due_today','orders_due_this_week','orders_due_next_week','orders_due_this_month','orders_due_next_month')
  AND field = 'shipping_method';

WITH order_status_choices AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'text', name,
      'value', id,
      'foreground', CASE
        WHEN name IN (U&'\041d\043e\0432\044b\0439', U&'\0413\043e\0442\043e\0432') THEN '#111827'
        ELSE '#F8FAFC'
      END,
      'background', CASE
        WHEN name = U&'\041d\043e\0432\044b\0439' THEN '#FBBF24'
        WHEN name = U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435 \043c\0430\043a\0435\0442\0430' THEN '#A855F7'
        WHEN name = U&'\0412 \0440\0430\0431\043e\0442\0435' THEN '#3B82F6'
        WHEN name = U&'\0413\043e\0442\043e\0432' THEN '#22C55E'
        WHEN name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN '#16A34A'
        WHEN name = U&'\041e\0442\043c\0435\043d\0435\043d' THEN '#DC2626'
        ELSE '#64748B'
      END
    )
    ORDER BY COALESCE(sort, id), id
  ) AS choices
  FROM order_statuses
)
UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', order_status_choices.choices)::json
FROM order_status_choices
WHERE collection IN ('my_orders_in_work','my_orders_completed','my_orders_unpaid')
  AND field = 'order_status';

WITH order_status_choices AS (
  SELECT jsonb_agg(
    jsonb_build_object('text', name, 'value', id)
    ORDER BY COALESCE(sort, id), id
  ) AS choices
  FROM order_statuses
)
UPDATE directus_fields
SET interface = 'select-dropdown',
    options = jsonb_build_object('choices', order_status_choices.choices)::json
FROM order_status_choices
WHERE collection IN ('orders','my_orders_in_work','my_orders_completed','my_orders_unpaid')
  AND field = 'order_status';

WITH order_status_choices AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'text', name,
      'value', id,
      'foreground', CASE
        WHEN name IN (U&'\041d\043e\0432\044b\0439', U&'\0413\043e\0442\043e\0432') THEN '#111827'
        ELSE '#F8FAFC'
      END,
      'background', CASE
        WHEN name = U&'\041d\043e\0432\044b\0439' THEN '#FBBF24'
        WHEN name = U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435 \043c\0430\043a\0435\0442\0430' THEN '#A855F7'
        WHEN name = U&'\0412 \0440\0430\0431\043e\0442\0435' THEN '#3B82F6'
        WHEN name = U&'\0413\043e\0442\043e\0432' THEN '#22C55E'
        WHEN name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN '#16A34A'
        WHEN name = U&'\041e\0442\043c\0435\043d\0435\043d' THEN '#DC2626'
        ELSE '#64748B'
      END
    )
    ORDER BY COALESCE(sort, id), id
  ) AS choices
  FROM order_statuses
)
UPDATE directus_fields
SET display = 'labels',
    display_options = jsonb_build_object('choices', order_status_choices.choices)::json
FROM order_status_choices
WHERE collection = 'office_issue_archive'
  AND field = 'order_status';

DELETE FROM directus_permissions
WHERE collection IN (
  'orders_overview',
  'orders_due_urgent',
  'orders_due_today',
  'orders_due_this_week',
  'orders_due_next_week',
  'orders_due_this_month',
  'orders_due_next_month',
  'customer_reconciliation',
  'orders_overview_items',
  'my_orders_in_work',
  'my_orders_completed',
  'my_orders_unpaid',
  'my_orders_in_work_items',
  'my_orders_completed_items',
  'my_orders_unpaid_items',
  'my_orders_in_work_payments',
  'my_orders_completed_payments',
  'my_orders_unpaid_payments'
);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('orders_overview'),
    ('orders_due_urgent'),
    ('orders_due_today'),
    ('orders_due_this_week'),
    ('orders_due_next_week'),
    ('orders_due_this_month'),
    ('orders_due_next_month'),
    ('customer_reconciliation'),
    ('orders_overview_items')
) AS collections(collection_name)
CROSS JOIN (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id);

DELETE FROM directus_permissions
WHERE collection = 'customer_reconciliation';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'customer_reconciliation', 'read', permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000203', '{}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('my_orders_in_work'),
    ('my_orders_completed'),
    ('my_orders_unpaid')
) AS collections(collection_name)
CROSS JOIN (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('my_orders_in_work_items'),
    ('my_orders_completed_items'),
    ('my_orders_unpaid_items')
) AS collections(collection_name)
CROSS JOIN (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('my_orders_in_work_payments'),
    ('my_orders_completed_payments'),
    ('my_orders_unpaid_payments')
) AS collections(collection_name)
CROSS JOIN (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value);

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["date","deadline","manager_employee","order_number","customer","customer_company","order_status","order_items","order_sum"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'orders'
  AND (layout_query IS NULL OR NOT (layout_query::jsonb #> '{tabular,fields}' IS NOT NULL));

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["order","product_name","quantity","deadline","item_status","production_status","office_status"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'orders_items';

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["office_issue","order_number","product_name","quantity","customer_name","customer_company_name","manager_employee","office_status"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'office_items_in_office';

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'office_issue';

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'office_issue_archive';

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection IN ('my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid');

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["counterparty_name","order_number","deadline","manager_employee","order_status_name","order_sum","paid_amount","payment_due","overpayment","reconciliation_result"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'customer_reconciliation';

INSERT INTO directus_presets ("user", collection, layout, layout_query, layout_options)
SELECT
  du.id,
  'office_items_in_office',
  'tabular',
  '{"tabular":{"fields":["office_issue","order_number","product_name","quantity","customer_name","customer_company_name","manager_employee","office_status"],"page":1}}'::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM directus_users du
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp."user" = du.id
    AND dp.collection = 'office_items_in_office'
    AND dp.bookmark IS NULL
);

INSERT INTO directus_presets ("user", collection, layout, layout_query, layout_options)
SELECT
  du.id,
  'orders_items',
  'tabular',
  '{"tabular":{"fields":["order","product_name","quantity","deadline","item_status","production_status","office_status"],"page":1}}'::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM directus_users du
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp."user" = du.id
    AND dp.collection = 'orders_items'
    AND dp.bookmark IS NULL
);

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["amount","order_number_display","customer_name_display","customer_company_name_display","payment_date","payment_type","allocated_amount","unallocated_amount"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection = 'order_payments';

INSERT INTO directus_presets ("user", collection, layout, layout_query, layout_options)
SELECT
  du.id,
  'order_payments',
  'tabular',
  '{"tabular":{"fields":["amount","order_number_display","customer_name_display","customer_company_name_display","payment_date","payment_type","allocated_amount","unallocated_amount"],"page":1}}'::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM directus_users du
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp."user" = du.id
    AND dp.collection = 'order_payments'
    AND dp.bookmark IS NULL
);

INSERT INTO directus_presets ("user", collection, layout, layout_query, layout_options)
SELECT
  du.id,
  collection_name,
  'tabular',
  layout_query_value::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM directus_users du
CROSS JOIN (
  VALUES
    ('office_issue', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
    ('office_issue_archive', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
    ('customer_reconciliation', '{"tabular":{"fields":["counterparty_name","order_number","deadline","manager_employee","order_status_name","order_sum","paid_amount","payment_due","overpayment","reconciliation_result"],"page":1}}'),
    ('my_orders_in_work', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
    ('my_orders_completed', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
    ('my_orders_unpaid', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}')
) AS presets(collection_name, layout_query_value)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp."user" = du.id
    AND dp.collection = presets.collection_name
    AND dp.bookmark IS NULL
);

WITH manager_roles AS (
  SELECT id
  FROM directus_roles
  WHERE name IN (
    U&'\041c\0435\043d\0435\0434\0436\0435\0440',
    U&'\041e\0444\0438\0441-\043c\0435\043d\0435\0434\0436\0435\0440',
    U&'\0423\043f\0440\0430\0432\043b\044f\044e\0449\0438\0439'
  )
),
manager_presets(collection_name, layout_query_value) AS (VALUES
  ('orders', '{"tabular":{"fields":["date","deadline","manager_employee","order_number","customer","customer_company","order_status","order_items","order_sum"],"page":1}}'),
  ('orders_items', '{"tabular":{"fields":["order","product_name","quantity","deadline","item_status","production_status","office_status"],"page":1}}'),
  ('order_payments', '{"tabular":{"fields":["amount","order_number_display","customer_name_display","customer_company_name_display","payment_date","payment_type","allocated_amount","unallocated_amount"],"page":1}}'),
  ('payment_allocations', '{"tabular":{"fields":["payment","order","amount","comment"],"page":1}}'),
  ('office_issue', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
  ('office_issue_archive', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
  ('office_items_in_office', '{"tabular":{"fields":["office_issue","order_number","product_name","quantity","customer_name","customer_company_name","manager_employee","office_status"],"page":1}}'),
  ('orders_overview', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_urgent', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_today', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_this_week', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_next_week', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_this_month', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_next_month', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('customer_reconciliation', '{"tabular":{"fields":["counterparty_name","order_number","deadline","manager_employee","order_status_name","order_sum","paid_amount","payment_due","overpayment","reconciliation_result"],"page":1}}'),
  ('my_orders_in_work', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('my_orders_completed', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('my_orders_unpaid', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('customers', '{"tabular":{"fields":["name","phone","email","company","manager"],"page":1}}'),
  ('customer_companies', '{"tabular":{"fields":["name","phone","email","manager"],"page":1}}'),
  ('customer_company_links', '{"tabular":{"fields":["customer","company"],"page":1}}')
),
upsert_role_presets AS (
  UPDATE directus_presets dp
  SET layout = 'tabular',
      layout_query = manager_presets.layout_query_value::json,
      layout_options = '{"tabular":{"spacing":"compact"}}'::json
  FROM manager_roles
  JOIN manager_presets ON true
  WHERE dp.role = manager_roles.id
    AND dp."user" IS NULL
    AND dp.collection = manager_presets.collection_name
    AND dp.bookmark IS NULL
  RETURNING dp.role, dp.collection
)
INSERT INTO directus_presets (role, collection, layout, layout_query, layout_options)
SELECT
  manager_roles.id,
  manager_presets.collection_name,
  'tabular',
  manager_presets.layout_query_value::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM manager_roles
CROSS JOIN manager_presets
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp.role = manager_roles.id
    AND dp."user" IS NULL
    AND dp.collection = manager_presets.collection_name
    AND dp.bookmark IS NULL
);

WITH admin_roles AS (
  SELECT id
  FROM directus_roles
  WHERE name = 'Administrator'
),
admin_presets(collection_name, layout_query_value) AS (VALUES
  ('orders', '{"tabular":{"fields":["order_number","deadline","customer","customer_company","manager_employee","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_items', '{"tabular":{"fields":["order","product_name","quantity","price_per_unit","order_sum","deadline","item_status","production_status","office_status"],"page":1}}'),
  ('order_payments', '{"tabular":{"fields":["amount","order_number_display","customer_name_display","customer_company_name_display","payment_date","payment_type","allocated_amount","unallocated_amount"],"page":1}}'),
  ('payment_allocations', '{"tabular":{"fields":["payment","order","amount","comment"],"page":1}}'),
  ('office_issue', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
  ('office_issue_archive', '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'),
  ('office_items_in_office', '{"tabular":{"fields":["office_issue","order_number","product_name","quantity","customer_name","customer_company_name","manager_employee","office_status"],"page":1}}'),
  ('orders_overview', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_urgent', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_today', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_this_week', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_next_week', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_this_month', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('orders_due_next_month', '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('customer_reconciliation', '{"tabular":{"fields":["counterparty_name","order_number","deadline","manager_employee","order_status_name","order_sum","paid_amount","payment_due","overpayment","reconciliation_result"],"page":1}}'),
  ('my_orders_in_work', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('my_orders_completed', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'),
  ('my_orders_unpaid', '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}')
),
upsert_admin_presets AS (
  UPDATE directus_presets dp
  SET layout = 'tabular',
      layout_query = admin_presets.layout_query_value::json,
      layout_options = '{"tabular":{"spacing":"compact"}}'::json
  FROM admin_roles
  JOIN admin_presets ON true
  WHERE dp.role = admin_roles.id
    AND dp."user" IS NULL
    AND dp.collection = admin_presets.collection_name
    AND dp.bookmark IS NULL
  RETURNING dp.role, dp.collection
)
INSERT INTO directus_presets (role, collection, layout, layout_query, layout_options)
SELECT
  admin_roles.id,
  admin_presets.collection_name,
  'tabular',
  admin_presets.layout_query_value::json,
  '{"tabular":{"spacing":"compact"}}'::json
FROM admin_roles
CROSS JOIN admin_presets
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp.role = admin_roles.id
    AND dp."user" IS NULL
    AND dp.collection = admin_presets.collection_name
    AND dp.bookmark IS NULL
);

DELETE FROM directus_presets
WHERE "user" IS NOT NULL
  AND bookmark IS NULL
  AND collection IN (
    'orders', 'orders_items', 'order_payments', 'payment_allocations',
    'office_issue', 'office_issue_archive', 'office_items_in_office',
    'orders_overview', 'orders_due_urgent', 'orders_due_today', 'orders_due_this_week',
    'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month',
    'customer_reconciliation',
    'my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid'
  );

DROP TRIGGER IF EXISTS symbolika_normalize_list_presets ON directus_presets;

CREATE OR REPLACE FUNCTION normalize_symbolika_list_presets()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.collection = 'orders'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["date","deadline","manager_employee","order_number","customer","customer_company","order_status","order_items","order_sum"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'orders_items'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["order","product_name","quantity","deadline","item_status","production_status","office_status"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'office_items_in_office'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' ? 'office_status')
    ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["office_issue","order_number","product_name","quantity","customer_name","customer_company_name","manager_employee","office_status"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'order_payments'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' ? 'order_number_display')
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["amount","order_number_display","customer_name_display","customer_company_name_display","payment_date","payment_type","allocated_amount","unallocated_amount"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'office_issue'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'office_issue_archive'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["manager_employee","customer_name","order_number","order_items","office_payment_due","office_status"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection IN ('my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid')
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["order_number","deadline","customer_display","order_items","order_status","office_status","order_sum","paid_amount","payment_due"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection IN ('orders_overview', 'orders_due_urgent', 'orders_due_today', 'orders_due_this_week', 'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month')
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["order_number","deadline","customer_display","manager_name","shipping_method_name","order_sum","paid_amount","payment_due"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  IF NEW.collection = 'customer_reconciliation'
     AND (
       NEW.layout_query IS NULL
       OR NOT (NEW.layout_query::jsonb #> '{tabular,fields}' IS NOT NULL)
       OR jsonb_typeof(NEW.layout_query::jsonb #> '{tabular,fields}') <> 'array'
       OR jsonb_array_length(NEW.layout_query::jsonb #> '{tabular,fields}') = 0
     ) THEN
    NEW.layout := 'tabular';
    NEW.layout_query := '{"tabular":{"fields":["counterparty_name","order_number","deadline","manager_employee","order_status_name","order_sum","paid_amount","payment_due","overpayment","reconciliation_result"],"page":1}}'::json;
    NEW.layout_options := '{"tabular":{"spacing":"compact"}}'::json;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_normalize_list_presets
BEFORE INSERT OR UPDATE ON directus_presets
FOR EACH ROW
WHEN (NEW.collection IN ('orders', 'orders_items', 'office_items_in_office', 'order_payments', 'office_issue', 'office_issue_archive', 'orders_overview', 'orders_due_urgent', 'orders_due_today', 'orders_due_this_week', 'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month', 'customer_reconciliation', 'my_orders_in_work', 'my_orders_completed', 'my_orders_unpaid'))
EXECUTE FUNCTION normalize_symbolika_list_presets();

INSERT INTO payment_allocations (payment, "order", amount, comment)
SELECT
  op.id,
  op."order",
  op.amount,
  U&'\0410\0432\0442\043e\043c\0430\0442\0438\0447\0435\0441\043a\043e\0435 \0440\0430\0441\043f\0440\0435\0434\0435\043b\0435\043d\0438\0435'
FROM order_payments op
WHERE op."order" IS NOT NULL
  AND COALESCE(op.amount, 0) > 0
  AND COALESCE(op.allocation_mode, 'to_order') = 'to_order'
  AND NOT EXISTS (
    SELECT 1
    FROM payment_allocations pa
    WHERE pa.payment = op.id
      AND pa."order" = op."order"
  );

UPDATE order_payments op
   SET allocated_amount = COALESCE(allocated.total, 0),
       unallocated_amount = COALESCE(op.amount, 0) - COALESCE(allocated.total, 0)
  FROM (
    SELECT payment, COALESCE(SUM(amount), 0)::numeric(10,2) AS total
    FROM payment_allocations
    GROUP BY payment
  ) allocated
 WHERE op.id = allocated.payment;

UPDATE order_payments op
   SET allocated_amount = 0,
       unallocated_amount = COALESCE(op.amount, 0)
 WHERE NOT EXISTS (
   SELECT 1
   FROM payment_allocations pa
   WHERE pa.payment = op.id
 );

WITH item_totals AS (
  SELECT "order" AS order_id, COALESCE(SUM(order_sum), 0)::numeric(10,2) AS order_sum
  FROM orders_items
  GROUP BY "order"
),
payment_totals AS (
  SELECT "order" AS order_id, COALESCE(SUM(amount), 0)::numeric(10,2) AS paid_amount
  FROM payment_allocations
  GROUP BY "order"
)
UPDATE orders o
   SET order_sum = COALESCE(item_totals.order_sum, 0),
       paid_amount = COALESCE(payment_totals.paid_amount, 0),
       payment_due = COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0),
       office_payment_due = CASE
         WHEN o.payment_on_receipt THEN COALESCE(item_totals.order_sum, 0) - COALESCE(payment_totals.paid_amount, 0)
         ELSE 0
       END
  FROM item_totals
  LEFT JOIN payment_totals ON payment_totals.order_id = item_totals.order_id
 WHERE o.id = item_totals.order_id;

UPDATE orders o
   SET paid_amount = 0,
       payment_due = COALESCE(o.order_sum, 0),
       office_payment_due = CASE WHEN o.payment_on_receipt THEN COALESCE(o.order_sum, 0) ELSE 0 END
 WHERE NOT EXISTS (
   SELECT 1
   FROM payment_allocations pa
   WHERE pa."order" = o.id
 );

-- Card layout polish: put every working card in a predictable, task-oriented order.
WITH group_labels(collection_name, field_name, label_value) AS (VALUES
  ('orders', 'main', U&'\0413\043b\0430\0432\043d\043e\0435'),
  ('orders', 'client', U&'\041a\043b\0438\0435\043d\0442'),
  ('orders', 'order', U&'\0421\043e\0441\0442\0430\0432 \0437\0430\043a\0430\0437\0430'),
  ('orders', 'payment', U&'\041e\043f\043b\0430\0442\044b'),
  ('orders', 'finance', U&'\0424\0438\043d\0430\043d\0441\044b'),
  ('orders', 'shipping', U&'\0412\044b\0434\0430\0447\0430 \0438 \0434\043e\0441\0442\0430\0432\043a\0430'),
  ('orders', 'admin', U&'\0424\0438\043d\0440\0435\0437\0443\043b\044c\0442\0430\0442'),
  ('orders_items', 'main', U&'\041f\043e\0437\0438\0446\0438\044f'),
  ('orders_items', 'item', U&'\0421\0442\0430\0442\0443\0441\044b'),
  ('orders_items', 'tech', U&'\0422\0435\0445\043d\0438\0447\0435\0441\043a\043e\0435 \0437\0430\0434\0430\043d\0438\0435'),
  ('orders_items', 'admin', U&'\041f\043e\0434\0440\044f\0434\0447\0438\043a\0438 \0438 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  ('orders_items', 'finance', U&'\0424\0438\043d\0430\043d\0441\044b')
)
UPDATE directus_fields df
SET translations = json_build_array(json_build_object('language', 'ru-RU', 'translation', group_labels.label_value))::json
FROM group_labels
WHERE df.collection = group_labels.collection_name
  AND df.field = group_labels.field_name;

UPDATE directus_fields
SET options = '{"layout":"table","tableSpacing":"compact","fields":["product_name","quantity","price_per_unit","order_sum","deadline","item_status","production_status","office_status"],"enableCreate":true,"enableSelect":true}'::json
WHERE collection = 'orders'
  AND field = 'order_items';

WITH layout(collection_name, field_name, group_name, sort_value, width_value, hidden_value) AS (VALUES
  ('orders', 'main', NULL, 1, 'full', false),
  ('orders', 'order_number', 'main', 1, 'half', false),
  ('orders', 'manager_employee', 'main', 2, 'half', false),
  ('orders', 'date', 'main', 3, 'half', false),
  ('orders', 'deadline', 'main', 4, 'half', false),
  ('orders', 'order_status', 'main', 5, 'half', false),
  ('orders', 'office_status', 'main', 6, 'half', false),
  ('orders', 'comment', 'main', 7, 'half', false),
  ('orders', 'client', NULL, 2, 'full', false),
  ('orders', 'customer', 'client', 1, 'half', false),
  ('orders', 'customer_company', 'client', 2, 'half', false),
  ('orders', 'order', NULL, 3, 'full', false),
  ('orders', 'order_items', 'order', 1, 'full', false),
  ('orders', 'shipping', NULL, 4, 'full', false),
  ('orders', 'shipping_method', 'shipping', 1, 'half', false),
  ('orders', 'shipping_comment', 'shipping', 2, 'half', false),
  ('orders', 'payment', NULL, 5, 'full', false),
  ('orders', 'order_sum', 'payment', 1, 'half', false),
  ('orders', 'paid_amount', 'payment', 2, 'half', false),
  ('orders', 'payment_due', 'payment', 3, 'half', false),
  ('orders', 'office_payment_due', 'payment', 4, 'half', false),
  ('orders', 'payment_on_receipt', 'payment', 5, 'half', false),
  ('orders', 'payment_type', 'payment', 6, 'half', false),
  ('orders', 'payments', 'payment', 7, 'full', false),
  ('orders', 'admin', NULL, 90, 'full', false),
  ('orders', 'items_total_cost', 'admin', 1, 'half', false),
  ('orders', 'items_tax_sum', 'admin', 2, 'half', false),
  ('orders', 'items_manager_commission_sum', 'admin', 3, 'half', false),
  ('orders', 'profit_sum', 'admin', 4, 'half', false),
  ('orders', 'margin_percent', 'admin', 5, 'half', false),

  ('orders_items', 'main', NULL, 1, 'full', false),
  ('orders_items', 'order', 'main', 1, 'half', false),
  ('orders_items', 'product_name', 'main', 2, 'half', false),
  ('orders_items', 'quantity', 'main', 3, 'half', false),
  ('orders_items', 'price_per_unit', 'main', 4, 'half', false),
  ('orders_items', 'order_sum', 'main', 5, 'half', false),
  ('orders_items', 'deadline', 'main', 6, 'half', false),
  ('orders_items', 'product_category', 'main', 7, 'half', false),
  ('orders_items', 'product_subcategory', 'main', 8, 'half', false),
  ('orders_items', 'application_method', 'main', 9, 'half', false),
  ('orders_items', 'item', NULL, 2, 'full', false),
  ('orders_items', 'item_status', 'item', 1, 'half', false),
  ('orders_items', 'production_status', 'item', 2, 'half', false),
  ('orders_items', 'office_status', 'item', 3, 'half', false),
  ('orders_items', 'shipping_method', 'item', 4, 'half', false),
  ('orders_items', 'manager_employee', 'item', 5, 'half', false),
  ('orders_items', 'order_link', 'item', 6, 'half', false),
  ('orders_items', 'tech', NULL, 3, 'full', false),
  ('orders_items', 'technical_task_text', 'tech', 1, 'full', false),
  ('orders_items', 'url', 'tech', 2, 'full', false),
  ('orders_items', 'production_comment', 'tech', 3, 'full', false),
  ('orders_items', 'admin', NULL, 4, 'full', false),
  ('orders_items', 'contractor_1', 'admin', 1, 'half', false),
  ('orders_items', 'contractor_2', 'admin', 2, 'half', false),
  ('orders_items', 'contractor_1_cost', 'admin', 3, 'half', false),
  ('orders_items', 'contractor_2_cost', 'admin', 4, 'half', false),
  ('orders_items', 'finance', NULL, 5, 'full', false),
  ('orders_items', 'unit_cost', 'finance', 1, 'half', false),
  ('orders_items', 'total_cost', 'finance', 2, 'half', false),
  ('orders_items', 'tax_percent', 'finance', 3, 'half', false),
  ('orders_items', 'tax_sum', 'finance', 4, 'half', false),
  ('orders_items', 'profit_sum', 'finance', 5, 'half', false),
  ('orders_items', 'margin_percent', 'finance', 6, 'half', false),
  ('orders_items', 'manager_percent', 'finance', 7, 'half', false),
  ('orders_items', 'manager_commission_sum', 'finance', 8, 'half', false),

  ('office_issue', 'office_summary', NULL, 1, 'full', false),
  ('office_issue', 'order_number', 'office_summary', 1, 'half', false),
  ('office_issue', 'customer_name', 'office_summary', 2, 'half', false),
  ('office_issue', 'office_status', 'office_summary', 3, 'half', false),
  ('office_issue', 'order_sum', 'office_summary', 4, 'half', false),
  ('office_issue', 'payment_due', 'office_summary', 5, 'half', false),
  ('office_issue', 'add_payment', 'office_summary', 6, 'half', false),
  ('office_issue', 'payment_type', 'office_summary', 7, 'half', false),
  ('office_issue', 'order_link', 'office_summary', 8, 'half-right', false),
  ('office_issue', 'office_positions', NULL, 2, 'full', false),
  ('office_issue', 'order_items', 'office_positions', 1, 'full', false),
  ('office_issue', 'office_customer', NULL, 3, 'full', false),
  ('office_issue', 'customer_phone', 'office_customer', 1, 'half', false),
  ('office_issue', 'customer_company_name', 'office_customer', 2, 'half', false),
  ('office_issue', 'manager_employee', 'office_customer', 3, 'half', false),
  ('office_issue', 'deadline', 'office_customer', 4, 'half', false),
  ('office_issue', 'date', 'office_customer', 5, 'half', false),
  ('office_issue', 'order_status_name', 'office_customer', 6, 'half', false),
  ('office_issue', 'office_payment', NULL, 4, 'full', false),
  ('office_issue', 'paid_amount', 'office_payment', 1, 'half', false),
  ('office_issue', 'office_payment_due', 'office_payment', 2, 'half', false),
  ('office_issue', 'overpayment', 'office_payment', 3, 'half', false),
  ('office_issue', 'payment_comment', 'office_payment', 4, 'full', false),

  ('office_items_in_office', 'order_number', NULL, 1, 'half', false),
  ('office_items_in_office', 'office_issue', NULL, 2, 'half', false),
  ('office_items_in_office', 'office_status', NULL, 3, 'half', false),
  ('office_items_in_office', 'product_name', NULL, 4, 'half', false),
  ('office_items_in_office', 'quantity', NULL, 5, 'half', false),
  ('office_items_in_office', 'customer_name', NULL, 6, 'half', false),
  ('office_items_in_office', 'customer_company_name', NULL, 7, 'half', false),
  ('office_items_in_office', 'manager_employee', NULL, 8, 'half', false),
  ('office_items_in_office', 'order_link', NULL, 99, 'full', true),

  ('production_work', 'order_link', NULL, 1, 'half', false),
  ('production_work', 'order', NULL, 2, 'half', false),
  ('production_work', 'production_status', NULL, 3, 'half', false),
  ('production_work', 'deadline', NULL, 4, 'half', false),
  ('production_work', 'product_name', NULL, 5, 'half', false),
  ('production_work', 'quantity', NULL, 6, 'half', false),
  ('production_work', 'customer', NULL, 7, 'half', false),
  ('production_work', 'customer_company', NULL, 8, 'half', false),
  ('production_work', 'manager_employee', NULL, 9, 'half', false),
  ('production_work', 'url', NULL, 10, 'full', false),
  ('production_work', 'technical_task_text', NULL, 11, 'full', false),
  ('production_work', 'production_comment', NULL, 12, 'full', false),

  ('screen_printing_work', 'order_link', NULL, 1, 'half', false),
  ('screen_printing_work', 'order', NULL, 2, 'half', false),
  ('screen_printing_work', 'production_status', NULL, 3, 'half', false),
  ('screen_printing_work', 'deadline', NULL, 4, 'half', false),
  ('screen_printing_work', 'product_name', NULL, 5, 'half', false),
  ('screen_printing_work', 'quantity', NULL, 6, 'half', false),
  ('screen_printing_work', 'customer', NULL, 7, 'half', false),
  ('screen_printing_work', 'customer_company', NULL, 8, 'half', false),
  ('screen_printing_work', 'manager_employee', NULL, 9, 'half', false),
  ('screen_printing_work', 'url', NULL, 10, 'full', false),
  ('screen_printing_work', 'technical_task_text', NULL, 11, 'full', false),
  ('screen_printing_work', 'production_comment', NULL, 12, 'full', false),

  ('contractor_work', 'order_link', NULL, 1, 'half', false),
  ('contractor_work', 'order', NULL, 2, 'half', false),
  ('contractor_work', 'contractor', NULL, 3, 'half', false),
  ('contractor_work', 'production_status', NULL, 4, 'half', false),
  ('contractor_work', 'deadline', NULL, 5, 'half', false),
  ('contractor_work', 'product_name', NULL, 6, 'half', false),
  ('contractor_work', 'quantity', NULL, 7, 'half', false),
  ('contractor_work', 'customer', NULL, 8, 'half', false),
  ('contractor_work', 'customer_company', NULL, 9, 'half', false),
  ('contractor_work', 'manager_employee', NULL, 10, 'half', false),
  ('contractor_work', 'url', NULL, 11, 'full', false),
  ('contractor_work', 'technical_task_text', NULL, 12, 'full', false),
  ('contractor_work', 'production_comment', NULL, 13, 'full', false),

  ('customers', 'name', NULL, 1, 'half', false),
  ('customers', 'phone', NULL, 2, 'half', false),
  ('customers', 'email', NULL, 3, 'half', false),
  ('customers', 'manager', NULL, 4, 'half', false),
  ('customers', 'company', NULL, 5, 'half', false),
  ('customers', 'comment', NULL, 6, 'full', false),
  ('customers', 'orders_total_sum', NULL, 20, 'half', false),
  ('customers', 'payments_total_in', NULL, 21, 'half', false),
  ('customers', 'balance', NULL, 22, 'half', false),
  ('customers', 'debt_to_us', NULL, 23, 'half', false),
  ('customers', 'our_debt_to_customer', NULL, 24, 'half', false),
  ('customers', 'refunds_total_out', NULL, 25, 'half', false),
  ('customers', 'orders', NULL, 30, 'full', false),
  ('customers', 'company_links', NULL, 31, 'full', false),

  ('customer_companies', 'name', NULL, 1, 'half', false),
  ('customer_companies', 'phone', NULL, 2, 'half', false),
  ('customer_companies', 'email', NULL, 3, 'half', false),
  ('customer_companies', 'manager', NULL, 4, 'half', false),
  ('customer_companies', 'comment', NULL, 5, 'full', false),
  ('customer_companies', 'orders_total_sum', NULL, 20, 'half', false),
  ('customer_companies', 'payments_total_in', NULL, 21, 'half', false),
  ('customer_companies', 'balance', NULL, 22, 'half', false),
  ('customer_companies', 'debt_to_us', NULL, 23, 'half', false),
  ('customer_companies', 'our_debt_to_customer', NULL, 24, 'half', false),
  ('customer_companies', 'refunds_total_out', NULL, 25, 'half', false),
  ('customer_companies', 'customer_links', NULL, 30, 'full', false),

  ('order_payments', 'order_link', NULL, 1, 'half', false),
  ('order_payments', 'amount', NULL, 2, 'half', false),
  ('order_payments', 'payment_date', NULL, 3, 'half', false),
  ('order_payments', 'payment_type', NULL, 4, 'half', false),
  ('order_payments', 'order_number_display', NULL, 5, 'half', false),
  ('order_payments', 'customer_name_display', NULL, 6, 'half', false),
  ('order_payments', 'customer_company_name_display', NULL, 7, 'half', false),
  ('order_payments', 'allocated_amount', NULL, 8, 'half', false),
  ('order_payments', 'unallocated_amount', NULL, 9, 'half', false),
  ('order_payments', 'comment', NULL, 10, 'full', false),

  ('payment_allocations', 'order_link', NULL, 1, 'half', false),
  ('payment_allocations', 'payment', NULL, 2, 'half', false),
  ('payment_allocations', 'order', NULL, 3, 'half', false),
  ('payment_allocations', 'amount', NULL, 4, 'half', false),
  ('payment_allocations', 'comment', NULL, 5, 'full', false)
)
UPDATE directus_fields df
SET "group" = layout.group_name,
    sort = layout.sort_value,
    width = layout.width_value,
    hidden = layout.hidden_value
FROM layout
WHERE df.collection = layout.collection_name
  AND df.field = layout.field_name;

UPDATE directus_fields archive_fields
SET "group" = source_fields."group",
    sort = source_fields.sort,
    width = source_fields.width,
    hidden = source_fields.hidden
FROM directus_fields source_fields
WHERE archive_fields.collection = 'office_issue_archive'
  AND source_fields.collection = 'office_issue'
  AND archive_fields.field = source_fields.field;

UPDATE directus_fields
SET hidden = true
WHERE collection = 'orders'
  AND field IN ('divider-4rwmk3', 'accordion-cbo-ay', 'finance');

UPDATE directus_fields
SET interface = 'group-detail',
    options = '{"start":"open"}'::json,
    hidden = false
WHERE collection = 'orders'
  AND field = 'payment';

UPDATE directus_fields
SET hidden = true
WHERE collection = 'orders_items'
  AND field = 'accordion-redqc5';

SELECT sync_office_issue_order(id)
FROM orders
WHERE shipping_method = 'office_pickup';

SELECT refresh_customer_reconciliation();

COMMIT;


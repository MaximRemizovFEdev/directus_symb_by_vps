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
DROP TRIGGER IF EXISTS symbolika_zero_internal_contractor_costs ON orders_items;
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
DROP TRIGGER IF EXISTS symbolika_validate_order_workflow_transition ON orders;
DROP TRIGGER IF EXISTS symbolika_keep_order_commission_manager ON orders;
DROP TRIGGER IF EXISTS symbolika_set_item_manager ON orders_items;
DROP TRIGGER IF EXISTS symbolika_set_item_commission_manager ON orders_items;
DROP TRIGGER IF EXISTS symbolika_transfer_customer_manager ON customers;
DROP TRIGGER IF EXISTS symbolika_transfer_company_manager ON customer_companies;

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

CREATE TABLE IF NOT EXISTS symbolika_employee_notification_settings (
  "user" uuid PRIMARY KEY REFERENCES directus_users(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT true,
  email_enabled boolean NOT NULL DEFAULT false,
  vk_enabled boolean NOT NULL DEFAULT false,
  telegram_enabled boolean NOT NULL DEFAULT false,
  email_address varchar(255),
  vk_peer_id varchar(100),
  telegram_chat_id varchar(100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE symbolika_employee_notification_settings
  ADD COLUMN IF NOT EXISTS topics jsonb NOT NULL DEFAULT '{"order_status":true,"item_status":true,"new_tasks":true,"task_updates":true,"production":true,"procurement":true,"mail":false,"finance":true,"birthdays":true}'::jsonb;

ALTER TABLE symbolika_employee_notification_settings
  ALTER COLUMN topics SET DEFAULT '{"order_status":true,"item_status":true,"new_tasks":true,"task_updates":true,"production":true,"procurement":true,"mail":false,"finance":true,"birthdays":true}'::jsonb;

CREATE TABLE IF NOT EXISTS symbolika_employee_notification_deliveries (
  id bigserial PRIMARY KEY,
  notification bigint NOT NULL,
  "user" uuid NOT NULL REFERENCES directus_users(id) ON DELETE CASCADE,
  channel varchar(32) NOT NULL,
  recipient text,
  status varchar(32) NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  UNIQUE (notification, channel)
);

CREATE INDEX IF NOT EXISTS symbolika_employee_notification_deliveries_user_idx
  ON symbolika_employee_notification_deliveries("user", created_at DESC);

CREATE INDEX IF NOT EXISTS symbolika_employee_notification_deliveries_status_idx
  ON symbolika_employee_notification_deliveries(status, updated_at);

CREATE TABLE IF NOT EXISTS symbolika_work_assignment_notifications (
  id serial PRIMARY KEY,
  item integer NOT NULL,
  channel text NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (item, channel)
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
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birthday date;
ALTER TABLE directus_users ADD COLUMN IF NOT EXISTS phone character varying(255);

CREATE TABLE IF NOT EXISTS symbolika_birthday_notification_log (
  id bigserial PRIMARY KEY,
  birthday_employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  birthday_year integer NOT NULL,
  reminder_days integer NOT NULL,
  recipient uuid NOT NULL REFERENCES directus_users(id) ON DELETE CASCADE,
  notification bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (birthday_employee, birthday_year, reminder_days, recipient),
  CHECK (reminder_days IN (0, 7))
);

UPDATE directus_users u
SET phone = e.phone
FROM employees e
WHERE e.directus_user = u.id
  AND NULLIF(btrim(COALESCE(u.phone, '')), '') IS NULL
  AND NULLIF(btrim(COALESCE(e.phone, '')), '') IS NOT NULL;
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS access_manager_user uuid;
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS access_shipping_method character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS order_number_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS customer_name_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS customer_company_name_display character varying(255);
ALTER TABLE order_payments ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE payment_allocations ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS application_method integer;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS blank_source character varying(255) DEFAULT 'none';
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS blank_ordered boolean NOT NULL DEFAULT false;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS needs_designer_help boolean NOT NULL DEFAULT false;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS designer_comment text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS designer_source_url text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_revision_url_snapshot text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_path text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_name text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_size bigint;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_mime_type character varying(255);
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_uploaded_by uuid REFERENCES directus_users(id) ON DELETE SET NULL;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_disk_uploaded_at timestamptz;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_url text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_disk_path text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_disk_name text;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_disk_size bigint;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_disk_mime_type character varying(255);
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_uploaded_by uuid REFERENCES directus_users(id) ON DELETE SET NULL;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS layout_preview_uploaded_at timestamptz;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS internal_route_production boolean NOT NULL DEFAULT false;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS internal_route_screen boolean NOT NULL DEFAULT false;

-- Additional files and external references attached to an order item. The
-- legacy orders_items.url remains the primary layout used by readiness and
-- automation rules; this table stores any number of supporting materials.
CREATE TABLE IF NOT EXISTS order_item_attachments (
  id bigserial PRIMARY KEY,
  order_item integer NOT NULL REFERENCES orders_items(id) ON DELETE CASCADE,
  attachment_type character varying(20) NOT NULL DEFAULT 'file',
  title text,
  url text NOT NULL,
  disk_path text,
  file_name text,
  file_size bigint,
  mime_type character varying(255),
  uploaded_by uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  date_created timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT order_item_attachments_type_check CHECK (attachment_type IN ('file', 'link'))
);

CREATE INDEX IF NOT EXISTS order_item_attachments_item_idx
  ON order_item_attachments (order_item, date_created, id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS commission_manager_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE orders_items ADD COLUMN IF NOT EXISTS commission_manager_employee integer REFERENCES employees(id) ON DELETE SET NULL;

-- Existing orders predate the split between the employee currently responsible
-- for an order and the manager whose own sale earns commission. The current
-- manager is the safest historical baseline; subsequent transfers never change it.
UPDATE orders
SET commission_manager_employee = manager_employee
WHERE commission_manager_employee IS NULL;

UPDATE orders_items oi
SET commission_manager_employee = COALESCE(o.commission_manager_employee, o.manager_employee)
FROM orders o
WHERE o.id = oi."order"
  AND oi.commission_manager_employee IS DISTINCT FROM COALESCE(o.commission_manager_employee, o.manager_employee);

CREATE OR REPLACE FUNCTION symbolika_keep_order_commission_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.commission_manager_employee IS NOT NULL
     AND NEW.commission_manager_employee IS DISTINCT FROM OLD.commission_manager_employee THEN
    RAISE EXCEPTION 'commission manager is immutable after assignment';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_keep_order_commission_manager
BEFORE UPDATE OF commission_manager_employee ON orders
FOR EACH ROW EXECUTE FUNCTION symbolika_keep_order_commission_manager();

CREATE OR REPLACE FUNCTION symbolika_set_item_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT o.manager_employee
    INTO NEW.manager_employee
    FROM orders o
   WHERE o.id = NEW."order";
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_set_item_manager
BEFORE INSERT OR UPDATE OF "order" ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_set_item_manager();

CREATE OR REPLACE FUNCTION symbolika_set_item_commission_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT o.commission_manager_employee
    INTO NEW.commission_manager_employee
    FROM orders o
   WHERE o.id = NEW."order";
  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_set_item_commission_manager
BEFORE INSERT OR UPDATE OF "order", commission_manager_employee ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_set_item_commission_manager();

CREATE OR REPLACE FUNCTION symbolika_transfer_customer_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.manager IS NOT DISTINCT FROM OLD.manager THEN
    RETURN NEW;
  END IF;

  UPDATE orders
     SET manager_employee = NEW.manager
   WHERE customer = NEW.id
     AND manager_employee IS DISTINCT FROM NEW.manager;

  UPDATE orders_items oi
     SET manager_employee = NEW.manager
    FROM orders o
   WHERE o.id = oi."order"
     AND o.customer = NEW.id
     AND oi.manager_employee IS DISTINCT FROM NEW.manager;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_transfer_customer_manager
AFTER UPDATE OF manager ON customers
FOR EACH ROW EXECUTE FUNCTION symbolika_transfer_customer_manager();

CREATE OR REPLACE FUNCTION symbolika_transfer_company_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.manager IS NOT DISTINCT FROM OLD.manager THEN
    RETURN NEW;
  END IF;

  UPDATE customers c
     SET manager = NEW.manager
   WHERE c.company = NEW.id
     AND c.manager IS DISTINCT FROM NEW.manager;

  UPDATE orders o
     SET manager_employee = NEW.manager
   WHERE (
          o.customer_company = NEW.id
          OR EXISTS (
            SELECT 1
              FROM customers c
             WHERE c.id = o.customer
               AND c.manager = NEW.manager
               AND c.company = NEW.id
          )
        )
     AND o.manager_employee IS DISTINCT FROM NEW.manager;

  UPDATE orders_items oi
     SET manager_employee = NEW.manager
    FROM orders o
   WHERE o.id = oi."order"
     AND o.manager_employee = NEW.manager
     AND (
          o.customer_company = NEW.id
          OR EXISTS (
            SELECT 1
              FROM customers c
             WHERE c.id = o.customer
               AND c.company = NEW.id
          )
        )
     AND oi.manager_employee IS DISTINCT FROM NEW.manager;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_transfer_company_manager
AFTER UPDATE OF manager ON customer_companies
FOR EACH ROW EXECUTE FUNCTION symbolika_transfer_company_manager();
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS detail_mode character varying(255) DEFAULT 'subcategory';
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS office_applicable boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION symbolika_enforce_item_office_applicability()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  category_office_applicable boolean;
BEGIN
  IF NEW.product_category IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(pc.office_applicable, true)
    INTO category_office_applicable
  FROM product_categories pc
  WHERE pc.id = NEW.product_category;

  IF category_office_applicable = false THEN
    NEW.office_status := NULL;
    NEW.shipping_method := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_enforce_item_office_applicability ON orders_items;
CREATE TRIGGER symbolika_enforce_item_office_applicability
BEFORE INSERT OR UPDATE OF product_category, office_status, shipping_method ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_enforce_item_office_applicability();

ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_product_category integer REFERENCES product_categories(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_product_subcategory integer REFERENCES product_subcategories(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS supplies_textile_blanks boolean DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS supplies_merch_blanks boolean DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS has_own_view boolean DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS directus_user uuid REFERENCES directus_users(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS city character varying(255);
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS pickup_address text;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_delivery_method character varying(64) DEFAULT 'self_pickup';
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_transport_company character varying(255);
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS default_pickup_days integer;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS pickup_notes text;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS supplier_kind character varying(64) DEFAULT 'contractor';
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS is_internal_production boolean NOT NULL DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS website_url text;

UPDATE contractors
SET is_internal_production = true
WHERE name = U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'
  AND is_internal_production IS DISTINCT FROM true;
ALTER TABLE product_categories DROP COLUMN IF EXISTS default_contractor_1;
ALTER TABLE product_categories DROP COLUMN IF EXISTS default_contractor_2;

CREATE TABLE IF NOT EXISTS symbolika_tasks (
  id serial PRIMARY KEY,
  title text NOT NULL,
  description text,
  status varchar(32) NOT NULL DEFAULT 'new',
  priority varchar(32) NOT NULL DEFAULT 'normal',
  due_date date,
  completed_at timestamp with time zone,
  assigned_to integer REFERENCES employees(id) ON DELETE SET NULL,
  created_by_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  related_order integer REFERENCES orders(id) ON DELETE SET NULL,
  related_order_item integer REFERENCES orders_items(id) ON DELETE SET NULL,
  related_customer integer REFERENCES customers(id) ON DELETE SET NULL,
  related_company integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  date_created timestamp with time zone DEFAULT now(),
  date_updated timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS symbolika_task_comments (
  id serial PRIMARY KEY,
  task integer REFERENCES symbolika_tasks(id) ON DELETE CASCADE,
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  comment text NOT NULL,
  date_created timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS symbolika_task_checklist (
  id serial PRIMARY KEY,
  task integer REFERENCES symbolika_tasks(id) ON DELETE CASCADE,
  title text NOT NULL,
  is_done boolean NOT NULL DEFAULT false,
  sort integer NOT NULL DEFAULT 100,
  date_created timestamp with time zone DEFAULT now(),
  date_updated timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS symbolika_task_attachments (
  id serial PRIMARY KEY,
  task integer NOT NULL REFERENCES symbolika_tasks(id) ON DELETE CASCADE,
  file uuid NOT NULL REFERENCES directus_files(id) ON DELETE CASCADE,
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  title text,
  date_created timestamp with time zone DEFAULT now()
);

ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS title text NOT NULL DEFAULT '';
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS status varchar(32) NOT NULL DEFAULT 'new';
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS priority varchar(32) NOT NULL DEFAULT 'normal';
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS due_date date;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS assigned_to integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS created_by_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS related_order integer REFERENCES orders(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS related_order_item integer REFERENCES orders_items(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS related_customer integer REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS related_company integer REFERENCES customer_companies(id) ON DELETE SET NULL;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS date_created timestamp with time zone DEFAULT now();
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS date_updated timestamp with time zone DEFAULT now();
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS task_type varchar(32) NOT NULL DEFAULT 'general';
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS result_url text;
ALTER TABLE symbolika_tasks ADD COLUMN IF NOT EXISTS source_url text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS email_signature text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS public_position character varying(255);
ALTER TABLE employees ADD COLUMN IF NOT EXISTS email_signature_settings jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS symbolika_tasks_assigned_to_idx ON symbolika_tasks(assigned_to);
CREATE INDEX IF NOT EXISTS symbolika_tasks_created_by_employee_idx ON symbolika_tasks(created_by_employee);
CREATE INDEX IF NOT EXISTS symbolika_tasks_due_date_idx ON symbolika_tasks(due_date);
CREATE INDEX IF NOT EXISTS symbolika_tasks_status_idx ON symbolika_tasks(status);
CREATE INDEX IF NOT EXISTS symbolika_task_comments_task_idx ON symbolika_task_comments(task);
CREATE INDEX IF NOT EXISTS symbolika_task_checklist_task_idx ON symbolika_task_checklist(task);
CREATE INDEX IF NOT EXISTS symbolika_task_attachments_task_idx ON symbolika_task_attachments(task);
CREATE INDEX IF NOT EXISTS symbolika_task_attachments_file_idx ON symbolika_task_attachments(file);

-- The Directus action hook also enriches designer tasks and sends notifications,
-- but this database trigger guarantees that the task exists before the item
-- request returns. The insert is idempotent and the hook reuses the same row.
CREATE OR REPLACE FUNCTION symbolika_ensure_designer_task_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  order_row record;
  designer_employee integer;
BEGIN
  IF COALESCE(NEW.needs_designer_help, false) THEN
    SELECT o.* INTO order_row FROM orders o WHERE o.id = NEW."order";
    SELECT e.id INTO designer_employee
    FROM employees e
    JOIN directus_users u ON u.id = e.directus_user
    JOIN directus_roles r ON r.id = u.role
    WHERE r.name = U&'\0414\0438\0437\0430\0439\043d\0435\0440'
      AND COALESCE(e.is_active, true)
      AND COALESCE(u.status, 'active') = 'active'
    ORDER BY e.id
    LIMIT 1;

    INSERT INTO symbolika_tasks (
      title, description, task_type, status, priority, due_date, assigned_to,
      created_by_employee, related_order, related_order_item, related_customer,
      related_company, source_url, result_url, date_updated
    )
    SELECT
      concat(U&'\041f\043e\0434\0433\043e\0442\043e\0432\0438\0442\044c \043c\0430\043a\0435\0442: ', COALESCE(NULLIF(NEW.product_name, ''), concat(U&'\043f\043e\0437\0438\0446\0438\044f #', NEW.id))),
      NULLIF(concat_ws(E'\n\n',
        CASE WHEN NULLIF(BTRIM(NEW.designer_comment), '') IS NOT NULL
          THEN concat(U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439 \043c\0435\043d\0435\0434\0436\0435\0440\0430:', E'\n', NEW.designer_comment) END,
        CASE WHEN NULLIF(BTRIM(NEW.production_comment), '') IS NOT NULL
          THEN concat(U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430:', E'\n', NEW.production_comment) END
      ), ''), 'design', 'new', 'normal', COALESCE(NEW.deadline, order_row.deadline),
      designer_employee, order_row.manager_employee, NEW."order", NEW.id,
      order_row.customer, order_row.customer_company,
      COALESCE(NULLIF(BTRIM(NEW.designer_source_url), ''), NEW.url), NULL, now()
    WHERE NOT EXISTS (
      SELECT 1 FROM symbolika_tasks t
      WHERE t.task_type = 'design'
        AND t.related_order_item = NEW.id
        AND t.status <> 'cancelled'
    );

    UPDATE symbolika_tasks
    SET description = NULLIF(concat_ws(E'\n\n',
          CASE WHEN NULLIF(BTRIM(NEW.designer_comment), '') IS NOT NULL
            THEN concat(U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439 \043c\0435\043d\0435\0434\0436\0435\0440\0430:', E'\n', NEW.designer_comment) END,
          CASE WHEN NULLIF(BTRIM(NEW.production_comment), '') IS NOT NULL
            THEN concat(U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430:', E'\n', NEW.production_comment) END
        ), ''),
        source_url = COALESCE(NULLIF(BTRIM(NEW.designer_source_url), ''), NEW.url),
        due_date = COALESCE(NEW.deadline, order_row.deadline),
        date_updated = now()
    WHERE task_type = 'design'
      AND related_order_item = NEW.id
      AND status <> 'cancelled';
  ELSIF TG_OP = 'UPDATE' AND COALESCE(OLD.needs_designer_help, false) THEN
    UPDATE symbolika_tasks
    SET status = 'cancelled', date_updated = now()
    WHERE task_type = 'design'
      AND related_order_item = NEW.id
      AND status <> 'done';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_orders_items_designer_task ON orders_items;
CREATE TRIGGER symbolika_orders_items_designer_task
AFTER INSERT OR UPDATE OF needs_designer_help, designer_comment, designer_source_url, production_comment, url, deadline ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_ensure_designer_task_trigger();

CREATE TABLE IF NOT EXISTS inventory_items (
  id serial PRIMARY KEY,
  name text NOT NULL,
  section character varying(64) NOT NULL DEFAULT 'general',
  item_type character varying(64) NOT NULL DEFAULT 'consumable',
  unit character varying(32) NOT NULL DEFAULT 'шт.',
  current_qty numeric(14,3) NOT NULL DEFAULT 0,
  min_qty numeric(14,3) NOT NULL DEFAULT 0,
  default_supplier integer REFERENCES contractors(id) ON DELETE SET NULL,
  storage_place text,
  is_active boolean NOT NULL DEFAULT true,
  comment text,
  date_created timestamp with time zone DEFAULT now(),
  date_updated timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_movements (
  id serial PRIMARY KEY,
  inventory_item integer REFERENCES inventory_items(id) ON DELETE CASCADE,
  movement_type character varying(64) NOT NULL DEFAULT 'incoming',
  quantity numeric(14,3) NOT NULL DEFAULT 0,
  unit_cost numeric(14,2) NOT NULL DEFAULT 0,
  supplier integer REFERENCES contractors(id) ON DELETE SET NULL,
  related_order integer REFERENCES orders(id) ON DELETE SET NULL,
  related_order_item integer REFERENCES orders_items(id) ON DELETE SET NULL,
  comment text,
  date_created timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS procurement_requests (
  id serial PRIMARY KEY,
  request_type character varying(64) NOT NULL DEFAULT 'blank',
  request_source character varying(64) NOT NULL DEFAULT 'employee_request',
  purchase_source_type character varying(64) NOT NULL DEFAULT 'supplier',
  purchase_place character varying(255),
  product_url text,
  section character varying(64) NOT NULL DEFAULT 'general',
  status character varying(64) NOT NULL DEFAULT 'need_order',
  supplier integer REFERENCES contractors(id) ON DELETE SET NULL,
  inventory_item integer REFERENCES inventory_items(id) ON DELETE SET NULL,
  related_order integer REFERENCES orders(id) ON DELETE SET NULL,
  order_item integer REFERENCES orders_items(id) ON DELETE CASCADE,
  customer integer REFERENCES customers(id) ON DELETE SET NULL,
  customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  manager_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  product_name text,
  quantity numeric(14,3) NOT NULL DEFAULT 0,
  unit character varying(32) NOT NULL DEFAULT 'шт.',
  estimated_cost numeric(14,2) NOT NULL DEFAULT 0,
  delivery_method character varying(64) NOT NULL DEFAULT 'self_pickup',
  transport_company character varying(255),
  supplier_city character varying(255),
  pickup_address text,
  pickup_deadline date,
  ordered_at timestamp with time zone,
  received_at timestamp with time zone,
  requested_by_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  responsible_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  task_order_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  task_payment_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  task_pickup_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  comment text,
  date_created timestamp with time zone DEFAULT now(),
  date_updated timestamp with time zone DEFAULT now()
);

CREATE SEQUENCE IF NOT EXISTS procurement_batch_number_seq START WITH 1;

CREATE TABLE IF NOT EXISTS procurement_batches (
  id serial PRIMARY KEY,
  batch_number character varying(64) NOT NULL DEFAULT concat('PO-', lpad(nextval('procurement_batch_number_seq')::text, 5, '0')),
  supplier integer REFERENCES contractors(id) ON DELETE SET NULL,
  purchase_source_type character varying(64) NOT NULL DEFAULT 'supplier',
  purchase_place character varying(255),
  status character varying(64) NOT NULL DEFAULT 'need_order',
  delivery_method character varying(64) NOT NULL DEFAULT 'unknown',
  transport_company character varying(255),
  supplier_city character varying(255),
  pickup_address text,
  pickup_deadline date,
  item_count integer NOT NULL DEFAULT 0,
  estimated_total numeric(14,2) NOT NULL DEFAULT 0,
  responsible_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  task_order_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  management_task_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  task_payment_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  task_pickup_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  comment text,
  date_created timestamp with time zone DEFAULT now(),
  date_updated timestamp with time zone DEFAULT now()
);

ALTER TABLE procurement_requests
  ADD COLUMN IF NOT EXISTS task_payment_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL;

ALTER TABLE procurement_requests
  ADD COLUMN IF NOT EXISTS auto_generated boolean NOT NULL DEFAULT false;

ALTER TABLE procurement_requests
  ADD COLUMN IF NOT EXISTS requested_by_employee integer REFERENCES employees(id) ON DELETE SET NULL;

ALTER TABLE procurement_requests
  ADD COLUMN IF NOT EXISTS procurement_batch integer REFERENCES procurement_batches(id) ON DELETE SET NULL;

ALTER TABLE procurement_requests ADD COLUMN IF NOT EXISTS request_source character varying(64) NOT NULL DEFAULT 'employee_request';
ALTER TABLE procurement_requests ADD COLUMN IF NOT EXISTS purchase_source_type character varying(64) NOT NULL DEFAULT 'supplier';
ALTER TABLE procurement_requests ADD COLUMN IF NOT EXISTS purchase_place character varying(255);
ALTER TABLE procurement_requests ADD COLUMN IF NOT EXISTS product_url text;

UPDATE procurement_requests
SET request_source = CASE
      WHEN COALESCE(auto_generated, false) OR inventory_item IS NOT NULL THEN 'inventory_minimum'
      WHEN order_item IS NOT NULL AND request_type = 'blank' THEN 'order_blank'
      ELSE COALESCE(NULLIF(request_source, ''), 'employee_request')
    END,
    purchase_source_type = CASE
      WHEN supplier IS NOT NULL THEN 'supplier'
      WHEN COALESCE(NULLIF(purchase_source_type, ''), 'supplier') = 'supplier' THEN 'other'
      ELSE purchase_source_type
    END;

-- Procurement sections describe the responsible internal department, not the
-- kind of purchased product. Keep legacy requests visible under Production.
UPDATE procurement_requests
SET section = 'production'
WHERE section IN ('textile', 'merch');

ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS batch_number character varying(64) NOT NULL DEFAULT concat('PO-', lpad(nextval('procurement_batch_number_seq')::text, 5, '0'));
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS supplier integer REFERENCES contractors(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS purchase_source_type character varying(64) NOT NULL DEFAULT 'supplier';
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS purchase_place character varying(255);
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS status character varying(64) NOT NULL DEFAULT 'need_order';
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS delivery_method character varying(64) NOT NULL DEFAULT 'unknown';
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS transport_company character varying(255);
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS supplier_city character varying(255);
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS pickup_address text;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS pickup_deadline date;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS item_count integer NOT NULL DEFAULT 0;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS estimated_total numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS responsible_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS task_order_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS management_task_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS task_payment_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS task_pickup_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS comment text;
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS date_created timestamp with time zone DEFAULT now();
ALTER TABLE procurement_batches ADD COLUMN IF NOT EXISTS date_updated timestamp with time zone DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS procurement_requests_blank_item_uid
  ON procurement_requests(order_item, request_type)
  WHERE order_item IS NOT NULL AND request_type = 'blank';

CREATE UNIQUE INDEX IF NOT EXISTS procurement_requests_inventory_auto_open_uid
  ON procurement_requests(inventory_item)
  WHERE inventory_item IS NOT NULL
    AND auto_generated = true
    AND status NOT IN ('received', 'cancelled');

CREATE INDEX IF NOT EXISTS inventory_items_section_idx ON inventory_items(section);
CREATE INDEX IF NOT EXISTS inventory_items_supplier_idx ON inventory_items(default_supplier);
CREATE INDEX IF NOT EXISTS inventory_movements_item_idx ON inventory_movements(inventory_item);
CREATE INDEX IF NOT EXISTS procurement_requests_status_idx ON procurement_requests(status);
CREATE INDEX IF NOT EXISTS procurement_requests_supplier_idx ON procurement_requests(supplier);
CREATE INDEX IF NOT EXISTS procurement_requests_order_item_idx ON procurement_requests(order_item);
CREATE INDEX IF NOT EXISTS procurement_requests_pickup_deadline_idx ON procurement_requests(pickup_deadline);
CREATE UNIQUE INDEX IF NOT EXISTS procurement_batches_number_uid ON procurement_batches(batch_number);
CREATE INDEX IF NOT EXISTS procurement_batches_status_idx ON procurement_batches(status);
CREATE INDEX IF NOT EXISTS procurement_batches_supplier_idx ON procurement_batches(supplier);
CREATE INDEX IF NOT EXISTS procurement_requests_batch_idx ON procurement_requests(procurement_batch);

CREATE TABLE IF NOT EXISTS finance_dashboard_metrics (
  metric_key character varying(255) PRIMARY KEY,
  title character varying(255) NOT NULL,
  metric_group character varying(255) NOT NULL,
  value numeric(14,2) DEFAULT 0,
  sort integer DEFAULT 100,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS finance_dashboard_monthly (
  month_start date PRIMARY KEY,
  month_label character varying(255) NOT NULL,
  revenue numeric(14,2) DEFAULT 0,
  paid numeric(14,2) DEFAULT 0,
  profit numeric(14,2) DEFAULT 0,
  expenses numeric(14,2) DEFAULT 0,
  receivable numeric(14,2) DEFAULT 0,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS finance_dashboard_series (
  id serial PRIMARY KEY,
  month_start date NOT NULL,
  month_label character varying(255) NOT NULL,
  metric_key character varying(255) NOT NULL,
  metric_name character varying(255) NOT NULL,
  value numeric(14,2) DEFAULT 0,
  sort integer DEFAULT 100,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS business_expenses (
  id serial PRIMARY KEY,
  expense_date date NOT NULL DEFAULT current_date,
  accounting_month date,
  expense_type character varying(255) NOT NULL DEFAULT 'other',
  amount numeric(14,2) NOT NULL DEFAULT 0,
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  payment_type integer REFERENCES payment_types(id) ON DELETE SET NULL,
  comment text,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS expense_date date NOT NULL DEFAULT current_date;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS accounting_month date;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS expense_type character varying(255) NOT NULL DEFAULT 'other';
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS amount numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS payment_type integer REFERENCES payment_types(id) ON DELETE SET NULL;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS comment text;
ALTER TABLE business_expenses ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now();

UPDATE business_expenses
SET accounting_month = date_trunc('month', expense_date)::date
WHERE accounting_month IS NULL;

CREATE OR REPLACE FUNCTION normalize_business_expense_accounting_month()
RETURNS trigger AS $$
BEGIN
  NEW.accounting_month := date_trunc(
    'month',
    COALESCE(NEW.accounting_month, NEW.expense_date, current_date)
  )::date;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS business_expenses_normalize_accounting_month ON business_expenses;
CREATE TRIGGER business_expenses_normalize_accounting_month
BEFORE INSERT OR UPDATE OF expense_date, accounting_month ON business_expenses
FOR EACH ROW EXECUTE FUNCTION normalize_business_expense_accounting_month();

CREATE TABLE IF NOT EXISTS finance_settings (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  monthly_rent numeric(14,2) NOT NULL DEFAULT 160000,
  rent_due_day_from smallint NOT NULL DEFAULT 26 CHECK (rent_due_day_from BETWEEN 1 AND 31),
  rent_due_day_to smallint NOT NULL DEFAULT 30 CHECK (rent_due_day_to BETWEEN 1 AND 31),
  advance_day smallint NOT NULL DEFAULT 28 CHECK (advance_day BETWEEN 1 AND 31),
  salary_day smallint NOT NULL DEFAULT 12 CHECK (salary_day BETWEEN 1 AND 31),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

INSERT INTO finance_settings (id, monthly_rent)
VALUES (1, 160000)
ON CONFLICT (id) DO NOTHING;

DROP TABLE IF EXISTS employee_salary_monthly CASCADE;
DROP TABLE IF EXISTS employee_salary_summary CASCADE;

CREATE OR REPLACE VIEW employee_salary_summary AS
WITH period AS (
  SELECT date_trunc('month', current_date)::date AS month_start
),
employee_orders AS (
  SELECT
    e.id AS employee,
    COALESCE(SUM(o.order_sum), 0) AS orders_sum,
    COALESCE(SUM(o.paid_amount), 0) AS paid_orders_sum,
    COALESCE(SUM(GREATEST(o.payment_due, 0)), 0) AS unpaid_orders_sum
  FROM employees e
  CROSS JOIN period p
  LEFT JOIN orders o
    ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
   AND o.date >= p.month_start
   AND o.date < (p.month_start + interval '1 month')::date
  GROUP BY e.id
),
employee_payments AS (
  SELECT
    be.employee,
    COALESCE(SUM(be.amount) FILTER (WHERE be.expense_type = 'salary_payment'), 0) AS salary_paid,
    COALESCE(SUM(be.amount) FILTER (WHERE be.expense_type = 'employee_advance'), 0) AS advances_paid
  FROM business_expenses be
  CROSS JOIN period p
  WHERE be.employee IS NOT NULL
    AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = p.month_start
  GROUP BY be.employee
)
SELECT
  e.id,
  e.id AS employee,
  e.full_name AS employee_name,
  ep.name AS position_name,
  p.month_start,
  COALESCE(e.salary_fixed, 0) AS salary_fixed,
  COALESCE(e.order_percent, 0) AS order_percent,
  COALESCE(eo.orders_sum, 0) AS orders_sum,
  COALESCE(eo.paid_orders_sum, 0) AS paid_orders_sum,
  COALESCE(eo.unpaid_orders_sum, 0) AS unpaid_orders_sum,
  ROUND(COALESCE(eo.paid_orders_sum, 0) * COALESCE(e.order_percent, 0) / 100, 2) AS commission_accrued,
  ROUND(COALESCE(e.salary_fixed, 0) + COALESCE(eo.paid_orders_sum, 0) * COALESCE(e.order_percent, 0) / 100, 2) AS salary_accrued,
  COALESCE(pay.salary_paid, 0) AS salary_paid,
  COALESCE(pay.advances_paid, 0) AS advances_paid,
  ROUND(
    COALESCE(e.salary_fixed, 0)
    + COALESCE(eo.paid_orders_sum, 0) * COALESCE(e.order_percent, 0) / 100
    - COALESCE(pay.salary_paid, 0)
    - COALESCE(pay.advances_paid, 0),
    2
  ) AS salary_debt
FROM employees e
CROSS JOIN period p
LEFT JOIN employee_positions ep ON ep.id = e.position
LEFT JOIN employee_orders eo ON eo.employee = e.id
LEFT JOIN employee_payments pay ON pay.employee = e.id
WHERE COALESCE(e.is_active, true) = true;

CREATE OR REPLACE VIEW employee_salary_monthly AS
WITH months AS (
  SELECT generate_series(
    (date_trunc('month', current_date) - interval '11 months')::date,
    date_trunc('month', current_date)::date,
    interval '1 month'
  )::date AS month_start
),
base AS (
  SELECT
    e.id AS employee,
    e.full_name AS employee_name,
    m.month_start,
    to_char(m.month_start, 'MM.YY') AS month_label,
    COALESCE(e.salary_fixed, 0) AS salary_fixed,
    COALESCE(e.order_percent, 0) AS order_percent,
    COALESCE(SUM(o.order_sum), 0) AS orders_sum,
    COALESCE(SUM(o.paid_amount), 0) AS paid_orders_sum,
    COALESCE(SUM(GREATEST(o.payment_due, 0)), 0) AS unpaid_orders_sum
  FROM employees e
  CROSS JOIN months m
  LEFT JOIN orders o
    ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
   AND o.date >= m.month_start
   AND o.date < (m.month_start + interval '1 month')::date
  WHERE COALESCE(e.is_active, true) = true
  GROUP BY e.id, e.full_name, m.month_start, e.salary_fixed, e.order_percent
),
payments AS (
  SELECT
    be.employee,
    COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) AS month_start,
    COALESCE(SUM(be.amount) FILTER (WHERE be.expense_type = 'salary_payment'), 0) AS salary_paid,
    COALESCE(SUM(be.amount) FILTER (WHERE be.expense_type = 'employee_advance'), 0) AS advances_paid
  FROM business_expenses be
  WHERE be.employee IS NOT NULL
  GROUP BY be.employee, COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date)
)
SELECT
  row_number() OVER (ORDER BY b.month_start DESC, b.employee)::integer AS id,
  b.employee,
  b.employee_name,
  b.month_start,
  b.month_label,
  b.salary_fixed,
  b.order_percent,
  b.orders_sum,
  b.paid_orders_sum,
  b.unpaid_orders_sum,
  ROUND(b.paid_orders_sum * b.order_percent / 100, 2) AS commission_accrued,
  ROUND(b.salary_fixed + b.paid_orders_sum * b.order_percent / 100, 2) AS salary_accrued,
  COALESCE(p.salary_paid, 0) AS salary_paid,
  COALESCE(p.advances_paid, 0) AS advances_paid,
  ROUND(b.salary_fixed + b.paid_orders_sum * b.order_percent / 100 - COALESCE(p.salary_paid, 0) - COALESCE(p.advances_paid, 0), 2) AS salary_debt
FROM base b
LEFT JOIN payments p ON p.employee = b.employee AND p.month_start = b.month_start;

DROP VIEW IF EXISTS employee_salary_monthly CASCADE;
DROP VIEW IF EXISTS employee_salary_summary CASCADE;

CREATE TABLE IF NOT EXISTS employee_salary_summary (
  id integer PRIMARY KEY,
  employee integer,
  employee_name character varying(255),
  position_name character varying(255),
  month_start date,
  salary_fixed numeric(14,2) DEFAULT 0,
  order_percent numeric(14,2) DEFAULT 0,
  orders_sum numeric(14,2) DEFAULT 0,
  paid_orders_sum numeric(14,2) DEFAULT 0,
  unpaid_orders_sum numeric(14,2) DEFAULT 0,
  commission_accrued numeric(14,2) DEFAULT 0,
  salary_accrued numeric(14,2) DEFAULT 0,
  salary_paid numeric(14,2) DEFAULT 0,
  advances_paid numeric(14,2) DEFAULT 0,
  bonus_paid numeric(14,2) DEFAULT 0,
  salary_debt numeric(14,2) DEFAULT 0
);

ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS bonus_paid numeric(14,2) DEFAULT 0;

CREATE TABLE IF NOT EXISTS employee_salary_monthly (
  id integer PRIMARY KEY,
  employee integer,
  employee_name character varying(255),
  position_name character varying(255),
  month_start date,
  month_label character varying(255),
  salary_fixed numeric(14,2) DEFAULT 0,
  order_percent numeric(14,2) DEFAULT 0,
  orders_sum numeric(14,2) DEFAULT 0,
  paid_orders_sum numeric(14,2) DEFAULT 0,
  unpaid_orders_sum numeric(14,2) DEFAULT 0,
  commission_accrued numeric(14,2) DEFAULT 0,
  salary_accrued numeric(14,2) DEFAULT 0,
  salary_paid numeric(14,2) DEFAULT 0,
  advances_paid numeric(14,2) DEFAULT 0,
  bonus_paid numeric(14,2) DEFAULT 0,
  salary_debt numeric(14,2) DEFAULT 0
);

ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS bonus_paid numeric(14,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS position_name character varying(255);

CREATE OR REPLACE FUNCTION refresh_employee_salary_tables()
RETURNS void AS $$
DECLARE
  month_begin date := date_trunc('month', current_date)::date;
BEGIN
  PERFORM pg_advisory_xact_lock(2026080201);

  DELETE FROM employee_salary_summary;

  INSERT INTO employee_salary_summary (
    id, employee, employee_name, position_name, month_start,
    salary_fixed, order_percent, orders_sum, paid_orders_sum, unpaid_orders_sum,
    commission_accrued, salary_accrued, salary_paid, advances_paid, bonus_paid, salary_debt
  )
  SELECT
    e.id,
    e.id,
    e.full_name,
    ep.name,
    month_begin,
    COALESCE(e.salary_fixed, 0),
    COALESCE(e.order_percent, 0),
    COALESCE(SUM(o.order_sum), 0),
    COALESCE(SUM(o.paid_amount), 0),
    COALESCE(SUM(GREATEST(o.payment_due, 0)), 0),
    ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2),
    ROUND(
      COALESCE(e.salary_fixed, 0)
      + COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100
      + COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = e.id
          AND be.expense_type = 'employee_bonus'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
      ), 0),
      2
    ),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = e.id
        AND be.expense_type = 'salary_payment'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
    ), 0),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = e.id
        AND be.expense_type = 'employee_advance'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
    ), 0),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = e.id
        AND be.expense_type = 'employee_bonus'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
    ), 0),
    ROUND(
      COALESCE(e.salary_fixed, 0)
      + COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100
      + COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = e.id
          AND be.expense_type = 'employee_bonus'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
      ), 0)
      - COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = e.id
          AND be.expense_type = 'salary_payment'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
      ), 0)
      - COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = e.id
          AND be.expense_type = 'employee_advance'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = month_begin
      ), 0),
      2
    )
  FROM employees e
  LEFT JOIN employee_positions ep ON ep.id = e.position
  LEFT JOIN orders o
    ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
   AND o.date >= month_begin
   AND o.date < (month_begin + interval '1 month')::date
  WHERE COALESCE(e.is_active, true) = true
  GROUP BY e.id, e.full_name, ep.name, e.salary_fixed, e.order_percent;

  DELETE FROM employee_salary_monthly;

  INSERT INTO employee_salary_monthly (
    id, employee, employee_name, position_name, month_start, month_label,
    salary_fixed, order_percent, orders_sum, paid_orders_sum, unpaid_orders_sum,
    commission_accrued, salary_accrued, salary_paid, advances_paid, bonus_paid, salary_debt
  )
  WITH months AS (
    SELECT generate_series(
      (date_trunc('month', current_date) - interval '11 months')::date,
      date_trunc('month', current_date)::date,
      interval '1 month'
    )::date AS month_start
  ),
  base AS (
    SELECT
      e.id AS employee,
      e.full_name AS employee_name,
      ep.name AS position_name,
      m.month_start,
      to_char(m.month_start, 'MM.YY') AS month_label,
      COALESCE(e.salary_fixed, 0) AS salary_fixed,
      COALESCE(e.order_percent, 0) AS order_percent,
      COALESCE(SUM(o.order_sum), 0) AS orders_sum,
      COALESCE(SUM(o.paid_amount), 0) AS paid_orders_sum,
      COALESCE(SUM(GREATEST(o.payment_due, 0)), 0) AS unpaid_orders_sum
    FROM employees e
    LEFT JOIN employee_positions ep ON ep.id = e.position
    CROSS JOIN months m
    LEFT JOIN orders o
      ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
     AND o.date >= m.month_start
     AND o.date < (m.month_start + interval '1 month')::date
    WHERE COALESCE(e.is_active, true) = true
    GROUP BY e.id, e.full_name, ep.name, m.month_start, e.salary_fixed, e.order_percent
  )
  SELECT
    row_number() OVER (ORDER BY b.month_start DESC, b.employee)::integer,
    b.employee,
    b.employee_name,
    b.position_name,
    b.month_start,
    b.month_label,
    b.salary_fixed,
    b.order_percent,
    b.orders_sum,
    b.paid_orders_sum,
    b.unpaid_orders_sum,
    ROUND(b.paid_orders_sum * b.order_percent / 100, 2),
    ROUND(
      b.salary_fixed
      + b.paid_orders_sum * b.order_percent / 100
      + COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = b.employee
          AND be.expense_type = 'employee_bonus'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
      ), 0),
      2
    ),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = b.employee
        AND be.expense_type = 'salary_payment'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
    ), 0),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = b.employee
        AND be.expense_type = 'employee_advance'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
    ), 0),
    COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.employee = b.employee
        AND be.expense_type = 'employee_bonus'
        AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
    ), 0),
    ROUND(
      b.salary_fixed
      + b.paid_orders_sum * b.order_percent / 100
      + COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = b.employee
          AND be.expense_type = 'employee_bonus'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
      ), 0)
      - COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = b.employee
          AND be.expense_type = 'salary_payment'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
      ), 0)
      - COALESCE((
        SELECT SUM(be.amount)
        FROM business_expenses be
        WHERE be.employee = b.employee
          AND be.expense_type = 'employee_advance'
          AND COALESCE(be.accounting_month, date_trunc('month', be.expense_date)::date) = b.month_start
      ), 0),
      2
    )
  FROM base b;
END;
$$ LANGUAGE plpgsql;

SELECT refresh_employee_salary_tables();

CREATE TABLE IF NOT EXISTS manager_finance_summary (
  id integer PRIMARY KEY,
  employee integer REFERENCES employees(id) ON DELETE CASCADE,
  directus_user uuid,
  employee_name character varying(255),
  order_percent numeric(14,2) DEFAULT 0,
  orders_count integer DEFAULT 0,
  orders_sum numeric(14,2) DEFAULT 0,
  paid_orders_sum numeric(14,2) DEFAULT 0,
  unpaid_orders_sum numeric(14,2) DEFAULT 0,
  commission_total numeric(14,2) DEFAULT 0,
  commission_accrued numeric(14,2) DEFAULT 0,
  commission_expected numeric(14,2) DEFAULT 0,
  commission_paid numeric(14,2) DEFAULT 0,
  commission_to_pay numeric(14,2) DEFAULT 0
);

CREATE OR REPLACE FUNCTION refresh_manager_finance_summary()
RETURNS void AS $$
BEGIN
  DELETE FROM manager_finance_summary;

  INSERT INTO manager_finance_summary (
    id,
    employee,
    directus_user,
    employee_name,
    order_percent,
    orders_count,
    orders_sum,
    paid_orders_sum,
    unpaid_orders_sum,
    commission_total,
    commission_accrued,
    commission_expected,
    commission_paid,
    commission_to_pay
  )
  SELECT
    e.id,
    e.id,
    e.directus_user,
    e.full_name,
    COALESCE(e.order_percent, 0),
    COUNT(o.id)::integer,
    ROUND(COALESCE(SUM(o.order_sum), 0), 2),
    ROUND(COALESCE(SUM(o.paid_amount), 0), 2),
    ROUND(COALESCE(SUM(o.payment_due), 0), 2),
    ROUND(COALESCE(SUM(o.order_sum), 0) * COALESCE(e.order_percent, 0) / 100, 2),
    ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2),
    ROUND(COALESCE(SUM(o.payment_due), 0) * COALESCE(e.order_percent, 0) / 100, 2),
    LEAST(
      ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2),
      ROUND(
        COALESCE((
          SELECT SUM(be.amount)
          FROM business_expenses be
          WHERE be.employee = e.id
            AND be.expense_type IN ('salary_payment', 'employee_advance')
        ), 0),
        2
      )
    ),
    GREATEST(
      ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2)
      - LEAST(
        ROUND(COALESCE(SUM(o.paid_amount), 0) * COALESCE(e.order_percent, 0) / 100, 2),
        ROUND(
          COALESCE((
            SELECT SUM(be.amount)
            FROM business_expenses be
            WHERE be.employee = e.id
              AND be.expense_type IN ('salary_payment', 'employee_advance')
          ), 0),
          2
        )
      ),
      0
    )
  FROM employees e
  LEFT JOIN orders o ON COALESCE(o.commission_manager_employee, o.manager_employee) = e.id
  WHERE COALESCE(e.is_active, true) = true
  GROUP BY e.id, e.directus_user, e.full_name, e.order_percent;
END;
$$ LANGUAGE plpgsql;

SELECT refresh_manager_finance_summary();

CREATE OR REPLACE FUNCTION refresh_finance_dashboard_metrics()
RETURNS void AS $$
DECLARE
  month_begin date := date_trunc('month', current_date)::date;
  year_begin date := date_trunc('year', current_date)::date;
  business_expenses_month numeric(14,2) := 0;
  business_expenses_year numeric(14,2) := 0;
BEGIN
  PERFORM refresh_employee_salary_tables();
  PERFORM refresh_manager_finance_summary();

  SELECT COALESCE(SUM(amount), 0)
  INTO business_expenses_month
  FROM business_expenses
  WHERE expense_date >= month_begin
    AND expense_date < (month_begin + interval '1 month')::date
    AND expense_type <> 'employee_bonus';

  SELECT COALESCE(SUM(amount), 0)
  INTO business_expenses_year
  FROM business_expenses
  WHERE expense_date >= year_begin
    AND expense_date < (year_begin + interval '1 year')::date
    AND expense_type <> 'employee_bonus';

  DELETE FROM finance_dashboard_metrics;

  INSERT INTO finance_dashboard_metrics(metric_key, title, metric_group, value, sort)
  VALUES
    (
      'revenue_month',
      U&'\0412\044b\0440\0443\0447\043a\0430 \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      COALESCE((SELECT SUM(order_sum) FROM orders WHERE date >= month_begin AND date < (month_begin + interval '1 month')::date), 0),
      10
    ),
    (
      'revenue_year',
      U&'\0412\044b\0440\0443\0447\043a\0430 \0437\0430 \0433\043e\0434',
      'year',
      COALESCE((SELECT SUM(order_sum) FROM orders WHERE date >= year_begin AND date < (year_begin + interval '1 year')::date), 0),
      20
    ),
    (
      'paid_month',
      U&'\041e\043f\043b\0430\0447\0435\043d\043e \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      COALESCE((SELECT SUM(amount) FROM order_payments WHERE payment_direction = 'incoming' AND payment_date >= month_begin AND payment_date < (month_begin + interval '1 month')::date), 0),
      30
    ),
    (
      'paid_year',
      U&'\041e\043f\043b\0430\0447\0435\043d\043e \0437\0430 \0433\043e\0434',
      'year',
      COALESCE((SELECT SUM(amount) FROM order_payments WHERE payment_direction = 'incoming' AND payment_date >= year_begin AND payment_date < (year_begin + interval '1 year')::date), 0),
      40
    ),
    (
      'profit_month',
      U&'\0427\0438\0441\0442\0430\044f \043f\0440\0438\0431\044b\043b\044c \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      COALESCE((SELECT SUM(profit_sum) FROM orders WHERE date >= month_begin AND date < (month_begin + interval '1 month')::date), 0) - business_expenses_month,
      50
    ),
    (
      'profit_year',
      U&'\0427\0438\0441\0442\0430\044f \043f\0440\0438\0431\044b\043b\044c \0437\0430 \0433\043e\0434',
      'year',
      COALESCE((SELECT SUM(profit_sum) FROM orders WHERE date >= year_begin AND date < (year_begin + interval '1 year')::date), 0) - business_expenses_year,
      60
    ),
    (
      'expenses_month',
      U&'\0420\0430\0441\0445\043e\0434\044b \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      COALESCE((SELECT SUM(items_total_cost) FROM orders WHERE date >= month_begin AND date < (month_begin + interval '1 month')::date), 0) + business_expenses_month,
      70
    ),
    (
      'expenses_year',
      U&'\0420\0430\0441\0445\043e\0434\044b \0437\0430 \0433\043e\0434',
      'year',
      COALESCE((SELECT SUM(items_total_cost) FROM orders WHERE date >= year_begin AND date < (year_begin + interval '1 year')::date), 0) + business_expenses_year,
      80
    ),
    (
      'business_expenses_month',
      U&'\041e\043f\0435\0440\0430\0446\0438\043e\043d\043d\044b\0435 \0440\0430\0441\0445\043e\0434\044b \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      business_expenses_month,
      85
    ),
    (
      'salary_debt',
      U&'\0414\043e\043b\0433 \043f\043e \0417\041f',
      'balance',
      COALESCE((SELECT SUM(GREATEST(salary_debt, 0)) FROM employee_salary_summary), 0),
      86
    ),
    (
      'receivable',
      U&'\041d\0430\043c \0434\043e\043b\0436\043d\044b',
      'balance',
      COALESCE((SELECT SUM(GREATEST(payment_due, 0)) FROM orders), 0),
      90
    ),
    (
      'we_owe_contractors',
      U&'\041c\044b \0434\043e\043b\0436\043d\044b \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\0430\043c',
      'balance',
      COALESCE((SELECT SUM(debt_to_contractor) FROM contractors), 0),
      100
    ),
    (
      'contractors_owe_us',
      U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442\044b \0434\043e\043b\0436\043d\044b \043d\0430\043c',
      'balance',
      COALESCE((SELECT SUM(contractor_debt_to_us) FROM contractors), 0),
      110
    ),
    (
      'orders_month',
      U&'\0417\0430\043a\0430\0437\043e\0432 \0437\0430 \043c\0435\0441\044f\0446',
      'orders',
      COALESCE((SELECT COUNT(*) FROM orders WHERE date >= month_begin AND date < (month_begin + interval '1 month')::date), 0),
      120
    ),
    (
      'orders_active',
      U&'\0410\043a\0442\0438\0432\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432',
      'orders',
      COALESCE((
        SELECT COUNT(*)
        FROM orders o
        LEFT JOIN order_statuses os ON os.id = o.order_status
        WHERE COALESCE(os.name, '') NOT IN (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', U&'\041e\0442\043c\0435\043d\0435\043d')
      ), 0),
      130
    ),
    (
      'orders_unpaid',
      U&'\041d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432',
      'orders',
      COALESCE((SELECT COUNT(*) FROM orders WHERE payment_due > 0), 0),
      140
    ),
    (
      'avg_order_month',
      U&'\0421\0440\0435\0434\043d\0438\0439 \0447\0435\043a \0437\0430 \043c\0435\0441\044f\0446',
      'month',
      COALESCE((SELECT AVG(order_sum) FROM orders WHERE date >= month_begin AND date < (month_begin + interval '1 month')::date), 0),
      150
    );

  DELETE FROM finance_dashboard_monthly;

  INSERT INTO finance_dashboard_monthly(month_start, month_label, revenue, paid, profit, expenses, receivable)
  SELECT
    months.month_start,
    to_char(months.month_start, 'MM.YY'),
    COALESCE(SUM(o.order_sum), 0),
    COALESCE((
      SELECT SUM(op.amount)
      FROM order_payments op
      WHERE op.payment_direction = 'incoming'
        AND op.payment_date >= months.month_start
        AND op.payment_date < (months.month_start + interval '1 month')::date
    ), 0),
    COALESCE(SUM(o.profit_sum), 0) - COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.expense_date >= months.month_start
        AND be.expense_date < (months.month_start + interval '1 month')::date
        AND be.expense_type <> 'employee_bonus'
    ), 0),
    COALESCE(SUM(o.items_total_cost), 0) + COALESCE((
      SELECT SUM(be.amount)
      FROM business_expenses be
      WHERE be.expense_date >= months.month_start
        AND be.expense_date < (months.month_start + interval '1 month')::date
        AND be.expense_type <> 'employee_bonus'
    ), 0),
    COALESCE(SUM(GREATEST(o.payment_due, 0)), 0)
  FROM generate_series(
    (date_trunc('month', current_date) - interval '11 months')::date,
    date_trunc('month', current_date)::date,
    interval '1 month'
  ) AS months(month_start)
  LEFT JOIN orders o
    ON o.date >= months.month_start
   AND o.date < (months.month_start + interval '1 month')::date
  GROUP BY months.month_start
  ORDER BY months.month_start;

  DELETE FROM finance_dashboard_series;

  INSERT INTO finance_dashboard_series(month_start, month_label, metric_key, metric_name, value, sort)
  SELECT month_start, month_label, 'revenue', U&'\0412\044b\0440\0443\0447\043a\0430', revenue, 10
  FROM finance_dashboard_monthly
  UNION ALL
  SELECT month_start, month_label, 'paid', U&'\041e\043f\043b\0430\0447\0435\043d\043e', paid, 20
  FROM finance_dashboard_monthly
  UNION ALL
  SELECT month_start, month_label, 'profit', U&'\041f\0440\0438\0431\044b\043b\044c', profit, 30
  FROM finance_dashboard_monthly
  UNION ALL
  SELECT month_start, month_label, 'expenses', U&'\0420\0430\0441\0445\043e\0434\044b', expenses, 40
  FROM finance_dashboard_monthly
  UNION ALL
  SELECT month_start, month_label, 'receivable', U&'\0414\0435\0431\0438\0442\043e\0440\043a\0430', receivable, 50
  FROM finance_dashboard_monthly;
END;
$$ LANGUAGE plpgsql;

SELECT refresh_finance_dashboard_metrics();

CREATE OR REPLACE FUNCTION refresh_salary_and_finance_trigger()
RETURNS trigger AS $$
BEGIN
  PERFORM refresh_employee_salary_tables();
  PERFORM refresh_finance_dashboard_metrics();
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS business_expenses_refresh_finance ON business_expenses;
CREATE TRIGGER business_expenses_refresh_finance
AFTER INSERT OR UPDATE OR DELETE ON business_expenses
FOR EACH ROW
EXECUTE FUNCTION refresh_salary_and_finance_trigger();

DROP TRIGGER IF EXISTS employees_refresh_salary ON employees;
CREATE TRIGGER employees_refresh_salary
AFTER INSERT OR UPDATE OF salary_fixed, order_percent, is_active, position, full_name OR DELETE ON employees
FOR EACH ROW
EXECUTE FUNCTION refresh_salary_and_finance_trigger();

DROP TRIGGER IF EXISTS orders_refresh_salary ON orders;
CREATE TRIGGER orders_refresh_salary
AFTER INSERT OR UPDATE OF date, manager_employee, order_sum, paid_amount, payment_due, profit_sum, items_total_cost OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION refresh_salary_and_finance_trigger();

CREATE TABLE IF NOT EXISTS product_application_methods (
  id serial PRIMARY KEY,
  name character varying(255) NOT NULL,
  sort integer,
  is_active boolean DEFAULT true
);
ALTER TABLE product_application_methods ADD COLUMN IF NOT EXISTS category integer REFERENCES product_categories(id) ON DELETE CASCADE;

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
  order_number character varying(255),
  customer integer,
  customer_name character varying(255),
  customer_company integer,
  customer_company_name character varying(255),
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  price_per_unit numeric(14,2),
  order_sum numeric(14,2),
  blank_source character varying(255),
  blank_ordered boolean NOT NULL DEFAULT false,
  product_category integer,
  product_subcategory integer,
  application_method integer,
  contractor_1 integer,
  contractor_1_cost numeric(14,2),
  technical_task_text text,
  production_comment text,
  url character varying(255),
  item_status character varying(255),
  office_status character varying(255),
  production_status integer,
  date timestamp without time zone,
  deadline timestamp without time zone
);

CREATE TABLE IF NOT EXISTS screen_printing_work (
  id integer PRIMARY KEY,
  "order" integer,
  order_number character varying(255),
  customer integer,
  customer_name character varying(255),
  customer_company integer,
  customer_company_name character varying(255),
  manager_employee integer,
  product_name character varying(255),
  quantity numeric(10,0),
  price_per_unit numeric(14,2),
  order_sum numeric(14,2),
  blank_source character varying(255),
  blank_ordered boolean NOT NULL DEFAULT false,
  product_category integer,
  product_subcategory integer,
  application_method integer,
  contractor_1 integer,
  contractor_1_cost numeric(14,2),
  technical_task_text text,
  production_comment text,
  url character varying(255),
  item_status character varying(255),
  office_status character varying(255),
  production_status integer,
  date timestamp without time zone,
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
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS order_number character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS customer_name character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS customer_company_name character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS production_comment text;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS date timestamp without time zone;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS item_status character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS price_per_unit numeric(14,2);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS order_sum numeric(14,2);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS blank_source character varying(255);
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS blank_ordered boolean NOT NULL DEFAULT false;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS product_category integer;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS product_subcategory integer;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS application_method integer;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS contractor_1 integer;
ALTER TABLE production_work ADD COLUMN IF NOT EXISTS contractor_1_cost numeric(14,2);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS order_number character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS customer_name character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS customer_company_name character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS production_comment text;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS date timestamp without time zone;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS item_status character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS price_per_unit numeric(14,2);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS order_sum numeric(14,2);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS blank_source character varying(255);
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS blank_ordered boolean NOT NULL DEFAULT false;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS product_category integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS product_subcategory integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS application_method integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS contractor_1 integer;
ALTER TABLE screen_printing_work ADD COLUMN IF NOT EXISTS contractor_1_cost numeric(14,2);
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

-- Bootstrap routing used while the base order schema is assembled. A final
-- capability-aware definition replaces it after contractor_capabilities is
-- created near the end of this installation script.
CREATE OR REPLACE FUNCTION apply_category_contractors_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  matched_contractors integer[];
  needs_blank boolean := false;
  routed_contractor integer;
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.product_category IS DISTINCT FROM OLD.product_category
     OR NEW.product_subcategory IS DISTINCT FROM OLD.product_subcategory
     OR NEW.application_method IS DISTINCT FROM OLD.application_method
     OR NEW.blank_source IS DISTINCT FROM OLD.blank_source THEN
    SELECT COALESCE(pc.name IN (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447'), false)
      INTO needs_blank
      FROM product_categories pc
      WHERE pc.id = NEW.product_category;
    needs_blank := COALESCE(needs_blank, false);

    IF NEW.product_subcategory IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM product_subcategories ps
         WHERE ps.id = NEW.product_subcategory
           AND ps.category = NEW.product_category
           AND COALESCE(ps.is_active, true) = true
       ) THEN
      NEW.product_subcategory := NULL;
    END IF;

    IF NEW.application_method IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM product_application_methods pam
         WHERE pam.id = NEW.application_method
           AND COALESCE(pam.is_active, true) = true
           AND (pam.category = NEW.product_category OR pam.category IS NULL)
       ) THEN
      NEW.application_method := NULL;
    END IF;

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

    routed_contractor := COALESCE(matched_contractors[2], matched_contractors[1]);

    IF needs_blank THEN
      IF NEW.blank_source IS NULL OR NEW.blank_source NOT IN ('supplier', 'customer', 'warehouse', 'contractor') THEN
        NEW.blank_source := 'supplier';
      END IF;

      IF NEW.blank_source IN ('customer', 'warehouse', 'contractor') THEN
        NEW.contractor_1 := NULL;
        NEW.contractor_1_cost := 0;
        NEW.blank_ordered := false;
      END IF;

      NEW.contractor_2 := routed_contractor;
    ELSE
      NEW.blank_source := 'none';
      NEW.blank_ordered := false;
      NEW.contractor_1 := matched_contractors[1];
      NEW.contractor_2 := matched_contractors[2];
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_apply_category_contractors
BEFORE INSERT OR UPDATE OF product_category, product_subcategory, application_method, blank_source ON orders_items
FOR EACH ROW
EXECUTE FUNCTION apply_category_contractors_trigger();

CREATE OR REPLACE FUNCTION symbolika_zero_internal_contractor_costs_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.contractor_1 IS NOT NULL AND EXISTS (
    SELECT 1 FROM contractors c
    WHERE c.id = NEW.contractor_1 AND COALESCE(c.is_internal_production, false)
  ) THEN
    NEW.contractor_1_cost := 0;
  END IF;

  IF NEW.contractor_2 IS NOT NULL AND EXISTS (
    SELECT 1 FROM contractors c
    WHERE c.id = NEW.contractor_2 AND COALESCE(c.is_internal_production, false)
  ) THEN
    NEW.contractor_2_cost := 0;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER symbolika_zero_internal_contractor_costs
BEFORE INSERT OR UPDATE OF contractor_1, contractor_2, contractor_1_cost, contractor_2_cost ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_zero_internal_contractor_costs_trigger();

UPDATE orders_items oi
SET contractor_1_cost = 0
WHERE EXISTS (
  SELECT 1 FROM contractors c
  WHERE c.id = oi.contractor_1 AND COALESCE(c.is_internal_production, false)
)
AND COALESCE(oi.contractor_1_cost, 0) <> 0;

UPDATE orders_items oi
SET contractor_2_cost = 0
WHERE EXISTS (
  SELECT 1 FROM contractors c
  WHERE c.id = oi.contractor_2 AND COALESCE(c.is_internal_production, false)
)
AND COALESCE(oi.contractor_2_cost, 0) <> 0;

UPDATE orders_items
SET unit_cost = ROUND(COALESCE(contractor_1_cost, 0) + COALESCE(contractor_2_cost, 0), 2),
    total_cost = ROUND((COALESCE(contractor_1_cost, 0) + COALESCE(contractor_2_cost, 0)) * COALESCE(quantity, 0), 2),
    profit_sum = ROUND(
      COALESCE(order_sum, 0)
      - (COALESCE(contractor_1_cost, 0) + COALESCE(contractor_2_cost, 0)) * COALESCE(quantity, 0)
      - COALESCE(manager_commission_sum, 0)
      - COALESCE(tax_sum, 0),
      2
    ),
    margin_percent = CASE
      WHEN COALESCE(order_sum, 0) > 0 THEN ROUND((
        COALESCE(order_sum, 0)
        - (COALESCE(contractor_1_cost, 0) + COALESCE(contractor_2_cost, 0)) * COALESCE(quantity, 0)
        - COALESCE(manager_commission_sum, 0)
        - COALESCE(tax_sum, 0)
      ) / order_sum * 100, 2)
      ELSE 0
    END;

WITH item_totals AS (
  SELECT
    oi."order" AS order_id,
    ROUND(COALESCE(SUM(oi.order_sum), 0), 2) AS order_sum,
    ROUND(COALESCE(SUM(oi.total_cost), 0), 2) AS items_total_cost,
    ROUND(COALESCE(SUM(oi.manager_commission_sum), 0), 2) AS items_manager_commission_sum,
    ROUND(COALESCE(SUM(oi.tax_sum), 0), 2) AS items_tax_sum
  FROM orders_items oi
  GROUP BY oi."order"
)
UPDATE orders o
SET order_sum = totals.order_sum,
    items_total_cost = totals.items_total_cost,
    items_manager_commission_sum = totals.items_manager_commission_sum,
    items_tax_sum = totals.items_tax_sum,
    profit_sum = ROUND(
      totals.order_sum - totals.items_total_cost
      - totals.items_manager_commission_sum - totals.items_tax_sum,
      2
    ),
    margin_percent = CASE
      WHEN totals.order_sum > 0 THEN ROUND((
        totals.order_sum - totals.items_total_cost
        - totals.items_manager_commission_sum - totals.items_tax_sum
      ) / totals.order_sum * 100, 2)
      ELSE 0
    END
FROM item_totals totals
WHERE totals.order_id = o.id;

UPDATE contractors c
SET items_total_cost = 0,
    balance = COALESCE(c.payments_total_out, 0),
    debt_to_contractor = 0,
    contractor_debt_to_us = GREATEST(COALESCE(c.payments_total_out, 0), 0)
WHERE COALESCE(c.is_internal_production, false);

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
    AND EXISTS (
      SELECT 1
      FROM orders_items oi
      LEFT JOIN product_categories pc ON pc.id = oi.product_category
      WHERE oi."order" = o.id
        AND COALESCE(pc.office_applicable, true)
    )
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
    AND EXISTS (
      SELECT 1
      FROM orders_items oi
      LEFT JOIN product_categories pc ON pc.id = oi.product_category
      WHERE oi."order" = o.id
        AND COALESCE(pc.office_applicable, true)
    )
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
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(pc.office_applicable, true)
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
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(pc.office_applicable, true)
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
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  WHERE oi.id = item_id
    AND o.shipping_method = 'office_pickup'
    AND COALESCE(pc.office_applicable, true)
    AND COALESCE(o.office_status, 'not_in_office') <> 'issued';
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
  FROM orders_items oi
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND COALESCE(pc.office_applicable, true);

  IF items_count = 0 THEN
    RETURN;
  END IF;

  SELECT
    bool_and(office_status = 'issued'),
    bool_and(office_status IN ('in_office', 'issued')),
    bool_or(COALESCE(office_status, 'not_in_office') = 'not_in_office')
  INTO all_issued, all_in_office, has_not_in_office
  FROM orders_items oi
  LEFT JOIN product_categories pc ON pc.id = oi.product_category
  WHERE oi."order" = order_id
    AND COALESCE(pc.office_applicable, true);

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
    WHEN 'send_to_work' THEN 'sent_to_work'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    ELSE COALESCE(status_value, 'new')
  END
$$;

-- Bootstrap readiness for the legacy route fields. The capability-aware
-- definition later in this script deliberately replaces it after the route
-- catalogue exists.
CREATE OR REPLACE FUNCTION symbolika_order_work_readiness(order_id integer)
RETURNS TABLE (
  ready_for_work boolean,
  missing_count integer,
  missing_fields text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  order_row record;
  item_row record;
  missing_values text[] := ARRAY[]::text[];
  item_label text;
BEGIN
  SELECT o.* INTO order_row
  FROM orders o
  WHERE o.id = order_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 1, U&'\0417\0430\043a\0430\0437 \043d\0435 \043d\0430\0439\0434\0435\043d';
    RETURN;
  END IF;

  IF order_row.customer IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043a\043b\0438\0435\043d\0442');
  END IF;
  IF order_row.manager_employee IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043c\0435\043d\0435\0434\0436\0435\0440');
  END IF;
  IF order_row.date IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0434\0430\0442\0430');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM orders_items oi WHERE oi."order" = order_id) THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043d\0435\0442 \043f\043e\0437\0438\0446\0438\0439');
  END IF;

  FOR item_row IN
    SELECT oi.*
    FROM orders_items oi
    WHERE oi."order" = order_id
      AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ORDER BY oi.id
  LOOP
    item_label := COALESCE(NULLIF(BTRIM(item_row.product_name), ''), U&'\041f\043e\0437\0438\0446\0438\044f #' || item_row.id::text);

    IF NULLIF(BTRIM(item_row.product_name), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \043d\0430\0437\0432\0430\043d\0438\0435');
    END IF;
    IF COALESCE(item_row.quantity, 0) <= 0 THEN
      missing_values := array_append(missing_values, item_label || U&': \043a\043e\043b\0438\0447\0435\0441\0442\0432\043e');
    END IF;
    IF NULLIF(BTRIM(item_row.technical_task_text), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \0422\0417');
    END IF;
    IF NULLIF(BTRIM(item_row.url), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \0441\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442');
    END IF;

    IF symbolika_normalize_item_status(item_row.item_status) = 'layout_revision'
       AND (
         NULLIF(BTRIM(item_row.url), '') IS NULL
         OR item_row.url IS NOT DISTINCT FROM item_row.layout_revision_url_snapshot
       ) THEN
      missing_values := array_append(missing_values, item_label || U&': \043e\0431\043d\043e\0432\0438\0442\0435 \0441\0441\044b\043b\043a\0443 \043d\0430 \043c\0430\043a\0435\0442');
    END IF;
  END LOOP;

  RETURN QUERY SELECT
    COALESCE(array_length(missing_values, 1), 0) = 0,
    COALESCE(array_length(missing_values, 1), 0),
    array_to_string(missing_values, '||');
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_validate_order_workflow_transition_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_status_name text;
  new_status_name text;
  readiness record;
  transition_allowed boolean := false;
BEGIN
  IF NEW.order_status IS NOT DISTINCT FROM OLD.order_status OR pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT name INTO old_status_name FROM order_statuses WHERE id = OLD.order_status;
  SELECT name INTO new_status_name FROM order_statuses WHERE id = NEW.order_status;

  transition_allowed := CASE
    WHEN old_status_name IN (U&'\041d\043e\0432\044b\0439', U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435')
      THEN new_status_name IN (U&'\041d\043e\0432\044b\0439', U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', U&'\0412 \0440\0430\0431\043e\0442\0435')
    WHEN old_status_name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
      THEN new_status_name IN (U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', U&'\0412 \0440\0430\0431\043e\0442\0435')
    WHEN old_status_name IN (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', U&'\0412 \0440\0430\0431\043e\0442\0435')
      THEN new_status_name IN (U&'\0412 \0440\0430\0431\043e\0442\0435', U&'\0413\043e\0442\043e\0432', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d')
    WHEN old_status_name = U&'\0413\043e\0442\043e\0432'
      THEN new_status_name IN (U&'\0413\043e\0442\043e\0432', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d')
    WHEN old_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
      THEN new_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
    ELSE false
  END;

  IF NOT transition_allowed THEN
    RAISE EXCEPTION 'Недопустимый переход статуса заказа: % -> %', COALESCE(old_status_name, '-'), COALESCE(new_status_name, '-');
  END IF;

  IF new_status_name = U&'\0412 \0440\0430\0431\043e\0442\0435'
     AND old_status_name IN (
       U&'\041d\043e\0432\044b\0439',
       U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435',
       U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
     ) THEN
    SELECT * INTO readiness FROM symbolika_order_work_readiness(NEW.id);
    IF NOT COALESCE(readiness.ready_for_work, false) THEN
      RAISE EXCEPTION 'Заказ нельзя отправить в работу. Заполните: %', replace(COALESCE(readiness.missing_fields, ''), '||', ', ');
    END IF;
  END IF;

  RETURN NEW;
END;
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
    WHEN bool_and(item_status IN ('delivered', 'cancelled')) AND bool_or(item_status = 'delivered') THEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
    WHEN bool_and(item_status IN ('ready', 'cancelled')) AND bool_or(item_status = 'ready') THEN U&'\0413\043e\0442\043e\0432'
    WHEN bool_or(item_status = 'layout_revision') THEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430'
    WHEN bool_or(item_status = 'cancellation_requested') THEN U&'\0412 \0440\0430\0431\043e\0442\0435'
    WHEN bool_or(item_status = 'sent_to_work') THEN U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443'
    WHEN bool_or(item_status = 'in_work') THEN U&'\0412 \0440\0430\0431\043e\0442\0435'
    WHEN bool_or(item_status = 'approval') THEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435'
    ELSE U&'\041d\043e\0432\044b\0439'
  END
  INTO next_status_name
  FROM normalized;

  next_status_id := symbolika_order_status_id(next_status_name);

  IF next_status_id IS NOT NULL THEN
    UPDATE orders
       SET order_status = next_status_id,
           office_status = CASE
             WHEN next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'issued'
             ELSE office_status
           END
     WHERE id = order_id
       AND (
         order_status IS DISTINCT FROM next_status_id
         OR (
           next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
           AND office_status IS DISTINCT FROM 'issued'
         )
       );

    IF next_status_name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN
      UPDATE orders_items
         SET office_status = 'issued',
             shipping_method = 'office_pickup'
       WHERE "order" = order_id
         AND office_status IS DISTINCT FROM 'issued';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_item_status_from_production_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_item_status character varying;
  previous_item_status character varying;
  item_transition_allowed boolean;
  ready_production_status integer;
  parent_order_delivered boolean := false;
BEGIN
  -- A position added to an already ready/delivered order starts its own
  -- workflow and must never inherit the final state of the parent order.
  IF TG_OP = 'INSERT' THEN
    NEW.item_status := 'new';
    NEW.office_status := 'not_in_office';
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.production_status IS DISTINCT FROM OLD.production_status THEN
    next_item_status := symbolika_item_status_from_production(NEW.production_status);
  ELSE
    next_item_status := NULL;
  END IF;

  IF next_item_status IS NOT NULL THEN
    NEW.item_status := next_item_status;
  ELSE
    NEW.item_status := symbolika_normalize_item_status(NEW.item_status);
  END IF;

  previous_item_status := CASE
    WHEN TG_OP = 'INSERT' THEN NULL
    ELSE symbolika_normalize_item_status(OLD.item_status)
  END;

  IF NEW.item_status = 'layout_revision'
     AND previous_item_status IS DISTINCT FROM 'layout_revision' THEN
    NEW.layout_revision_url_snapshot := NEW.url;
  END IF;

  -- Office issue and the public item status describe the same final state.
  -- Whichever field was changed by the UI becomes the source of truth.
  IF TG_OP = 'INSERT' OR NEW.office_status IS DISTINCT FROM OLD.office_status THEN
    IF NEW.office_status = 'issued' THEN
      NEW.item_status := 'delivered';
      NEW.shipping_method := 'office_pickup';
    ELSIF NEW.office_status = 'in_office' THEN
      NEW.item_status := 'ready';
      NEW.shipping_method := 'office_pickup';
    END IF;
  ELSIF NEW.item_status IS DISTINCT FROM previous_item_status THEN
    IF NEW.item_status = 'delivered' THEN
      NEW.office_status := 'issued';
      NEW.shipping_method := 'office_pickup';
    ELSIF previous_item_status = 'delivered' AND OLD.office_status = 'issued' THEN
      NEW.office_status := CASE WHEN NEW.item_status = 'ready' THEN 'in_office' ELSE 'not_in_office' END;
      NEW.shipping_method := CASE WHEN NEW.item_status = 'ready' THEN 'office_pickup' ELSE NULL END;
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM orders o
    JOIN order_statuses os ON os.id = o.order_status
    WHERE o.id = NEW."order"
      AND os.name = U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d'
  ) INTO parent_order_delivered;

  -- A delivered order cannot contain an item that is merely waiting in the office.
  IF parent_order_delivered AND TG_OP <> 'INSERT' THEN
    NEW.office_status := 'issued';
  END IF;

  -- A position physically accepted by the office has completed production,
  -- even if the workshop forgot to set its status before handing it over.
  IF NEW.office_status IN ('in_office', 'issued') THEN
    SELECT ps.id INTO ready_production_status
    FROM production_statuses ps
    WHERE ps.name = U&'\0413\043e\0442\043e\0432'
    ORDER BY ps.id
    LIMIT 1;

    IF ready_production_status IS NOT NULL THEN
      NEW.production_status := ready_production_status;
    END IF;

    NEW.item_status := CASE
      WHEN NEW.office_status = 'issued' THEN 'delivered'
      ELSE 'ready'
    END;
    NEW.shipping_method := 'office_pickup';
  END IF;

  IF TG_OP = 'UPDATE'
     AND pg_trigger_depth() = 1
     AND NEW.production_status IS NOT DISTINCT FROM OLD.production_status
     AND NEW.office_status IS NOT DISTINCT FROM OLD.office_status
     AND NEW.item_status IS DISTINCT FROM previous_item_status THEN
    item_transition_allowed := CASE
      WHEN previous_item_status IN ('new', 'approval') THEN NEW.item_status IN ('new', 'approval', 'sent_to_work', 'in_work')
      WHEN previous_item_status = 'layout_revision' THEN NEW.item_status IN ('layout_revision', 'sent_to_work', 'in_work')
      WHEN previous_item_status IN ('sent_to_work', 'in_work') THEN NEW.item_status IN ('sent_to_work', 'in_work', 'cancellation_requested', 'ready', 'delivered')
      WHEN previous_item_status = 'cancellation_requested' THEN NEW.item_status IN ('cancellation_requested', 'cancelled')
      WHEN previous_item_status = 'ready' THEN NEW.item_status IN ('ready', 'delivered')
      WHEN previous_item_status = 'delivered' THEN NEW.item_status = 'delivered'
      ELSE NEW.item_status = previous_item_status
    END;

    IF NOT COALESCE(item_transition_allowed, false) THEN
      RAISE EXCEPTION 'Недопустимый переход статуса позиции: % -> %', previous_item_status, NEW.item_status;
    END IF;

    IF NEW.item_status IN ('sent_to_work', 'in_work')
       AND previous_item_status IN ('new', 'approval', 'layout_revision') THEN
      IF NULLIF(BTRIM(COALESCE(NEW.product_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните наименование';
      END IF;
      IF COALESCE(NEW.quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните количество';
      END IF;
      IF NULLIF(BTRIM(COALESCE(NEW.technical_task_text, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: заполните ТЗ';
      END IF;
      IF NULLIF(BTRIM(COALESCE(NEW.url, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Позицию нельзя запустить в работу: загрузите макет';
      END IF;
      IF previous_item_status = 'layout_revision'
         AND BTRIM(COALESCE(NEW.url, '')) = BTRIM(COALESCE(OLD.layout_revision_url_snapshot, '')) THEN
        RAISE EXCEPTION 'Позицию нельзя повторно запустить в работу: загрузите обновленный макет';
      END IF;
      NEW.layout_revision_url_snapshot := NULL;
    END IF;
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
  previous_status_name text;
  next_item_status character varying;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT name INTO status_name
  FROM order_statuses
  WHERE id = NEW.order_status;

  SELECT name INTO previous_status_name
  FROM order_statuses
  WHERE id = OLD.order_status;

  next_item_status := CASE status_name
    WHEN U&'\041d\043e\0432\044b\0439' THEN 'new'
    WHEN U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435' THEN 'approval'
    WHEN U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN 'layout_revision'
    WHEN U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443' THEN 'sent_to_work'
    WHEN U&'\0412 \0440\0430\0431\043e\0442\0435' THEN 'in_work'
    WHEN U&'\0413\043e\0442\043e\0432' THEN 'ready'
    WHEN U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d' THEN 'delivered'
    WHEN U&'\041e\0442\043c\0435\043d\0435\043d' THEN 'cancelled'
    ELSE NULL
  END;

  IF next_item_status IS NOT NULL THEN
    IF next_item_status = 'in_work'
       AND previous_status_name = U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430' THEN
      UPDATE orders_items
         SET item_status = 'in_work',
             layout_revision_url_snapshot = NULL
       WHERE "order" = NEW.id
         AND symbolika_normalize_item_status(item_status) = 'layout_revision';
    ELSE
      UPDATE orders_items
         SET item_status = next_item_status,
             layout_revision_url_snapshot = CASE WHEN next_item_status = 'in_work' THEN NULL ELSE layout_revision_url_snapshot END,
             office_status = CASE WHEN next_item_status = 'delivered' THEN 'issued' ELSE office_status END,
             shipping_method = CASE WHEN next_item_status = 'delivered' THEN 'office_pickup' ELSE shipping_method END
       WHERE "order" = NEW.id
         AND (
           symbolika_normalize_item_status(item_status) IS DISTINCT FROM next_item_status
           OR (next_item_status = 'delivered' AND office_status IS DISTINCT FROM 'issued')
         );
    END IF;

    IF next_item_status = 'delivered' THEN
      UPDATE orders
         SET office_status = 'issued'
       WHERE id = NEW.id
         AND office_status IS DISTINCT FROM 'issued';
    END IF;
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

  IF TG_OP = 'UPDATE'
     AND NEW.office_status IS DISTINCT FROM OLD.office_status
     AND pg_trigger_depth() = 1
     AND NEW.office_status IN ('in_office', 'issued', 'not_in_office') THEN
    UPDATE orders_items
       SET office_status = NEW.office_status,
           item_status = CASE
             WHEN NEW.office_status = 'issued' THEN 'delivered'
             WHEN NEW.office_status = 'in_office' THEN 'ready'
             ELSE item_status
           END
     WHERE "order" = NEW.id
       AND (
         office_status IS DISTINCT FROM NEW.office_status
         OR (
           NEW.office_status = 'issued'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
         )
         OR (
           NEW.office_status = 'in_office'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'ready'
         )
       );
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
     SET office_status = NEW.office_status,
         item_status = CASE
           WHEN NEW.office_status = 'issued' THEN 'delivered'
           WHEN NEW.office_status = 'in_office' THEN 'ready'
           ELSE item_status
         END
   WHERE id = NEW.id
     AND (
       office_status IS DISTINCT FROM NEW.office_status
       OR (
         NEW.office_status = 'issued'
         AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
       )
       OR (
         NEW.office_status = 'in_office'
         AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'ready'
       )
     )
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
       SET office_status = NEW.office_status,
           item_status = CASE
             WHEN NEW.office_status = 'issued' THEN 'delivered'
             WHEN NEW.office_status = 'in_office' THEN 'ready'
             ELSE item_status
           END
     WHERE "order" = NEW.id
       AND (
         office_status IS DISTINCT FROM NEW.office_status
         OR (
           NEW.office_status = 'issued'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'delivered'
         )
         OR (
           NEW.office_status = 'in_office'
           AND symbolika_normalize_item_status(item_status) IS DISTINCT FROM 'ready'
         )
       );
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
DECLARE
  order_status_name text;
  item_work_status character varying;
BEGIN
  DELETE FROM production_work WHERE id = item_id;
  DELETE FROM screen_printing_work WHERE id = item_id;
  DELETE FROM contractor_work WHERE order_item = item_id;

  SELECT os.name, symbolika_normalize_item_status(oi.item_status)
    INTO order_status_name, item_work_status
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN order_statuses os ON os.id = o.order_status
  WHERE oi.id = item_id;

  IF item_work_status NOT IN ('sent_to_work', 'in_work', 'layout_revision', 'ready', 'cancelled')
     AND order_status_name NOT IN (
       U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443',
       U&'\0412 \0440\0430\0431\043e\0442\0435',
       U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430',
       U&'\0413\043e\0442\043e\0432',
       U&'\041e\0442\043c\0435\043d\0435\043d'
     ) THEN
    RETURN;
  END IF;

  INSERT INTO production_work (
    id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
    product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
    product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
    technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
  )
  SELECT
    oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
    oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
    oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
    oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (
      c1.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
      OR c2.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
      OR COALESCE(oi.internal_route_production, false)
    );

  INSERT INTO screen_printing_work (
    id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
    product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
    product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
    technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
  )
  SELECT
    oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
    oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
    oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
    oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
  LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
  WHERE oi.id = item_id
    AND (
      c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
      OR c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
      OR COALESCE(oi.internal_route_screen, false)
    );

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
BEFORE INSERT OR UPDATE OF item_status, production_status, office_status ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_item_status_from_production_trigger();

UPDATE orders_items
SET production_status = (
      SELECT ps.id
      FROM production_statuses ps
      WHERE ps.name = U&'\0413\043e\0442\043e\0432'
      ORDER BY ps.id
      LIMIT 1
    )
WHERE office_status IN ('in_office', 'issued')
  AND production_status IS DISTINCT FROM (
    SELECT ps.id
    FROM production_statuses ps
    WHERE ps.name = U&'\0413\043e\0442\043e\0432'
    ORDER BY ps.id
    LIMIT 1
  );

CREATE TRIGGER symbolika_recalc_order_status_from_items
AFTER INSERT OR UPDATE OF item_status, production_status, office_status, "order" OR DELETE ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_recalc_order_status_from_items_trigger();

CREATE TRIGGER symbolika_validate_order_workflow_transition
BEFORE UPDATE OF order_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_validate_order_workflow_transition_trigger();

CREATE TRIGGER symbolika_apply_order_status_to_items
AFTER INSERT OR UPDATE OF order_status ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_order_status_to_items_trigger();

UPDATE orders
   SET order_status = symbolika_order_status_id(U&'\0412 \0440\0430\0431\043e\0442\0435')
 WHERE order_status = symbolika_order_status_id(U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443');

UPDATE orders_items
   SET item_status = 'in_work'
 WHERE symbolika_normalize_item_status(item_status) = 'sent_to_work';

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

  -- Updating item tax below fires the item trigger again. A transaction-local
  -- guard prevents a recursive recalculation while keeping independent calls
  -- in other transactions safe.
  IF current_setting('symbolika.recalculating_order_finance', true) = '1' THEN
    RETURN;
  END IF;

  IF NOT pg_try_advisory_xact_lock(hashtext('recalc_order_payment_totals'), order_id) THEN
    RETURN;
  END IF;

  PERFORM set_config('symbolika.recalculating_order_finance', '1', true);

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

  -- Payments and positions are both laid out as cumulative ranges. Their
  -- overlap is the amount of a concrete payment applied to a concrete item.
  -- This preserves the established top-to-bottom allocation rule and makes
  -- mixed payments exact: only the overlap with a taxable payment is taxed.
  WITH item_ranges AS (
    SELECT
      oi.id,
      COALESCE(oi.order_sum, 0)::numeric AS item_sum,
      COALESCE(
        SUM(COALESCE(oi.order_sum, 0)) OVER (
          ORDER BY oi.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::numeric AS range_start,
      SUM(COALESCE(oi.order_sum, 0)) OVER (
        ORDER BY oi.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::numeric AS range_end
    FROM orders_items oi
    WHERE oi."order" = order_id
      AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
  ),
  payment_steps AS (
    SELECT
      pa.id,
      pa.payment,
      CASE
        WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -1
        ELSE 1
      END::numeric AS direction_sign,
      COALESCE(pa.amount, 0)::numeric AS allocated_amount,
      COALESCE(pt.tax_percent, 0)::numeric AS tax_percent,
      COALESCE(
        SUM(
          CASE
            WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -COALESCE(pa.amount, 0)
            ELSE COALESCE(pa.amount, 0)
          END
        ) OVER (
          ORDER BY op.payment_date, op.id, pa.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )::numeric AS balance_before,
      SUM(
        CASE
          WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN -COALESCE(pa.amount, 0)
          ELSE COALESCE(pa.amount, 0)
        END
      ) OVER (
        ORDER BY op.payment_date, op.id, pa.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::numeric AS balance_after
    FROM payment_allocations pa
    JOIN order_payments op ON op.id = pa.payment
    LEFT JOIN payment_types pt ON pt.id = op.payment_type
    WHERE pa."order" = order_id
  ),
  item_taxes AS (
    SELECT
      ir.id,
      ir.item_sum,
      ROUND(
        COALESCE(SUM(
          ps.direction_sign
          * GREATEST(
              LEAST(ir.range_end, GREATEST(ps.balance_before, ps.balance_after))
              - GREATEST(ir.range_start, LEAST(ps.balance_before, ps.balance_after)),
              0
            )
          * ps.tax_percent / 100
        ), 0),
        2
      ) AS tax_sum
    FROM item_ranges ir
    LEFT JOIN payment_steps ps
      ON GREATEST(ps.balance_before, ps.balance_after) > ir.range_start
     AND LEAST(ps.balance_before, ps.balance_after) < ir.range_end
    GROUP BY ir.id, ir.item_sum
  )
  UPDATE orders_items oi
     SET tax_sum = GREATEST(it.tax_sum, 0),
         tax_percent = CASE
           WHEN it.item_sum > 0 THEN ROUND(GREATEST(it.tax_sum, 0) / it.item_sum * 100, 4)
           ELSE 0
         END,
         profit_sum = ROUND(
           COALESCE(oi.order_sum, 0)
           - COALESCE(oi.total_cost, 0)
           - COALESCE(oi.manager_commission_sum, 0)
           - GREATEST(it.tax_sum, 0),
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(oi.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(oi.order_sum, 0)
               - COALESCE(oi.total_cost, 0)
               - COALESCE(oi.manager_commission_sum, 0)
               - GREATEST(it.tax_sum, 0)
             ) / oi.order_sum * 100,
             2
           )
           ELSE 0
         END
    FROM item_taxes it
   WHERE oi.id = it.id;

  UPDATE orders_items oi
     SET tax_sum = 0,
         tax_percent = 0,
         profit_sum = ROUND(
           COALESCE(oi.order_sum, 0)
           - COALESCE(oi.total_cost, 0)
           - COALESCE(oi.manager_commission_sum, 0),
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(oi.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(oi.order_sum, 0)
               - COALESCE(oi.total_cost, 0)
               - COALESCE(oi.manager_commission_sum, 0)
             ) / oi.order_sum * 100,
             2
           )
           ELSE 0
         END
   WHERE oi."order" = order_id
     AND symbolika_normalize_item_status(oi.item_status) = 'cancelled';

  UPDATE orders o
     SET items_total_cost = totals.items_total_cost,
         items_manager_commission_sum = totals.items_manager_commission_sum,
         items_tax_sum = totals.items_tax_sum,
         profit_sum = ROUND(
           COALESCE(o.order_sum, 0)
           - totals.items_total_cost
           - totals.items_manager_commission_sum
           - totals.items_tax_sum,
           2
         ),
         margin_percent = CASE
           WHEN COALESCE(o.order_sum, 0) > 0 THEN ROUND(
             (
               COALESCE(o.order_sum, 0)
               - totals.items_total_cost
               - totals.items_manager_commission_sum
               - totals.items_tax_sum
             ) / o.order_sum * 100,
             2
           )
           ELSE 0
         END
    FROM (
      SELECT
        COALESCE(SUM(oi.total_cost), 0)::numeric(10,2) AS items_total_cost,
        COALESCE(SUM(oi.manager_commission_sum), 0)::numeric(10,2) AS items_manager_commission_sum,
        COALESCE(SUM(oi.tax_sum), 0)::numeric(10,2) AS items_tax_sum
      FROM orders_items oi
      WHERE oi."order" = order_id
        AND symbolika_normalize_item_status(oi.item_status) <> 'cancelled'
    ) totals
   WHERE o.id = order_id;

  PERFORM sync_office_issue_order(order_id);
  PERFORM set_config('symbolika.recalculating_order_finance', '0', true);
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
AFTER INSERT OR UPDATE OF "order", amount, payment_type, payment_direction, allocation_mode OR DELETE ON order_payments
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

-- Bring previously saved orders in line with their actual payment history.
DO $$
DECLARE
  existing_order_id integer;
BEGIN
  FOR existing_order_id IN SELECT id FROM orders ORDER BY id LOOP
    PERFORM recalc_order_payment_totals(existing_order_id);
  END LOOP;
END;
$$;

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
  AND EXISTS (
    SELECT 1
    FROM orders_items oi
    LEFT JOIN product_categories pc ON pc.id = oi.product_category
    WHERE oi."order" = o.id
      AND COALESCE(pc.office_applicable, true)
  )
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
  AND EXISTS (
    SELECT 1
    FROM orders_items oi
    LEFT JOIN product_categories pc ON pc.id = oi.product_category
    WHERE oi."order" = o.id
      AND COALESCE(pc.office_applicable, true)
  )
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
LEFT JOIN product_categories pc ON pc.id = oi.product_category
WHERE o.shipping_method = 'office_pickup'
  AND COALESCE(pc.office_applicable, true)
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
LEFT JOIN product_categories pc ON pc.id = oi.product_category
WHERE o.shipping_method = 'office_pickup'
  AND COALESCE(pc.office_applicable, true)
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
LEFT JOIN product_categories pc ON pc.id = oi.product_category
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
WHERE o.shipping_method = 'office_pickup'
  AND COALESCE(pc.office_applicable, true)
  AND COALESCE(o.office_status, 'not_in_office') <> 'issued';

DELETE FROM production_work;
DELETE FROM screen_printing_work;
DELETE FROM contractor_work;
INSERT INTO production_work (
  id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
  product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
  product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
  technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
)
SELECT
  oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
  oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
  oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
  oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN order_statuses os ON os.id = o.order_status
LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
WHERE (
    os.name IN (
      U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443',
      U&'\0412 \0440\0430\0431\043e\0442\0435',
      U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430',
      U&'\0413\043e\0442\043e\0432',
      U&'\041e\0442\043c\0435\043d\0435\043d'
    )
    OR symbolika_normalize_item_status(oi.item_status) IN ('sent_to_work', 'in_work', 'layout_revision', 'cancellation_requested', 'ready', 'cancelled')
  )
  AND (
    c1.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
    OR c2.name ILIKE U&'%\043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432%'
    OR COALESCE(oi.internal_route_production, false)
  );

INSERT INTO screen_printing_work (
  id, "order", order_number, customer, customer_name, customer_company, customer_company_name, manager_employee,
  product_name, quantity, price_per_unit, order_sum, blank_source, blank_ordered,
  product_category, product_subcategory, application_method, contractor_1, contractor_1_cost,
  technical_task_text, production_comment, url, item_status, office_status, production_status, date, deadline
)
SELECT
  oi.id, oi."order", o.order_number, o.customer, c.name, o.customer_company, cc.name, o.manager_employee,
  oi.product_name, oi.quantity, oi.price_per_unit, oi.order_sum, oi.blank_source, oi.blank_ordered,
  oi.product_category, oi.product_subcategory, oi.application_method, oi.contractor_1, oi.contractor_1_cost,
  oi.technical_task_text, oi.production_comment, oi.url, oi.item_status, oi.office_status, oi.production_status, o.date, oi.deadline
FROM orders_items oi
JOIN orders o ON o.id = oi."order"
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN order_statuses os ON os.id = o.order_status
LEFT JOIN contractors c1 ON c1.id = oi.contractor_1
LEFT JOIN contractors c2 ON c2.id = oi.contractor_2
WHERE (
    os.name IN (
      U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443',
      U&'\0412 \0440\0430\0431\043e\0442\0435',
      U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430',
      U&'\0413\043e\0442\043e\0432',
      U&'\041e\0442\043c\0435\043d\0435\043d'
    )
    OR symbolika_normalize_item_status(oi.item_status) IN ('sent_to_work', 'in_work', 'layout_revision', 'cancellation_requested', 'ready', 'cancelled')
  )
  AND (
    c1.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
    OR c2.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
    OR COALESCE(oi.internal_route_screen, false)
  );

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

INSERT INTO directus_collections (
  collection, icon, hidden, singleton, sort, collapse, translations
) VALUES (
  'service_directory', 'folder', false, false, 39, 'open',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043f\0440\0430\0432\043e\0447\043d\0438\043a\0438'))::json
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse,
  translations = EXCLUDED.translations;

INSERT INTO directus_collections (
  collection, icon, hidden, singleton, sort, collapse, translations
) VALUES (
  'service_directory', 'folder', false, false, 39, 'open',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043f\0440\0430\0432\043e\0447\043d\0438\043a\0438'))::json
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse,
  translations = EXCLUDED.translations;

WITH service_menu(collection_name, icon_value, label_value, sort_value) AS (VALUES
  ('contractors', 'groups', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442\044b', 40),
  ('product_categories', 'category', U&'\041a\0430\0442\0435\0433\043e\0440\0438\0438', 41),
  ('product_subcategories', 'subdirectory_arrow_right', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\0438', 42),
  ('product_application_methods', 'format_paint', U&'\0412\0438\0434\044b \043d\0430\043d\0435\0441\0435\043d\0438\044f', 43),
  ('product_routing_rules', 'account_tree', U&'\041f\0440\0430\0432\0438\043b\0430 \043c\0430\0440\0448\0440\0443\0442\0438\0437\0430\0446\0438\0438', 44),
  ('order_statuses', 'flag', U&'\0421\0442\0430\0442\0443\0441\044b \0437\0430\043a\0430\0437\043e\0432', 45),
  ('production_statuses', 'precision_manufacturing', U&'\0421\0442\0430\0442\0443\0441\044b \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430', 46),
  ('employees', 'badge', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a\0438', 47),
  ('employee_positions', 'assignment_ind', U&'\0414\043e\043b\0436\043d\043e\0441\0442\0438', 48),
  ('payment_types', 'payments', U&'\0422\0438\043f\044b \043e\043f\043b\0430\0442', 49),
  ('shipping_methods', 'local_shipping', U&'\0421\043f\043e\0441\043e\0431\044b \043e\0442\0433\0440\0443\0437\043a\0438', 50),
  ('customer_company_links', 'hub', U&'\0421\0432\044f\0437\0438 \043a\043b\0438\0435\043d\0442\043e\0432 \0438 \043a\043e\043c\043f\0430\043d\0438\0439', 51),
  ('contractor_payments', 'receipt_long', U&'\041e\043f\043b\0430\0442\044b \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\0430\043c', 52)
)
UPDATE directus_collections dc
SET hidden = false,
    icon = service_menu.icon_value,
    sort = service_menu.sort_value,
    "group" = 'service_directory',
    collapse = 'open',
    translations = json_build_array(json_build_object('language','ru-RU','translation', service_menu.label_value))::json
FROM service_menu
WHERE dc.collection = service_menu.collection_name;

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
  ('office_issue', 'office_status', NULL, 'select-dropdown', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 10, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),
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
  ('office_issue_items', 'office_status', NULL, 'select-dropdown', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office","icon":"location_off"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office","icon":"done"},{"text":"Р’С‹РґР°РЅ","value":"issued","icon":"done_all"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 5, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),

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
  ('office_items_in_office', 'office_status', NULL, 'select-dropdown', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office","icon":"location_off"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office","icon":"done"},{"text":"Р’С‹РґР°РЅ","value":"issued","icon":"done_all"}]}'::json, 'labels', '{"choices":[{"text":"РќРµ РІ РѕС„РёСЃРµ","value":"not_in_office"},{"text":"Р’ РѕС„РёСЃРµ","value":"in_office"},{"text":"Р’С‹РґР°РЅ","value":"issued"}]}'::json, false, false, 9, 'half', '[{"language":"ru-RU","translation":"РЎС‚Р°С‚СѓСЃ РѕС„РёСЃР°"}]'::json, false, true),

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
  ('production_work', 'item_status', NULL, 'select-dropdown', '{"choices":[{"text":"Новый","value":"new"},{"text":"Согласование","value":"approval"},{"text":"Доработка макета","value":"layout_revision"},{"text":"Отправлен в работу","value":"sent_to_work"},{"text":"В работе","value":"in_work"},{"text":"Готов","value":"ready"},{"text":"Доставлен","value":"delivered"},{"text":"Отменен","value":"cancelled"}]}'::json, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043f\043e\0437\0438\0446\0438\0438'))::json, false, true),
  ('production_work', 'office_status', NULL, 'select-dropdown', '{"choices":[{"text":"Не в офисе","value":"not_in_office"},{"text":"В офисе","value":"in_office"},{"text":"Выдано","value":"issued"}]}'::json, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'))::json, false, true),
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
  ('screen_printing_work', 'item_status', NULL, 'select-dropdown', '{"choices":[{"text":"Новый","value":"new"},{"text":"Согласование","value":"approval"},{"text":"Доработка макета","value":"layout_revision"},{"text":"Отправлен в работу","value":"sent_to_work"},{"text":"В работе","value":"in_work"},{"text":"Готов","value":"ready"},{"text":"Доставлен","value":"delivered"},{"text":"Отменен","value":"cancelled"}]}'::json, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043f\043e\0437\0438\0446\0438\0438'))::json, false, true),
  ('screen_printing_work', 'office_status', NULL, 'select-dropdown', '{"choices":[{"text":"Не в офисе","value":"not_in_office"},{"text":"В офисе","value":"in_office"},{"text":"Выдано","value":"issued"}]}'::json, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043e\0444\0438\0441\0430'))::json, false, true),
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

DELETE FROM directus_fields
WHERE collection = 'employees'
  AND field = 'birthday';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES (
  'employees', 'birthday', NULL, 'datetime', '{"includeSeconds":false,"use24":true}'::json, 'datetime', '{"format":"dd.MM.yyyy"}'::json,
  false, false, 6, 'half',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0430\0442\0430 \0440\043e\0436\0434\0435\043d\0438\044f'))::json,
  false, false
);

UPDATE directus_fields
SET translations = json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0435\043b\0435\0444\043e\043d'))::json
WHERE collection = 'employees'
  AND field = 'phone';

DELETE FROM directus_fields
WHERE collection = 'employees'
  AND field = 'public_position';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES (
  'employees', 'public_position', NULL, 'input', NULL, NULL, NULL,
  false, false, 5, 'full',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0443\0431\043b\0438\0447\043d\0430\044f \0434\043e\043b\0436\043d\043e\0441\0442\044c'))::json,
  false, true
);

-- Normalize legacy office/production Directus labels that were created before
-- the repository was cleaned up from broken Cyrillic encodings.
WITH collection_labels(collection_name, icon_value, note_value, label_value) AS (VALUES
  ('office_issue', 'storefront', U&'\0417\0430\043a\0430\0437\044b \0441 \0432\044b\0434\0430\0447\0435\0439 \0432 \043e\0444\0438\0441\0435.', U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'),
  ('office_issue_items', 'list_alt', U&'\0421\043b\0443\0436\0435\0431\043d\044b\0439 \0441\043f\0438\0441\043e\043a \043f\043e\0437\0438\0446\0438\0439 \0434\043b\044f \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435.', U&'\041f\043e\0437\0438\0446\0438\0438 \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435'),
  ('office_items_in_office', 'inventory', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\043e\0432, \043a\043e\0442\043e\0440\044b\0435 \0441\0435\0439\0447\0430\0441 \043d\0430\0445\043e\0434\044f\0442\0441\044f \0432 \043e\0444\0438\0441\0435.', U&'\0417\0430\043a\0430\0437\044b \0432 \043e\0444\0438\0441\0435'),
  ('production_work', 'engineering', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\043e\0432 \0434\043b\044f \0441\043e\0431\0441\0442\0432\0435\043d\043d\043e\0433\043e \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430.', U&'\041f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  ('screen_printing_work', 'format_paint', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\043e\0432 \0434\043b\044f \0448\0435\043b\043a\043e\0433\0440\0430\0444\0438\0438.', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f')
)
UPDATE directus_collections dc
SET icon = collection_labels.icon_value,
    note = collection_labels.note_value,
    translations = json_build_array(json_build_object('language','ru-RU','translation', collection_labels.label_value))::json
FROM collection_labels
WHERE dc.collection = collection_labels.collection_name;

WITH field_labels(collection_name, field_name, label_value) AS (VALUES
  ('office_issue', 'order_number', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430'),
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
  ('screen_printing_work', 'url', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'),
  ('screen_printing_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430')
)
UPDATE directus_fields df
SET translations = json_build_array(json_build_object('language','ru-RU','translation', field_labels.label_value))::json
FROM field_labels
WHERE df.collection = field_labels.collection_name
  AND df.field = field_labels.field_name;

UPDATE directus_fields
SET options = json_build_object('choices', json_build_array(
      json_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office'),
      json_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office'),
      json_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued')
    ))::json,
    display_options = json_build_object('choices', json_build_array(
      json_build_object('text', U&'\041d\0435 \0432 \043e\0444\0438\0441\0435', 'value', 'not_in_office'),
      json_build_object('text', U&'\0412 \043e\0444\0438\0441\0435', 'value', 'in_office'),
      json_build_object('text', U&'\0412\044b\0434\0430\043d', 'value', 'issued')
    ))::json
WHERE collection IN ('office_issue', 'office_issue_items', 'office_items_in_office')
  AND field = 'office_status';

UPDATE directus_fields
SET options = json_build_object('choices', json_build_array(
      json_build_object('text', U&'\041d\043e\0432\044b\0439', 'value', 'new'),
      json_build_object('text', U&'\0421\043e\0433\043b\0430\0441\043e\0432\0430\043d\0438\0435', 'value', 'approval'),
      json_build_object('text', U&'\0414\043e\0440\0430\0431\043e\0442\043a\0430 \043c\0430\043a\0435\0442\0430', 'value', 'layout_revision'),
      json_build_object('text', U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 'value', 'sent_to_work'),
      json_build_object('text', U&'\0412 \0440\0430\0431\043e\0442\0435', 'value', 'in_work'),
      json_build_object('text', U&'\0413\043e\0442\043e\0432', 'value', 'ready'),
      json_build_object('text', U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 'value', 'delivered'),
      json_build_object('text', U&'\041e\0442\043c\0435\043d\0435\043d', 'value', 'cancelled')
    ))::json
WHERE collection IN ('production_work', 'screen_printing_work')
  AND field = 'item_status';

DELETE FROM directus_fields
WHERE (collection = 'product_categories' AND field IN ('default_contractor_1', 'default_contractor_2'))
   OR (collection = 'contractors' AND field IN ('has_own_view', 'is_internal_production', 'directus_user', 'default_product_category', 'default_product_subcategory', 'supplies_textile_blanks', 'supplies_merch_blanks', 'website_url'))
   OR (collection = 'product_categories' AND field = 'detail_mode')
   OR (collection = 'product_application_methods' AND field IN ('id', 'category', 'name', 'sort', 'is_active'))
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
    'contractors', 'is_internal_production', 'cast-boolean', 'boolean',
    NULL, 'boolean', NULL,
    false, false, 8, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'))::json,
    false, true
  ),
  (
    'contractors', 'directus_user', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{first_name}} {{last_name}} {{email}}"}'::json, 'related-values', '{"template":"{{first_name}} {{last_name}} {{email}}"}'::json,
    false, false, 9, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\043b\044c\0437\043e\0432\0430\0442\0435\043b\044c Directus'))::json,
    false, true
  ),
  (
    'contractors', 'supplies_textile_blanks', 'cast-boolean', 'boolean',
    NULL, NULL, NULL,
    false, false, 9, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0441\0442\0430\0432\0449\0438\043a \0442\0435\043a\0441\0442\0438\043b\044f'))::json,
    false, true
  ),
  (
    'contractors', 'supplies_merch_blanks', 'cast-boolean', 'boolean',
    NULL, NULL, NULL,
    false, false, 10, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0441\0442\0430\0432\0449\0438\043a \0441\0443\0432\0435\043d\0438\0440\043a\0438'))::json,
    false, true
  ),
  (
    'contractors', 'website_url', NULL, 'input',
    json_build_object('placeholder', 'https://example.ru'), NULL, NULL,
    false, false, 11, 'full',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0430\0439\0442'))::json,
    false, true
  ),
  (
    'contractors', 'default_product_category', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json,
    true, true, 1002, 'half',
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f \043f\043e \0443\043c\043e\043b\0447\0430\043d\0438\044e'))::json,
    false, true
  ),
  (
    'contractors', 'default_product_subcategory', 'm2o', 'select-dropdown-m2o',
    '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json,
    true, true, 1003, 'half',
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
  ('product_application_methods', 'category', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f'))::json, false, true),
  ('product_application_methods', 'name', NULL, 'input', NULL, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0437\0432\0430\043d\0438\0435'))::json, true, true),
  ('product_application_methods', 'sort', NULL, 'input', NULL, NULL, NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0440\0442\0438\0440\043e\0432\043a\0430'))::json, false, true),
  ('product_application_methods', 'is_active', 'cast-boolean', 'boolean', NULL, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\043a\0442\0438\0432\043d\043e'))::json, false, true),
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
  ('production_work', 'product_category', 'product_categories', NULL, 'nullify'),
  ('production_work', 'product_subcategory', 'product_subcategories', NULL, 'nullify'),
  ('production_work', 'application_method', 'product_application_methods', NULL, 'nullify'),
  ('production_work', 'contractor_1', 'contractors', NULL, 'nullify'),
  ('production_work', 'production_status', 'production_statuses', NULL, 'nullify'),

  ('screen_printing_work', 'order', 'orders', NULL, 'nullify'),
  ('screen_printing_work', 'customer', 'customers', NULL, 'nullify'),
  ('screen_printing_work', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('screen_printing_work', 'manager_employee', 'employees', NULL, 'nullify'),
  ('screen_printing_work', 'product_category', 'product_categories', NULL, 'nullify'),
  ('screen_printing_work', 'product_subcategory', 'product_subcategories', NULL, 'nullify'),
  ('screen_printing_work', 'application_method', 'product_application_methods', NULL, 'nullify'),
  ('screen_printing_work', 'contractor_1', 'contractors', NULL, 'nullify'),
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
    ('product_application_methods', 'category', 'product_categories', NULL, 'cascade'),
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
  AND field IN ('order_link', 'application_method', 'blank_source', 'blank_ordered');

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
  ('orders_items', 'blank_source', NULL, 'select-dropdown', '{"choices":[{"text":"Не требуется","value":"none"},{"text":"Закупить у поставщика","value":"supplier"},{"text":"Заготовка заказчика","value":"customer"},{"text":"Со склада","value":"warehouse"},{"text":"Подрядчик под ключ","value":"contractor"}]}'::json, 'labels', '{"choices":[{"text":"Не требуется","value":"none","foreground":"#C9D1D9","background":"#30363D"},{"text":"Закупить у поставщика","value":"supplier","foreground":"#FFD7A8","background":"#4A3423"},{"text":"Заготовка заказчика","value":"customer","foreground":"#B7F7D2","background":"#173C2B"},{"text":"Со склада","value":"warehouse","foreground":"#BFDBFE","background":"#1E3A5F"},{"text":"Подрядчик под ключ","value":"contractor","foreground":"#FFE0B2","background":"#5A3218"}]}'::json, false, false, 17, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430'))::json, false, true),
  ('orders_items', 'blank_ordered', 'cast-boolean', 'boolean', NULL, 'boolean', NULL, false, false, 18, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430 \0437\0430\043a\0430\0437\0430\043d\0430'))::json, false, true),
  ('payment_allocations', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, false, true);

UPDATE directus_fields
SET options = '{"template":"{{name}}","filter":{"_and":[{"category":{"_eq":"{{product_category}}"}},{"is_active":{"_eq":true}}]}}'::json,
    display = 'related-values',
    display_options = '{"template":"{{name}}"}'::json
WHERE collection = 'orders_items'
  AND field = 'product_subcategory';

UPDATE directus_fields
SET options = '{"template":"{{name}}","filter":{"_and":[{"category":{"_eq":"{{product_category}}"}},{"is_active":{"_eq":true}}]}}'::json,
    display = 'related-values',
    display_options = '{"template":"{{name}}"}'::json
WHERE collection = 'orders_items'
  AND field = 'application_method';

UPDATE directus_fields
SET options = '{"template":"{{name}}","filter":{"_and":[{"category":{"_eq":"{{product_category}}"}},{"is_active":{"_eq":true}}]}}'::json,
    display = 'related-values',
    display_options = '{"template":"{{name}}"}'::json
WHERE collection = 'product_routing_rules'
  AND field = 'product_subcategory';

UPDATE directus_fields
SET options = '{"template":"{{name}}","filter":{"_and":[{"category":{"_eq":"{{product_category}}"}},{"is_active":{"_eq":true}}]}}'::json,
    display = 'related-values',
    display_options = '{"template":"{{name}}"}'::json
WHERE collection = 'product_routing_rules'
  AND field = 'application_method';

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = CASE collection
      WHEN 'product_categories' THEN '{"tabular":{"page":1,"sort":["sort"],"fields":["name","detail_mode"]}}'::json
      WHEN 'product_subcategories' THEN '{"tabular":{"page":1,"sort":["category","sort"],"fields":["category","name"]}}'::json
      WHEN 'product_application_methods' THEN '{"tabular":{"page":1,"sort":["category","sort"],"fields":["category","name"]}}'::json
      WHEN 'contractors' THEN '{"tabular":{"page":1,"sort":["name"],"fields":["name","contact_name","phone","email","website_url","balance","has_own_view"]}}'::json
      WHEN 'product_routing_rules' THEN '{"tabular":{"page":1,"sort":["product_category","product_subcategory","application_method","priority"],"fields":["product_category","product_subcategory","application_method","contractor_1","contractor_2","priority"]}}'::json
      ELSE layout_query
    END,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection IN ('product_categories', 'product_subcategories', 'product_application_methods', 'contractors', 'product_routing_rules')
  AND bookmark IS NULL;

INSERT INTO directus_presets (collection, layout, layout_query, layout_options)
SELECT preset.collection_name,
       'tabular',
       preset.layout_query,
       '{"tabular":{"spacing":"compact"}}'::json
FROM (
  VALUES
    ('product_categories', '{"tabular":{"page":1,"sort":["sort"],"fields":["name","detail_mode"]}}'::json),
    ('product_subcategories', '{"tabular":{"page":1,"sort":["category","sort"],"fields":["category","name"]}}'::json),
    ('product_application_methods', '{"tabular":{"page":1,"sort":["category","sort"],"fields":["category","name"]}}'::json),
    ('contractors', '{"tabular":{"page":1,"sort":["name"],"fields":["name","contact_name","phone","email","website_url","balance","has_own_view"]}}'::json),
    ('product_routing_rules', '{"tabular":{"page":1,"sort":["product_category","product_subcategory","application_method","priority"],"fields":["product_category","product_subcategory","application_method","contractor_1","contractor_2","priority"]}}'::json)
) AS preset(collection_name, layout_query)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp.collection = preset.collection_name
    AND dp.bookmark IS NULL
    AND dp."user" IS NULL
    AND dp.role IS NULL
);

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
  ('office_issue', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue', 'update', '{}'::json, NULL, NULL, 'id,office_summary,office_customer,office_payment,office_positions,office_status,add_payment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_items', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_archive', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000203'),
  ('office_issue_archive_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_items_in_office', 'read', '{}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000203'),
  ('office_items_in_office', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000203'),
  ('employee_positions', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000203'),
  ('employee_positions', 'read', '{}'::json, NULL, NULL, 'id,name,sort,is_active', '00000000-0000-4000-8000-000000000204'),
  ('employee_positions', 'read', '{}'::json, NULL, NULL, 'id,name,sort,is_active', '00000000-0000-4000-8000-000000000206'),
  ('contractors', 'read', '{}'::json, NULL, NULL, 'id,name,supplies_textile_blanks,supplies_merch_blanks', '00000000-0000-4000-8000-000000000202'),
  ('contractors', 'read', '{}'::json, NULL, NULL, 'id,name,supplies_textile_blanks,supplies_merch_blanks', '00000000-0000-4000-8000-000000000203'),
  ('product_routing_rules', 'read', '{}'::json, NULL, NULL, 'id,name,product_category,product_subcategory,application_method,contractor_1,contractor_2,priority,is_active', '00000000-0000-4000-8000-000000000202'),
  ('product_routing_rules', 'read', '{}'::json, NULL, NULL, 'id,name,product_category,product_subcategory,application_method,contractor_1,contractor_2,priority,is_active', '00000000-0000-4000-8000-000000000203'),

  ('office_issue', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue', 'update', '{}'::json, NULL, NULL, 'id,office_summary,office_customer,office_payment,office_positions,office_status,add_payment,payment_type,payment_comment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_archive', 'read', '{}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_archive_items', 'read', '{}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_items_in_office', 'read', '{}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_items_in_office', 'update', '{}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000201'),
  ('office_issue_items', 'read', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_items', 'update', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_archive', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'id,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items', '00000000-0000-4000-8000-000000000202'),
  ('office_issue_archive_items', 'read', '{"office_issue":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json, NULL, NULL, 'id,office_issue,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_items_in_office', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'id,order_number,office_issue,customer_name,customer_company_name,manager_employee,product_name,quantity,office_status', '00000000-0000-4000-8000-000000000202'),
  ('office_items_in_office', 'update', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL, 'office_status', '00000000-0000-4000-8000-000000000202'),

  ('production_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('production_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('production_work', 'read', '{}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,contractor_1,contractor_1_cost,date,deadline,item_status,office_status,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000204'),
  ('production_work', 'update', '{}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000204'),

  ('screen_printing_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('screen_printing_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('screen_printing_work', 'read', '{}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,contractor_1,contractor_1_cost,date,deadline,item_status,office_status,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000206'),
  ('screen_printing_work', 'update', '{}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000206'),

  ('contractor_work', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('contractor_work', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('contractor_work', 'read', '{"_and":[{"contractor_has_own_view":{"_eq":true}},{"access_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, 'id,order,order_link,customer,customer_company,manager_employee,contractor,product_name,quantity,deadline,technical_task_text,production_comment,url,production_status', '00000000-0000-4000-8000-000000000207'),
  ('contractor_work', 'update', '{"_and":[{"contractor_has_own_view":{"_eq":true}},{"access_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, 'production_status,production_comment', '00000000-0000-4000-8000-000000000207');

UPDATE directus_permissions
   SET fields = 'id,office_summary,office_customer,office_payment,office_positions,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,add_payment,overpayment,payment_type,payment_comment,order_items'
 WHERE collection = 'office_issue'
   AND action = 'read'
   AND fields IS NOT NULL
   AND fields <> '*';

UPDATE directus_permissions
   SET fields = 'id,office_summary,office_customer,office_payment,office_positions,order_link,order_number,date,deadline,customer_name,customer_phone,customer_company_name,manager_employee,manager_name,order_status_name,office_status,order_sum,paid_amount,payment_due,office_payment_due,overpayment,order_items'
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
 WHERE policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203'
  )
   AND collection = 'order_payments'
   AND action = 'delete';

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

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('order_payments', 'delete', '{"access_manager_user":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('order_payments', 'delete', '{"access_manager_user":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202'),
  ('order_payments', 'delete', '{"access_shipping_method":{"_eq":"office_pickup"}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000203');

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
     WHEN action = 'read' THEN 'id,accordion-redqc5,main,item,tech,order,order_link,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,production_status,deadline,production_comment,technical_task_text,manager_employee,shipping_method,office_status,url,contractor_1,contractor_1_cost'
     ELSE 'accordion-redqc5,main,item,tech,order,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url,contractor_1,contractor_1_cost'
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
SELECT 'employees', 'read', '{}'::json, NULL, NULL, 'id,full_name,position,phone,is_active,directus_user', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000206')
) AS p(policy_id)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions dp
  WHERE dp.collection = 'employees'
    AND dp.action = 'read'
    AND dp.policy = p.policy_id::uuid
);

UPDATE directus_permissions
   SET fields = 'id,full_name,position,phone,is_active,directus_user'
 WHERE collection = 'employees'
   AND action = 'read'
   AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206'
   )
   AND fields IS NOT NULL
   AND fields <> '*';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT
  'employees',
  'read',
  '{"directus_user":{"_eq":"$CURRENT_USER"}}'::json,
  NULL,
  NULL,
  'id,full_name,order_percent',
  '00000000-0000-4000-8000-000000000201'::uuid
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions dp
  WHERE dp.collection = 'employees'
    AND dp.action = 'read'
    AND dp.policy = '00000000-0000-4000-8000-000000000201'::uuid
    AND dp.fields = 'id,full_name,order_percent'
);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT
  'employee_salary_summary',
  'read',
  '{"employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,
  NULL,
  NULL,
  'id,employee,employee_name,position_name,order_percent,orders_sum,paid_orders_sum,unpaid_orders_sum,commission_accrued,salary_paid,advances_paid,salary_debt',
  '00000000-0000-4000-8000-000000000201'::uuid
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions dp
  WHERE dp.collection = 'employee_salary_summary'
    AND dp.action = 'read'
    AND dp.policy = '00000000-0000-4000-8000-000000000201'::uuid
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

UPDATE directus_settings
SET module_bar = (
  SELECT jsonb_agg(item)
  FROM (
    SELECT item
    FROM jsonb_array_elements(COALESCE(module_bar, '[]'::json)::jsonb) AS current_items(item)
    WHERE item->>'id' NOT IN (
      'symbolika-costing',
      'symbolika-orders',
      'symbolika-tasks',
      'symbolika-production',
      'symbolika-procurement',
      'symbolika-finance',
      'symbolika-clients',
      'symbolika-management',
      'symbolika-admin',
      'symbolika-contractor',
      'symbolika-mail-module',
      'symbolika-profile-module'
    )
    UNION ALL
    SELECT *
    FROM jsonb_array_elements(
      '[
        {"type":"module","id":"symbolika-orders","enabled":true},
        {"type":"module","id":"symbolika-tasks","enabled":true},
        {"type":"module","id":"symbolika-production","enabled":true},
        {"type":"module","id":"symbolika-procurement","enabled":true},
        {"type":"module","id":"symbolika-management","enabled":true},
        {"type":"module","id":"symbolika-admin","enabled":true},
        {"type":"module","id":"symbolika-mail-module","enabled":true},
        {"type":"module","id":"symbolika-profile-module","enabled":true}
      ]'::jsonb
    )
  ) module_items(item)
)::json
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
  (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 4),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 5),
  (U&'\0413\043e\0442\043e\0432', 6),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 7),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 8)
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
  (U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 4),
  (U&'\0412 \0440\0430\0431\043e\0442\0435', 5),
  (U&'\0413\043e\0442\043e\0432', 6),
  (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', 7),
  (U&'\041e\0442\043c\0435\043d\0435\043d', 8)
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
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', 'application_method', 100),
  (U&'\041c\043e\043d\0442\0430\0436', 'none', 105),
  (U&'\0420\0430\0437\0440\0430\0431\043e\0442\043a\0430 \0434\0438\0437\0430\0439\043d\0430', 'none', 110)
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
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', 'application_method', 100),
  (U&'\041c\043e\043d\0442\0430\0436', 'none', 105),
  (U&'\0420\0430\0437\0440\0430\0431\043e\0442\043a\0430 \0434\0438\0437\0430\0439\043d\0430', 'none', 110)
)
UPDATE product_categories pc
SET detail_mode = c.detail_mode,
    sort = c.sort,
    is_active = true
FROM categories c
WHERE pc.name = c.name;

UPDATE product_categories
SET office_applicable = false,
    detail_mode = 'none',
    is_active = true
WHERE name = U&'\0420\0430\0437\0440\0430\0431\043e\0442\043a\0430 \0434\0438\0437\0430\0439\043d\0430';

UPDATE orders_items oi
SET office_status = NULL
FROM product_categories pc
WHERE pc.id = oi.product_category
  AND pc.office_applicable = false
  AND oi.office_status IS NOT NULL;

WITH subcategories(category_name, name, sort) AS (VALUES
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0413\0440\0430\043c\043e\0442\044b', 10),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0412\0438\0437\0438\0442\043a\0438', 20),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041b\0438\0441\0442\043e\0432\043a\0438', 30),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\043b\043e\043a\043d\043e\0442\044b', 40),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041a\0430\043b\0435\043d\0434\0430\0440\0438', 50),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0440\043e\0448\044e\0440\044b', 60),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0443\043a\043b\0435\0442\044b', 70),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b', 110),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438', 120),
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

WITH subcategories(category_name, name, sort) AS (VALUES
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0413\0440\0430\043c\043e\0442\044b', 10),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0412\0438\0437\0438\0442\043a\0438', 20),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041b\0438\0441\0442\043e\0432\043a\0438', 30),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\043b\043e\043a\043d\043e\0442\044b', 40),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041a\0430\043b\0435\043d\0434\0430\0440\0438', 50),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0440\043e\0448\044e\0440\044b', 60),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\0411\0443\043a\043b\0435\0442\044b', 70),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b', 110),
  (U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f', U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438', 120),
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
UPDATE product_subcategories ps
SET sort = s.sort,
    is_active = true
FROM subcategories s
JOIN product_categories pc ON pc.name = s.category_name
WHERE ps.category = pc.id
  AND ps.name = s.name;

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
UPDATE product_application_methods pam
SET sort = m.sort,
    is_active = true
FROM methods m
WHERE pam.name = m.name;

WITH category_methods(category_name, method_name, sort) AS (VALUES
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', 5),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 10),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 20),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 30),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 40),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0422\0438\0441\043d\0435\043d\0438\0435', 50),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\0414\0422\0424', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 10),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', 20),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0412\044b\0448\0438\0432\043a\0430', 30),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 40),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0414\0422\0424', 50),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\041f\043b\0435\043d\043a\0430', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\041f\043e\0448\0438\0432', 70),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', 10),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0421\0442\0440\0443\0439\043d\0430\044f \043f\0435\0447\0430\0442\044c', 20),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 30),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 40),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0422\0438\0441\043d\0435\043d\0438\0435', 50),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 60),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 70),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0423\0424-\0414\0422\0424 \043f\0435\0447\0430\0442\044c', 80),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0414\0422\0424-\043f\0435\0447\0430\0442\044c', 90),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', 100),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0412\044b\0448\0438\0432\043a\0430', 110)
),
resolved_methods AS (
  SELECT pc.id AS category_id, cm.method_name, cm.sort
  FROM category_methods cm
  JOIN product_categories pc ON pc.name = cm.category_name
)
INSERT INTO product_application_methods (category, name, sort, is_active)
SELECT rm.category_id, rm.method_name, rm.sort, true
FROM resolved_methods rm
WHERE NOT EXISTS (
  SELECT 1
  FROM product_application_methods pam
  WHERE pam.category = rm.category_id
    AND pam.name = rm.method_name
);

WITH category_methods(category_name, method_name, sort) AS (VALUES
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', 5),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 10),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 20),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 30),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 40),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0422\0438\0441\043d\0435\043d\0438\0435', 50),
  (U&'\0421\0443\0432\0435\043d\0438\0440\044b, \043c\0435\0440\0447', U&'\0423\0424-\0414\0422\0424', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 10),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', 20),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0412\044b\0448\0438\0432\043a\0430', 30),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 40),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\0414\0422\0424', 50),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\041f\043b\0435\043d\043a\0430', 60),
  (U&'\0422\0435\043a\0441\0442\0438\043b\044c', U&'\041f\043e\0448\0438\0432', 70),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', 10),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0421\0442\0440\0443\0439\043d\0430\044f \043f\0435\0447\0430\0442\044c', 20),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', 30),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 40),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0422\0438\0441\043d\0435\043d\0438\0435', 50),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0421\0443\0431\043b\0438\043c\0430\0446\0438\044f', 60),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0423\0424-\043f\0435\0447\0430\0442\044c', 70),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0423\0424-\0414\0422\0424 \043f\0435\0447\0430\0442\044c', 80),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0414\0422\0424-\043f\0435\0447\0430\0442\044c', 90),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', 100),
  (U&'\041d\0430\043d\0435\0441\0435\043d\0438\0435', U&'\0412\044b\0448\0438\0432\043a\0430', 110)
)
UPDATE product_application_methods pam
SET sort = cm.sort,
    is_active = true
FROM category_methods cm
JOIN product_categories pc ON pc.name = cm.category_name
WHERE pam.category = pc.id
  AND pam.name = cm.method_name;

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
JOIN LATERAL (
  SELECT id, name
  FROM product_application_methods
  WHERE name = rs.method_name
    AND (category = pc.id OR category IS NULL)
  ORDER BY CASE WHEN category = pc.id THEN 0 ELSE 1 END, id
  LIMIT 1
) pam ON true
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
      jsonb_build_object('text', U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 'value', 'sent_to_work'),
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
      jsonb_build_object('text', U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443', 'value', 'sent_to_work', 'foreground', '#111827', 'background', '#FB923C'),
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
        WHEN name = U&'\041e\0442\043f\0440\0430\0432\043b\0435\043d \0432 \0440\0430\0431\043e\0442\0443' THEN '#FB923C'
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
  customer integer,
  customer_company integer,
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

CREATE TABLE IF NOT EXISTS customer_reconciliation_items (
  id integer PRIMARY KEY,
  order_item integer,
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
  production_status_name character varying(255),
  product_name character varying(255),
  quantity numeric(10,2),
  price_per_unit numeric(10,2),
  item_sum numeric(10,2),
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2),
  overpayment numeric(10,2),
  reconciliation_result character varying(255)
);

ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_item integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_number character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS date timestamp without time zone;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS deadline timestamp without time zone;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS customer_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS customer_company_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS counterparty_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS manager_employee integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS manager_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS production_status_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS product_name character varying(255);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS quantity numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS price_per_unit numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS item_sum numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS order_sum numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS paid_amount numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS payment_due numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS overpayment numeric(10,2);
ALTER TABLE customer_reconciliation_items ADD COLUMN IF NOT EXISTS reconciliation_result character varying(255);

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
  shipping_comment text,
  order_sum numeric(10,2),
  paid_amount numeric(10,2),
  payment_due numeric(10,2)
);

CREATE TABLE IF NOT EXISTS my_orders_completed (LIKE my_orders_in_work INCLUDING ALL);
CREATE TABLE IF NOT EXISTS my_orders_unpaid (LIKE my_orders_in_work INCLUDING ALL);

ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS shipping_comment text;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS shipping_comment text;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS shipping_comment text;

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
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_today ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_this_week ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_next_week ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_this_month ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_urgent ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS order_status integer;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS order_status_name character varying(255);
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS office_status character varying(255);
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_due_next_month ADD COLUMN IF NOT EXISTS completion_missing text;

DO $$
DECLARE
  due_table text;
BEGIN
  FOREACH due_table IN ARRAY ARRAY[
    'orders_due_urgent',
    'orders_due_today',
    'orders_due_this_week',
    'orders_due_next_week',
    'orders_due_this_month',
    'orders_due_next_month'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS work_completion_percent integer NOT NULL DEFAULT 0', due_table);
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS work_completion_missing_count integer NOT NULL DEFAULT 0', due_table);
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS work_completion_missing text', due_table);
  END LOOP;
END;
$$;
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS customer_debt_to_us numeric(10,2);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS our_debt_to_customer numeric(10,2);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS reconciliation_result character varying(255);
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS order_link integer;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS customer integer;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS customer_company integer;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS completion_missing text;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS completion_missing text;

ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS work_completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS work_completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS work_completion_missing text;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS work_completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS work_completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS work_completion_percent integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS work_completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS work_completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS work_completion_missing_count integer NOT NULL DEFAULT 0;
ALTER TABLE my_orders_in_work ADD COLUMN IF NOT EXISTS work_completion_missing text;
ALTER TABLE my_orders_completed ADD COLUMN IF NOT EXISTS work_completion_missing text;
ALTER TABLE my_orders_unpaid ADD COLUMN IF NOT EXISTS work_completion_missing text;

CREATE OR REPLACE FUNCTION symbolika_order_completion(order_id integer)
RETURNS TABLE (
  completion_percent integer,
  completion_missing_count integer,
  completion_missing text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  order_row record;
  item_row record;
  checks_total integer := 0;
  checks_filled integer := 0;
  missing_values text[] := ARRAY[]::text[];
  item_label text;
  has_subcategories boolean;
  has_application_methods boolean;
  contractor_costs_filled boolean;
BEGIN
  SELECT o.* INTO order_row FROM orders o WHERE o.id = order_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 0, 1, U&'\0417\0430\043a\0430\0437 \043d\0435 \043d\0430\0439\0434\0435\043d';
    RETURN;
  END IF;

  checks_total := checks_total + 1;
  IF order_row.customer IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043a\043b\0438\0435\043d\0442'); END IF;

  checks_total := checks_total + 1;
  IF order_row.manager_employee IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043c\0435\043d\0435\0434\0436\0435\0440'); END IF;

  checks_total := checks_total + 1;
  IF order_row.date IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0434\0430\0442\0430'); END IF;

  checks_total := checks_total + 1;
  IF order_row.deadline IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0441\0440\043e\043a'); END IF;

  checks_total := checks_total + 1;
  IF NULLIF(BTRIM(order_row.shipping_method), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0441\043f\043e\0441\043e\0431 \043f\043e\043b\0443\0447\0435\043d\0438\044f'); END IF;

  checks_total := checks_total + 1;
  IF order_row.payment_type IS NOT NULL THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0442\0438\043f \043e\043f\043b\0430\0442\044b'); END IF;

  checks_total := checks_total + 1;
  IF EXISTS (SELECT 1 FROM orders_items oi WHERE oi."order" = order_id) THEN checks_filled := checks_filled + 1;
  ELSE missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043d\0435\0442 \043f\043e\0437\0438\0446\0438\0439'); END IF;

  FOR item_row IN SELECT oi.* FROM orders_items oi WHERE oi."order" = order_id ORDER BY oi.id LOOP
    item_label := COALESCE(NULLIF(BTRIM(item_row.product_name), ''), U&'\041f\043e\0437\0438\0446\0438\044f #' || item_row.id::text);

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.product_name), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043d\0430\0437\0432\0430\043d\0438\0435'); END IF;

    checks_total := checks_total + 1;
    IF COALESCE(item_row.quantity, 0) > 0 THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\043e\043b\0438\0447\0435\0441\0442\0432\043e'); END IF;

    checks_total := checks_total + 1;
    IF COALESCE(item_row.price_per_unit, 0) > 0 THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0446\0435\043d\0430'); END IF;

    checks_total := checks_total + 1;
    IF item_row.deadline IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0441\0440\043e\043a'); END IF;

    checks_total := checks_total + 1;
    IF item_row.product_category IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\0430\0442\0435\0433\043e\0440\0438\044f'); END IF;

    SELECT EXISTS (
      SELECT 1 FROM product_subcategories ps WHERE ps.category = item_row.product_category
    ) INTO has_subcategories;
    IF has_subcategories THEN
      checks_total := checks_total + 1;
      IF item_row.product_subcategory IS NOT NULL THEN checks_filled := checks_filled + 1;
      ELSE missing_values := array_append(missing_values, item_label || U&': \043f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f'); END IF;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM product_application_methods pam
      WHERE pam.category = item_row.product_category AND COALESCE(pam.is_active, true)
    ) INTO has_application_methods;
    IF has_application_methods THEN
      checks_total := checks_total + 1;
      IF item_row.application_method IS NOT NULL THEN checks_filled := checks_filled + 1;
      ELSE missing_values := array_append(missing_values, item_label || U&': \0432\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f'); END IF;
    END IF;

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.technical_task_text), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0422\0417'); END IF;

    checks_total := checks_total + 1;
    IF item_row.contractor_1 IS NOT NULL OR item_row.contractor_2 IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442'); END IF;

    contractor_costs_filled := (
        item_row.contractor_1 IS NULL
        OR COALESCE(item_row.contractor_1_cost, 0) > 0
        OR EXISTS (
          SELECT 1 FROM contractors c
          WHERE c.id = item_row.contractor_1 AND COALESCE(c.is_internal_production, false)
        )
      )
      AND (
        item_row.contractor_2 IS NULL
        OR COALESCE(item_row.contractor_2_cost, 0) > 0
        OR EXISTS (
          SELECT 1 FROM contractors c
          WHERE c.id = item_row.contractor_2 AND COALESCE(c.is_internal_production, false)
        )
      )
      AND (item_row.contractor_1 IS NOT NULL OR item_row.contractor_2 IS NOT NULL);
    checks_total := checks_total + 1;
    IF contractor_costs_filled THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0441\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c'); END IF;

    IF COALESCE(item_row.needs_designer_help, false) THEN
      checks_total := checks_total + 1;
      IF NULLIF(BTRIM(item_row.url), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
      ELSE missing_values := array_append(missing_values, item_label || U&': \0441\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'); END IF;
    END IF;
  END LOOP;

  RETURN QUERY SELECT
    CASE WHEN checks_total > 0 THEN ROUND(checks_filled * 100.0 / checks_total)::integer ELSE 0 END,
    COALESCE(array_length(missing_values, 1), 0),
    array_to_string(missing_values, '||');
END;
$$;

-- Bootstrap completion used by the order views created below. It is replaced
-- by the route-aware definition after contractor_capabilities is available.
CREATE OR REPLACE FUNCTION symbolika_order_work_completion(order_id integer)
RETURNS TABLE (
  work_completion_percent integer,
  work_completion_missing_count integer,
  work_completion_missing text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  item_row record;
  checks_total integer := 0;
  checks_filled integer := 0;
  missing_values text[] := ARRAY[]::text[];
  item_label text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders_items oi WHERE oi."order" = order_id) THEN
    RETURN QUERY SELECT 0, 1, U&'\0417\0430\043a\0430\0437: \043d\0435\0442 \043f\043e\0437\0438\0446\0438\0439';
    RETURN;
  END IF;

  FOR item_row IN SELECT oi.* FROM orders_items oi WHERE oi."order" = order_id ORDER BY oi.id LOOP
    item_label := COALESCE(NULLIF(BTRIM(item_row.product_name), ''), U&'\041f\043e\0437\0438\0446\0438\044f #' || item_row.id::text);

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.product_name), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043d\0430\0437\0432\0430\043d\0438\0435'); END IF;

    checks_total := checks_total + 1;
    IF COALESCE(item_row.quantity, 0) > 0 THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\043e\043b\0438\0447\0435\0441\0442\0432\043e'); END IF;

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.technical_task_text), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0422\0417'); END IF;

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.url), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0441\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'); END IF;
  END LOOP;

  RETURN QUERY SELECT
    CASE WHEN checks_total > 0 THEN ROUND(checks_filled * 100.0 / checks_total)::integer ELSE 0 END,
    COALESCE(array_length(missing_values, 1), 0),
    array_to_string(missing_values, '||');
END;
$$;

CREATE OR REPLACE FUNCTION refresh_orders_due_tables()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  due_table text;
BEGIN
  -- The due buckets are rebuilt as a whole. Serialize concurrent rebuilds so
  -- two order/item transactions cannot both delete and reinsert the same ids.
  PERFORM pg_advisory_xact_lock(hashtext('symbolika_orders_due_refresh'));

  DELETE FROM orders_due_today;
  DELETE FROM orders_due_this_week;
  DELETE FROM orders_due_next_week;
  DELETE FROM orders_due_this_month;
  DELETE FROM orders_due_urgent;
  DELETE FROM orders_due_next_month;

  DROP TABLE IF EXISTS pg_temp.symbolika_order_due_dates;
  CREATE TEMP TABLE symbolika_order_due_dates ON COMMIT DROP AS
  SELECT oo.id AS order_id, d.deadline
  FROM orders_overview oo
  JOIN LATERAL (
    SELECT oo.deadline
    UNION ALL
    SELECT oi.deadline
    FROM orders_items oi
    WHERE oi."order" = oo.id
  ) d(deadline) ON d.deadline IS NOT NULL;

  INSERT INTO orders_due_urgent (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline < CURRENT_DATE + INTERVAL '1 day'
  ORDER BY oo.id, dd.deadline;

  INSERT INTO orders_due_today (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline >= CURRENT_DATE
    AND dd.deadline < CURRENT_DATE + INTERVAL '1 day'
  ORDER BY oo.id, dd.deadline;

  INSERT INTO orders_due_this_week (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline >= date_trunc('week', CURRENT_DATE)::date
    AND dd.deadline < date_trunc('week', CURRENT_DATE)::date + INTERVAL '7 days'
  ORDER BY oo.id, dd.deadline;

  INSERT INTO orders_due_next_week (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline >= date_trunc('week', CURRENT_DATE)::date + INTERVAL '7 days'
    AND dd.deadline < date_trunc('week', CURRENT_DATE)::date + INTERVAL '14 days'
  ORDER BY oo.id, dd.deadline;

  INSERT INTO orders_due_this_month (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline >= date_trunc('month', CURRENT_DATE)::date
    AND dd.deadline < date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
  ORDER BY oo.id, dd.deadline;

  INSERT INTO orders_due_next_month (
    id, order_number, date, deadline, customer_display, manager_name,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due, order_link,
    completion_percent, completion_missing_count, completion_missing
  )
  SELECT DISTINCT ON (oo.id)
    oo.id, oo.order_number, oo.date, dd.deadline, oo.customer_display, oo.manager_name,
    oo.shipping_method, oo.shipping_method_name, oo.order_sum, oo.paid_amount, oo.payment_due, oo.order_link,
    oo.completion_percent, oo.completion_missing_count, oo.completion_missing
  FROM orders_overview oo
  JOIN symbolika_order_due_dates dd ON dd.order_id = oo.id
  WHERE dd.deadline >= date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
    AND dd.deadline < date_trunc('month', CURRENT_DATE)::date + INTERVAL '2 months'
  ORDER BY oo.id, dd.deadline;

  FOREACH due_table IN ARRAY ARRAY[
    'orders_due_urgent',
    'orders_due_today',
    'orders_due_this_week',
    'orders_due_next_week',
    'orders_due_this_month',
    'orders_due_next_month'
  ]
  LOOP
    EXECUTE format(
      'UPDATE %I due
          SET work_completion_percent = overview.work_completion_percent,
              work_completion_missing_count = overview.work_completion_missing_count,
              work_completion_missing = overview.work_completion_missing
         FROM orders_overview overview
        WHERE overview.id = due.id',
      due_table
    );
  END LOOP;
END;
$$;

-- Bootstrap reconciliation for orders. The final definition below extends it
-- with customer_operations after that table has been created.
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

  INSERT INTO customer_reconciliation_items (
    id, order_item, order_link, order_number, date, deadline,
    customer, customer_name, customer_company, customer_company_name, counterparty_name,
    manager_employee, manager_name, order_status, order_status_name, production_status_name,
    product_name, quantity, price_per_unit, item_sum,
    order_sum, paid_amount, payment_due, overpayment, reconciliation_result
  )
  SELECT
    oi.id,
    oi.id,
    o.id,
    o.order_number,
    o.date,
    COALESCE(oi.deadline, o.deadline),
    o.customer,
    c.name,
    o.customer_company,
    cc.name,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
    o.manager_employee,
    e.full_name,
    o.order_status,
    os.name,
    ps.name,
    oi.product_name,
    COALESCE(oi.quantity, 0),
    COALESCE(oi.price_per_unit, 0),
    COALESCE(oi.order_sum, COALESCE(oi.quantity, 0) * COALESCE(oi.price_per_unit, 0)),
    COALESCE(o.order_sum, 0),
    COALESCE(o.paid_amount, 0),
    COALESCE(o.payment_due, 0),
    GREATEST(COALESCE(o.paid_amount, 0) - COALESCE(o.order_sum, 0), 0)::numeric(10,2),
    CASE
      WHEN COALESCE(o.payment_due, 0) > 0 THEN U&'\041a\043b\0438\0435\043d\0442 \0434\043e\043b\0436\0435\043d'
      WHEN COALESCE(o.payment_due, 0) < 0 THEN U&'\041c\044b \0434\043e\043b\0436\043d\044b'
      ELSE U&'\0420\0430\0441\0447\0435\0442 \0437\0430\043a\0440\044b\0442'
    END
  FROM orders_items oi
  JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  LEFT JOIN production_statuses ps ON ps.id = oi.production_status;
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
    END AS shipping_method_name,
    completion.completion_percent,
    completion.completion_missing_count,
    completion.completion_missing,
    work_completion.work_completion_percent,
    work_completion.work_completion_missing_count,
    work_completion.work_completion_missing
  INTO order_row
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  LEFT JOIN employees e ON e.id = o.manager_employee
  LEFT JOIN order_statuses os ON os.id = o.order_status
  LEFT JOIN LATERAL symbolika_order_completion(o.id) completion ON true
  LEFT JOIN LATERAL symbolika_order_work_completion(o.id) work_completion ON true
  WHERE o.id = order_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  is_completed := order_row.office_status = 'issued'
    OR order_row.order_status_name IN (U&'\0414\043e\0441\0442\0430\0432\043b\0435\043d', U&'\041e\0442\043c\0435\043d\0435\043d');
  is_unpaid := COALESCE(order_row.payment_due, 0) > 0;

  IF is_completed THEN
    INSERT INTO my_orders_completed (
      id, order_number, date, deadline, customer, customer_company, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name, shipping_comment,
      order_sum, paid_amount, payment_due, completion_percent, completion_missing_count, completion_missing,
      work_completion_percent, work_completion_missing_count, work_completion_missing
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer, order_row.customer_company,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name, order_row.shipping_comment,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due,
      order_row.completion_percent, order_row.completion_missing_count, order_row.completion_missing,
      order_row.work_completion_percent, order_row.work_completion_missing_count, order_row.work_completion_missing
    );
  ELSE
    INSERT INTO my_orders_in_work (
      id, order_number, date, deadline, customer, customer_company, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name, shipping_comment,
      order_sum, paid_amount, payment_due, completion_percent, completion_missing_count, completion_missing,
      work_completion_percent, work_completion_missing_count, work_completion_missing
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer, order_row.customer_company,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name, order_row.shipping_comment,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due,
      order_row.completion_percent, order_row.completion_missing_count, order_row.completion_missing,
      order_row.work_completion_percent, order_row.work_completion_missing_count, order_row.work_completion_missing
    );
  END IF;

  IF is_unpaid THEN
    INSERT INTO my_orders_unpaid (
      id, order_number, date, deadline, customer, customer_company, customer_display, manager_employee, manager_name,
      order_status, order_status_name, office_status, shipping_method, shipping_method_name, shipping_comment,
      order_sum, paid_amount, payment_due, completion_percent, completion_missing_count, completion_missing,
      work_completion_percent, work_completion_missing_count, work_completion_missing
    )
    VALUES (
      order_row.id, order_row.order_number, order_row.date, order_row.deadline,
      order_row.customer, order_row.customer_company,
      order_row.customer_display, order_row.manager_employee, order_row.manager_name,
      order_row.order_status, order_row.order_status_name, order_row.office_status,
      order_row.shipping_method, order_row.shipping_method_name, order_row.shipping_comment,
      order_row.order_sum, order_row.paid_amount, order_row.payment_due,
      order_row.completion_percent, order_row.completion_missing_count, order_row.completion_missing,
      order_row.work_completion_percent, order_row.work_completion_missing_count, order_row.work_completion_missing
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

  IF TG_OP = 'UPDATE' AND OLD."order" IS DISTINCT FROM NEW."order" THEN
    PERFORM sync_my_order_buckets(OLD."order");
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
    id, order_number, date, deadline, customer, customer_company, customer_display, manager_name,
    order_status, order_status_name, office_status,
    shipping_method, shipping_method_name, order_sum, paid_amount, payment_due,
    completion_percent, completion_missing_count, completion_missing,
    work_completion_percent, work_completion_missing_count, work_completion_missing
  )
  SELECT
    o.id,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    o.customer_company,
    COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
    e.full_name,
    o.order_status,
    os.name,
    o.office_status,
    o.shipping_method,
    CASE o.shipping_method
      WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
      WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
      WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
      ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
    END,
    o.order_sum,
    o.paid_amount,
    o.payment_due,
    completion.completion_percent,
    completion.completion_missing_count,
    completion.completion_missing,
    work_completion.work_completion_percent,
    work_completion.work_completion_missing_count,
    work_completion.work_completion_missing
FROM orders o
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN employees e ON e.id = o.manager_employee
LEFT JOIN order_statuses os ON os.id = o.order_status
LEFT JOIN LATERAL symbolika_order_completion(o.id) completion ON true
LEFT JOIN LATERAL symbolika_order_work_completion(o.id) work_completion ON true
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

  IF TG_OP = 'UPDATE' AND OLD."order" IS DISTINCT FROM NEW."order" THEN
    PERFORM sync_orders_overview(OLD."order");
  END IF;

  PERFORM sync_orders_overview(NEW."order");
  RETURN NEW;
END;
$$;

-- An item move can update the destination order from an earlier AFTER trigger
-- before the overview trigger itself runs. Remove the stale source summary row
-- in BEFORE UPDATE so rebuilding the destination cannot collide on item id.
CREATE OR REPLACE FUNCTION prepare_orders_overview_item_move_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD."order" IS DISTINCT FROM NEW."order" THEN
    DELETE FROM orders_overview_items WHERE id = OLD.id;
    DELETE FROM office_issue_items WHERE id = OLD.id;
    DELETE FROM office_issue_archive_items WHERE id = OLD.id;
    DELETE FROM office_items_in_office WHERE id = OLD.id;
    DELETE FROM production_work WHERE id = OLD.id;
    DELETE FROM screen_printing_work WHERE id = OLD.id;
    DELETE FROM contractor_work WHERE id = OLD.id;
    DELETE FROM my_orders_in_work_items WHERE id = OLD.id;
    DELETE FROM my_orders_completed_items WHERE id = OLD.id;
    DELETE FROM my_orders_unpaid_items WHERE id = OLD.id;
  END IF;
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

DROP TRIGGER IF EXISTS symbolika_prepare_orders_overview_item_move ON orders_items;
CREATE TRIGGER symbolika_prepare_orders_overview_item_move
BEFORE UPDATE OF "order" ON orders_items
FOR EACH ROW
EXECUTE FUNCTION prepare_orders_overview_item_move_trigger();

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
  id, order_number, date, deadline, customer, customer_company, customer_display, manager_name,
  order_status, order_status_name, office_status,
  shipping_method, shipping_method_name, order_sum, paid_amount, payment_due,
  completion_percent, completion_missing_count, completion_missing,
  work_completion_percent, work_completion_missing_count, work_completion_missing
)
SELECT
  o.id,
  o.order_number,
  o.date,
  o.deadline,
  o.customer,
  o.customer_company,
  COALESCE(NULLIF(cc.name, ''), NULLIF(c.name, ''), U&'\0411\0435\0437 \0437\0430\043a\0430\0437\0447\0438\043a\0430'),
  e.full_name,
  o.order_status,
  os.name,
  o.office_status,
  o.shipping_method,
  CASE o.shipping_method
    WHEN 'office_pickup' THEN U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435'
    WHEN 'client_delivery' THEN U&'\0414\043e\0441\0442\0430\0432\043a\0430 \043a\043b\0438\0435\043d\0442\0443'
    WHEN 'transport_company' THEN U&'\0422\0440\0430\043d\0441\043f\043e\0440\0442\043d\0430\044f \043a\043e\043c\043f\0430\043d\0438\044f'
    ELSE U&'\041d\0435 \0443\043a\0430\0437\0430\043d\043e'
  END,
  o.order_sum,
  o.paid_amount,
  o.payment_due,
  completion.completion_percent,
  completion.completion_missing_count,
  completion.completion_missing,
  work_completion.work_completion_percent,
  work_completion.work_completion_missing_count,
  work_completion.work_completion_missing
FROM orders o
LEFT JOIN customers c ON c.id = o.customer
LEFT JOIN customer_companies cc ON cc.id = o.customer_company
LEFT JOIN employees e ON e.id = o.manager_employee
LEFT JOIN order_statuses os ON os.id = o.order_status
LEFT JOIN LATERAL symbolika_order_completion(o.id) completion ON true
LEFT JOIN LATERAL symbolika_order_work_completion(o.id) work_completion ON true;

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

CREATE TABLE IF NOT EXISTS symbolika_news (
  id BIGSERIAL PRIMARY KEY,
  status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  title VARCHAR(240) NOT NULL,
  summary VARCHAR(500),
  content_html TEXT NOT NULL,
  cover_url TEXT,
  author_employee INTEGER REFERENCES employees(id) ON DELETE SET NULL,
  created_by UUID REFERENCES directus_users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES directus_users(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ,
  notifications_sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS symbolika_news_status_published_idx ON symbolika_news(status, published_at DESC);

CREATE TABLE IF NOT EXISTS symbolika_news_reads (
  id BIGSERIAL PRIMARY KEY,
  news BIGINT NOT NULL REFERENCES symbolika_news(id) ON DELETE CASCADE,
  "user" UUID NOT NULL REFERENCES directus_users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Directus requires a single-column primary key. Older installations used the
-- composite (news, user) key, so migrate them without losing read marks.
ALTER TABLE symbolika_news_reads ADD COLUMN IF NOT EXISTS id BIGINT;
CREATE SEQUENCE IF NOT EXISTS symbolika_news_reads_id_seq;
ALTER SEQUENCE symbolika_news_reads_id_seq OWNED BY symbolika_news_reads.id;
ALTER TABLE symbolika_news_reads
  ALTER COLUMN id SET DEFAULT nextval('symbolika_news_reads_id_seq');
UPDATE symbolika_news_reads
SET id = nextval('symbolika_news_reads_id_seq')
WHERE id IS NULL;
SELECT setval(
  'symbolika_news_reads_id_seq',
  COALESCE((SELECT MAX(id) FROM symbolika_news_reads), 1),
  EXISTS (SELECT 1 FROM symbolika_news_reads)
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
    EXECUTE format('ALTER TABLE public.symbolika_news_reads DROP CONSTRAINT %I', current_primary_key);
    current_primary_key := NULL;
  END IF;

  IF current_primary_key IS NULL THEN
    ALTER TABLE symbolika_news_reads
      ADD CONSTRAINT symbolika_news_reads_pkey PRIMARY KEY (id);
  END IF;
END $$;

ALTER TABLE symbolika_news_reads ALTER COLUMN id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS symbolika_news_reads_news_user_uidx
  ON symbolika_news_reads (news, "user");

-- Historical snapshots are preserved, but kept outside the working schema so
-- Directus does not expose them as collections or warn about missing keys.
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
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = backup_table
        AND relation.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format('ALTER TABLE public.%I SET SCHEMA symbolika_archive', backup_table);
    END IF;
  END LOOP;
END $$;

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
  ('customer_reconciliation_items', 'format_list_bulleted', NULL, '{{product_name}}', true, false, json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\0438 \0441\0432\0435\0440\043a\0438'))::json, true, 'all', 1, NULL, 'open', false),
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
  'customer_reconciliation_items',
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
) VALUES
  ('orders_overview', 'completion_percent', NULL, 'numeric', NULL, NULL, NULL, true, true, 20, 'half', NULL, false, false),
  ('orders_overview', 'completion_missing_count', NULL, 'numeric', NULL, NULL, NULL, true, true, 21, 'half', NULL, false, false),
  ('orders_overview', 'completion_missing', NULL, 'input-multiline', NULL, NULL, NULL, true, true, 22, 'full', NULL, false, false),
  ('orders_overview', 'work_completion_percent', NULL, 'numeric', NULL, NULL, NULL, true, true, 23, 'half', NULL, false, false),
  ('orders_overview', 'work_completion_missing_count', NULL, 'numeric', NULL, NULL, NULL, true, true, 24, 'half', NULL, false, false),
  ('orders_overview', 'work_completion_missing', NULL, 'input-multiline', NULL, NULL, NULL, true, true, 25, 'full', NULL, false, false);

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

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
)
SELECT
  'customer_reconciliation_items',
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
  ('order_item', NULL, 'numeric', NULL::json, NULL, NULL::json, 2, 'half', U&'\041f\043e\0437\0438\0446\0438\044f ID', true),
  ('order_link', NULL, 'symbolika-order-link', NULL::json, NULL, NULL::json, 3, 'half', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437', false),
  ('order_number', NULL, 'input', NULL::json, NULL, NULL::json, 4, 'half', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430', false),
  ('counterparty_name', NULL, 'input', NULL::json, NULL, NULL::json, 5, 'half', U&'\0417\0430\043a\0430\0437\0447\0438\043a', false),
  ('customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, 6, 'half', U&'\041a\043b\0438\0435\043d\0442', false),
  ('customer_name', NULL, 'input', NULL::json, NULL, NULL::json, 7, 'half', U&'\0418\043c\044f \043a\043b\0438\0435\043d\0442\0430', true),
  ('customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, 8, 'half', U&'\041a\043e\043c\043f\0430\043d\0438\044f', false),
  ('customer_company_name', NULL, 'input', NULL::json, NULL, NULL::json, 9, 'half', U&'\041d\0430\0437\0432\0430\043d\0438\0435 \043a\043e\043c\043f\0430\043d\0438\0438', true),
  ('manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, 10, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', false),
  ('manager_name', NULL, 'input', NULL::json, NULL, NULL::json, 11, 'half', U&'\041c\0435\043d\0435\0434\0436\0435\0440', true),
  ('date', NULL, 'datetime', NULL::json, NULL, NULL::json, 12, 'half', U&'\0414\0430\0442\0430', false),
  ('deadline', NULL, 'datetime', NULL::json, NULL, NULL::json, 13, 'half', U&'\0421\0440\043e\043a', false),
  ('order_status', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'labels', NULL::json, 14, 'half', U&'\0421\0442\0430\0442\0443\0441 \0437\0430\043a\0430\0437\0430', false),
  ('order_status_name', NULL, 'input', NULL::json, NULL, NULL::json, 15, 'half', U&'\0421\0442\0430\0442\0443\0441', true),
  ('product_name', NULL, 'input', NULL::json, NULL, NULL::json, 16, 'half', U&'\041f\043e\0437\0438\0446\0438\044f', false),
  ('quantity', NULL, 'input', NULL::json, NULL, NULL::json, 17, 'half', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e', false),
  ('price_per_unit', NULL, 'input', NULL::json, NULL, NULL::json, 18, 'half', U&'\0426\0435\043d\0430', false),
  ('item_sum', NULL, 'input', NULL::json, NULL, NULL::json, 19, 'half', U&'\0421\0443\043c\043c\0430 \043f\043e\0437\0438\0446\0438\0438', false),
  ('order_sum', NULL, 'input', NULL::json, NULL, NULL::json, 20, 'half', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\0430', false),
  ('paid_amount', NULL, 'input', NULL::json, NULL, NULL::json, 21, 'half', U&'\041e\043f\043b\0430\0447\0435\043d\043e', false),
  ('payment_due', NULL, 'input', NULL::json, NULL, NULL::json, 22, 'half', U&'\041e\0441\0442\0430\0442\043e\043a', false),
  ('overpayment', NULL, 'input', NULL::json, NULL, NULL::json, 23, 'half', U&'\041f\0435\0440\0435\043f\043b\0430\0442\0430', false),
  ('reconciliation_result', NULL, 'input', NULL::json, NULL, NULL::json, 24, 'half', U&'\0418\0442\043e\0433 \0441\0432\0435\0440\043a\0438', false)
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
  ('payment_due', 'input', 18, 'half', U&'\041e\0441\0442\0430\0442\043e\043a', false, NULL, NULL, NULL::json),
  ('completion_percent', 'numeric', 19, 'half', NULL, true, NULL, NULL, NULL::json),
  ('completion_missing_count', 'numeric', 20, 'half', NULL, true, NULL, NULL, NULL::json),
  ('completion_missing', 'input-multiline', 21, 'full', NULL, true, NULL, NULL, NULL::json),
  ('work_completion_percent', 'numeric', 22, 'half', NULL, true, NULL, NULL, NULL::json),
  ('work_completion_missing_count', 'numeric', 23, 'half', NULL, true, NULL, NULL, NULL::json),
  ('work_completion_missing', 'input-multiline', 24, 'full', NULL, true, NULL, NULL, NULL::json)
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
   OR (many_collection = 'customer_reconciliation_items' AND many_field IN ('customer', 'customer_company', 'manager_employee', 'order_status'))
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
  ('customer_reconciliation', 'order_status', 'order_statuses', NULL, 'nullify'),
  ('customer_reconciliation_items', 'customer', 'customers', NULL, 'nullify'),
  ('customer_reconciliation_items', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('customer_reconciliation_items', 'manager_employee', 'employees', NULL, 'nullify'),
  ('customer_reconciliation_items', 'order_status', 'order_statuses', NULL, 'nullify');

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
  'customer_reconciliation_items',
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
    ('customer_reconciliation_items'),
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
WHERE collection IN ('customer_reconciliation', 'customer_reconciliation_items');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000203', '{}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value)
CROSS JOIN (
  VALUES
    ('customer_reconciliation'),
    ('customer_reconciliation_items')
) AS collections(collection_name);

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
  ('orders_items', 'blank_source', 'main', 10, 'half', false),
  ('orders_items', 'blank_ordered', 'main', 11, 'half', false),
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

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, conditions
)
SELECT work.collection_name, 'date', NULL, 'datetime', NULL, NULL, NULL,
       true, false, 1, 'half',
       json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0430\0442\0430'))::json,
       false, NULL::json
FROM (VALUES ('production_work'), ('screen_printing_work')) AS work(collection_name)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_fields df
  WHERE df.collection = work.collection_name
    AND df.field = 'date'
);

UPDATE directus_fields
SET translations = json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0430\0442\0430'))::json,
    interface = 'datetime',
    readonly = true,
    hidden = false
WHERE collection IN ('production_work', 'screen_printing_work')
  AND field = 'date';

WITH work_field_meta(field_name, special_value, interface_value, options_value, display_value, display_options_value, readonly_value, hidden_value, sort_value, width_value, label_value) AS (VALUES
  ('price_per_unit', NULL::varchar, 'input', NULL::json, NULL::varchar, NULL::json, true, true, 20, 'half', U&'\0426\0435\043d\0430'),
  ('order_sum', NULL::varchar, 'input', NULL::json, NULL::varchar, NULL::json, true, true, 21, 'half', U&'\0421\0443\043c\043c\0430 \043f\043e\0437\0438\0446\0438\0438'),
  ('blank_source', NULL::varchar, 'select-dropdown',
    '{"choices":[{"text":"Не требуется","value":"none"},{"text":"Закупить у поставщика","value":"supplier"},{"text":"Заготовка заказчика","value":"customer"},{"text":"Со склада","value":"warehouse"},{"text":"Подрядчик под ключ","value":"contractor"}]}'::json,
    'labels',
    '{"choices":[{"text":"Не требуется","value":"none","foreground":"#C9D1D9","background":"#30363D"},{"text":"Закупить у поставщика","value":"supplier","foreground":"#FFD7A8","background":"#4A3423"},{"text":"Заготовка заказчика","value":"customer","foreground":"#B7F7D2","background":"#173C2B"},{"text":"Со склада","value":"warehouse","foreground":"#BFDBFE","background":"#1E3A5F"},{"text":"Подрядчик под ключ","value":"contractor","foreground":"#FFE0B2","background":"#5A3218"}]}'::json,
    true, true, 22, 'half', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430'),
  ('blank_ordered', 'cast-boolean', 'boolean', NULL::json, 'boolean', NULL::json, true, true, 23, 'half', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430 \0437\0430\043a\0430\0437\0430\043d\0430'),
  ('product_category', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 24, 'half', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f'),
  ('product_subcategory', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 25, 'half', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f'),
  ('application_method', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 26, 'half', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f'),
  ('contractor_1', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, true, 27, 'half', U&'\041f\043e\0434\0440\044f\0434\0447\0438\043a 1'),
  ('contractor_1_cost', NULL::varchar, 'input', NULL::json, NULL::varchar, NULL::json, true, true, 28, 'half', U&'\0421\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c 1')
),
work_collections(collection_name) AS (VALUES
  ('production_work'),
  ('screen_printing_work')
)
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, conditions
)
SELECT
  work_collections.collection_name,
  work_field_meta.field_name,
  work_field_meta.special_value,
  work_field_meta.interface_value,
  work_field_meta.options_value,
  work_field_meta.display_value,
  work_field_meta.display_options_value,
  work_field_meta.readonly_value,
  work_field_meta.hidden_value,
  work_field_meta.sort_value,
  work_field_meta.width_value,
  json_build_array(json_build_object('language','ru-RU','translation', work_field_meta.label_value))::json,
  false,
  NULL::json
FROM work_collections
CROSS JOIN work_field_meta
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_fields df
  WHERE df.collection = work_collections.collection_name
    AND df.field = work_field_meta.field_name
);

WITH work_labels(collection_name, field_name, label_value) AS (VALUES
  ('production_work', 'date', U&'\0414\0430\0442\0430'),
  ('production_work', 'deadline', U&'\0421\0440\043e\043a\0438'),
  ('production_work', 'order', U&'\0417\0430\043a\0430\0437'),
  ('production_work', 'customer', U&'\0417\0430\043a\0430\0437\0447\0438\043a'),
  ('production_work', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('production_work', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('production_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430'),
  ('screen_printing_work', 'date', U&'\0414\0430\0442\0430'),
  ('screen_printing_work', 'deadline', U&'\0421\0440\043e\043a\0438'),
  ('screen_printing_work', 'order', U&'\0417\0430\043a\0430\0437'),
  ('screen_printing_work', 'customer', U&'\0417\0430\043a\0430\0437\0447\0438\043a'),
  ('screen_printing_work', 'product_name', U&'\041d\0430\0438\043c\0435\043d\043e\0432\0430\043d\0438\0435'),
  ('screen_printing_work', 'quantity', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'),
  ('screen_printing_work', 'production_status', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430')
)
UPDATE directus_fields df
SET translations = json_build_array(json_build_object('language','ru-RU','translation', work_labels.label_value))::json
FROM work_labels
WHERE df.collection = work_labels.collection_name
  AND df.field = work_labels.field_name;

WITH work_layout(collection_name, field_name, sort_value, width_value, hidden_value) AS (VALUES
  ('production_work', 'date', 1, 'half', false),
  ('production_work', 'deadline', 2, 'half', false),
  ('production_work', 'order', 3, 'half', false),
  ('production_work', 'customer', 4, 'half', false),
  ('production_work', 'product_name', 5, 'half', false),
  ('production_work', 'quantity', 6, 'half', false),
  ('production_work', 'production_status', 7, 'half', false),
  ('production_work', 'technical_task_text', 8, 'full', false),
  ('production_work', 'url', 9, 'full', false),
  ('production_work', 'production_comment', 10, 'full', false),
  ('production_work', 'order_link', 11, 'half', true),
  ('production_work', 'customer_company', 12, 'half', true),
  ('production_work', 'manager_employee', 13, 'half', true),
  ('screen_printing_work', 'date', 1, 'half', false),
  ('screen_printing_work', 'deadline', 2, 'half', false),
  ('screen_printing_work', 'order', 3, 'half', false),
  ('screen_printing_work', 'customer', 4, 'half', false),
  ('screen_printing_work', 'product_name', 5, 'half', false),
  ('screen_printing_work', 'quantity', 6, 'half', false),
  ('screen_printing_work', 'production_status', 7, 'half', false),
  ('screen_printing_work', 'technical_task_text', 8, 'full', false),
  ('screen_printing_work', 'url', 9, 'full', false),
  ('screen_printing_work', 'production_comment', 10, 'full', false),
  ('screen_printing_work', 'order_link', 11, 'half', true),
  ('screen_printing_work', 'customer_company', 12, 'half', true),
  ('screen_printing_work', 'manager_employee', 13, 'half', true)
)
UPDATE directus_fields df
SET sort = work_layout.sort_value,
    width = work_layout.width_value,
    hidden = work_layout.hidden_value
FROM work_layout
WHERE df.collection = work_layout.collection_name
  AND df.field = work_layout.field_name;

UPDATE directus_presets
SET layout = 'tabular',
    layout_query = '{"tabular":{"fields":["date","deadline","order","customer","product_name","quantity","production_status"],"page":1}}'::json,
    layout_options = '{"tabular":{"spacing":"compact"}}'::json
WHERE collection IN ('production_work', 'screen_printing_work')
  AND bookmark IS NULL;

INSERT INTO directus_presets (collection, layout, layout_query, layout_options)
SELECT work.collection_name,
       'tabular',
       '{"tabular":{"fields":["date","deadline","order","customer","product_name","quantity","production_status"],"page":1}}'::json,
       '{"tabular":{"spacing":"compact"}}'::json
FROM (VALUES ('production_work'), ('screen_printing_work')) AS work(collection_name)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp.collection = work.collection_name
    AND dp.bookmark IS NULL
    AND dp."user" IS NULL
    AND dp.role IS NULL
);

INSERT INTO directus_presets ("user", collection, layout, layout_query, layout_options)
SELECT du.id,
       work.collection_name,
       'tabular',
       '{"tabular":{"fields":["date","deadline","order","customer","product_name","quantity","production_status"],"page":1}}'::json,
       '{"tabular":{"spacing":"compact"}}'::json
FROM directus_users du
CROSS JOIN (VALUES ('production_work'), ('screen_printing_work')) AS work(collection_name)
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_presets dp
  WHERE dp."user" = du.id
    AND dp.collection = work.collection_name
    AND dp.bookmark IS NULL
);

WITH service_menu(collection_name, icon_value, label_value, sort_value) AS (VALUES
  ('contractors', 'groups', U&'\041a\043e\043d\0442\0440\0430\0433\0435\043d\0442\044b', 40),
  ('product_categories', 'category', U&'\041a\0430\0442\0435\0433\043e\0440\0438\0438', 41),
  ('product_subcategories', 'account_tree', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\0438', 42),
  ('product_application_methods', 'format_paint', U&'\0412\0438\0434\044b \043d\0430\043d\0435\0441\0435\043d\0438\044f', 43),
  ('product_routing_rules', 'device_hub', U&'\041f\0440\0430\0432\0438\043b\0430 \043c\0430\0440\0448\0440\0443\0442\0438\0437\0430\0446\0438\0438', 44),
  ('order_statuses', 'fact_check', U&'\0421\0442\0430\0442\0443\0441\044b \0437\0430\043a\0430\0437\043e\0432', 45),
  ('production_statuses', 'engineering', U&'\0421\0442\0430\0442\0443\0441\044b \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430', 46),
  ('employees', 'badge', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a\0438', 47),
  ('employee_positions', 'work', U&'\0414\043e\043b\0436\043d\043e\0441\0442\0438', 48),
  ('payment_types', 'payments', U&'\0422\0438\043f\044b \043e\043f\043b\0430\0442', 49),
  ('customer_company_links', 'hub', U&'\0421\0432\044f\0437\0438 \043a\043b\0438\0435\043d\0442\043e\0432 \0438 \043a\043e\043c\043f\0430\043d\0438\0439', 51),
  ('contractor_payments', 'receipt_long', U&'\041e\043f\043b\0430\0442\044b \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\0430\043c', 52),
  ('business_expenses', 'receipt_long', U&'\0420\0430\0441\0445\043e\0434\044b', 55)
)
UPDATE directus_collections dc
SET hidden = false,
    icon = service_menu.icon_value,
    sort = service_menu.sort_value,
    "group" = 'service_directory',
    collapse = 'open',
    translations = json_build_array(json_build_object('language','ru-RU','translation', service_menu.label_value))::json
FROM service_menu
WHERE dc.collection = service_menu.collection_name;

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, translations,
  archive_app_filter, accountability, sort, collapse, versioning
) VALUES
  (
    'finance_dashboard_metrics', 'monitoring',
    'Aggregated finance metrics for Directus Analytics dashboards.',
    '{{title}}: {{value}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0424\0438\043d\0430\043d\0441\043e\0432\044b\0435 \043c\0435\0442\0440\0438\043a\0438'))::json,
    true, 'all', 90, 'open', false
  ),
  (
    'finance_dashboard_monthly', 'stacked_line_chart',
    'Monthly finance aggregates for Directus Analytics dashboards.',
    '{{month_label}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0424\0438\043d\0430\043d\0441\044b \043f\043e \043c\0435\0441\044f\0446\0430\043c'))::json,
    true, 'all', 91, 'open', false
  ),
  (
    'finance_dashboard_series', 'multiline_chart',
    'Monthly finance series for Directus Analytics line charts.',
    '{{month_label}} {{metric_name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0424\0438\043d\0430\043d\0441\043e\0432\0430\044f \0434\0438\043d\0430\043c\0438\043a\0430'))::json,
    true, 'all', 92, 'open', false
  ),
  (
    'business_expenses', 'receipt_long',
    'Operational company expenses and employee salary payments.',
    '{{expense_date}} {{amount}}', false, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0420\0430\0441\0445\043e\0434\044b'))::json,
    true, 'all', 55, 'open', false
  ),
  (
    'finance_settings', 'event_repeat',
    'Recurring finance settings and payment calendar.',
    'Постоянные расходы', true, true,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0441\0442\043e\044f\043d\043d\044b\0435 \0440\0430\0441\0445\043e\0434\044b'))::json,
    true, 'all', 56, 'open', false
  ),
  (
    'employee_salary_summary', 'payments',
    'Current month salary accrual and employee debt summary.',
    '{{employee_name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0420\0430\0441\0447\0435\0442 \0417\041f'))::json,
    true, 'all', 93, 'open', false
  ),
  (
    'employee_salary_monthly', 'calendar_month',
    'Monthly salary accrual history.',
    '{{month_label}} {{employee_name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\041f \043f\043e \043c\0435\0441\044f\0446\0430\043c'))::json,
    true, 'all', 94, 'open', false
  ),
  (
    'manager_finance_summary', 'workspace_premium',
    'Personal manager revenue and commission summary.',
    '{{employee_name}}', true, false,
    json_build_array(json_build_object('language','ru-RU','translation', U&'\041b\0438\0447\043d\044b\0435 \043f\043e\043a\0430\0437\0430\0442\0435\043b\0438 \043c\0435\043d\0435\0434\0436\0435\0440\0430'))::json,
    true, 'all', 95, 'open', false
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

DELETE FROM directus_fields
WHERE collection IN ('finance_dashboard_metrics', 'finance_dashboard_monthly', 'finance_dashboard_series', 'business_expenses', 'finance_settings', 'employee_salary_summary', 'employee_salary_monthly', 'manager_finance_summary');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('finance_dashboard_metrics', 'metric_key', NULL, 'input', NULL, NULL, NULL, true, true, 1, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\044e\0447'))::json, true, true),
  ('finance_dashboard_metrics', 'title', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\043a\0430\0437\0430\0442\0435\043b\044c'))::json, true, true),
  ('finance_dashboard_metrics', 'metric_group', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0413\0440\0443\043f\043f\0430'))::json, true, true),
  ('finance_dashboard_metrics', 'value', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0443\043c\043c\0430'))::json, false, true),
  ('finance_dashboard_metrics', 'sort', NULL, 'input', NULL, NULL, NULL, true, true, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0440\0442\0438\0440\043e\0432\043a\0430'))::json, false, true),
  ('finance_dashboard_metrics', 'updated_at', NULL, 'datetime', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\0431\043d\043e\0432\043b\0435\043d\043e'))::json, false, true),
  ('finance_dashboard_monthly', 'month_start', NULL, 'datetime', NULL, NULL, NULL, true, false, 1, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\0441\044f\0446'))::json, true, true),
  ('finance_dashboard_monthly', 'month_label', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0438\043e\0434'))::json, true, true),
  ('finance_dashboard_monthly', 'revenue', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\044b\0440\0443\0447\043a\0430'))::json, false, true),
  ('finance_dashboard_monthly', 'paid', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('finance_dashboard_monthly', 'profit', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0438\0431\044b\043b\044c'))::json, false, true),
  ('finance_dashboard_monthly', 'expenses', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0420\0430\0441\0445\043e\0434\044b'))::json, false, true),
  ('finance_dashboard_monthly', 'receivable', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0435\0431\0438\0442\043e\0440\043a\0430'))::json, false, true),
  ('finance_dashboard_monthly', 'updated_at', NULL, 'datetime', NULL, NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\0431\043d\043e\0432\043b\0435\043d\043e'))::json, false, true),
  ('finance_dashboard_series', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('finance_dashboard_series', 'month_start', NULL, 'datetime', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\0441\044f\0446'))::json, true, true),
  ('finance_dashboard_series', 'month_label', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0438\043e\0434'))::json, true, true),
  ('finance_dashboard_series', 'metric_key', NULL, 'input', NULL, NULL, NULL, true, true, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\044e\0447'))::json, true, true),
  ('finance_dashboard_series', 'metric_name', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\043a\0430\0437\0430\0442\0435\043b\044c'))::json, true, true),
  ('finance_dashboard_series', 'value', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0443\043c\043c\0430'))::json, false, true),
  ('finance_dashboard_series', 'sort', NULL, 'input', NULL, NULL, NULL, true, true, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0440\0442\0438\0440\043e\0432\043a\0430'))::json, false, true),
  ('finance_dashboard_series', 'updated_at', NULL, 'datetime', NULL, NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\0431\043d\043e\0432\043b\0435\043d\043e'))::json, false, true),
  ('business_expenses', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('business_expenses', 'expense_date', NULL, 'datetime', NULL, 'datetime', NULL, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0430\0442\0430'))::json, true, true),
  ('business_expenses', 'accounting_month', NULL, 'datetime', NULL, 'datetime', NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0420\0430\0441\0447\0451\0442\043d\044b\0439 \043c\0435\0441\044f\0446'))::json, false, true),
  ('business_expenses', 'expense_type', NULL, 'select-dropdown', '{"choices":[{"text":"Аренда","value":"rent"},{"text":"Материалы (бумага, тонер)","value":"production_materials"},{"text":"Производственная расходка","value":"production_consumables"},{"text":"Обслуживание и ремонт техники","value":"equipment_maintenance"},{"text":"Закупка прочих запасов","value":"inventory_purchase"},{"text":"Выплата зарплаты","value":"salary_payment"},{"text":"Назначенная премия","value":"employee_bonus"},{"text":"Оплата за доставку","value":"delivery"},{"text":"Прочие расходы","value":"other"},{"text":"Аванс сотруднику","value":"employee_advance"}]}'::json, 'labels', NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0438\043f \0440\0430\0441\0445\043e\0434\0430'))::json, true, true),
  ('business_expenses', 'amount', NULL, 'input', NULL, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0443\043c\043c\0430'))::json, true, true),
  ('business_expenses', 'employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('business_expenses', 'payment_type', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0422\0438\043f \043e\043f\043b\0430\0442\044b'))::json, false, true),
  ('business_expenses', 'comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 8, 'full', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043c\0435\043d\0442\0430\0440\0438\0439'))::json, false, true),
  ('business_expenses', 'created_at', NULL, 'datetime', NULL, NULL, NULL, true, true, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0437\0434\0430\043d\043e'))::json, false, true),
  ('finance_settings', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('finance_settings', 'monthly_rent', NULL, 'input', NULL, NULL, NULL, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\0440\0435\043d\0434\0430 \0432 \043c\0435\0441\044f\0446'))::json, true, true),
  ('finance_settings', 'rent_due_day_from', NULL, 'input', NULL, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\0430 \0430\0440\0435\043d\0434\044b \0441'))::json, true, true),
  ('finance_settings', 'rent_due_day_to', NULL, 'input', NULL, NULL, NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0442\0430 \0430\0440\0435\043d\0434\044b \0434\043e'))::json, true, true),
  ('finance_settings', 'advance_day', NULL, 'input', NULL, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0435\043d\044c \0430\0432\0430\043d\0441\0430'))::json, true, true),
  ('finance_settings', 'salary_day', NULL, 'input', NULL, NULL, NULL, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0435\043d\044c \0437\0430\0440\043f\043b\0430\0442\044b'))::json, true, true),
  ('finance_settings', 'updated_at', NULL, 'datetime', NULL, NULL, NULL, true, true, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\0431\043d\043e\0432\043b\0435\043d\043e'))::json, false, true),
  ('employee_salary_summary', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('employee_salary_summary', 'employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, true, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('employee_salary_summary', 'employee_name', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('employee_salary_summary', 'position_name', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043b\0436\043d\043e\0441\0442\044c'))::json, false, true),
  ('employee_salary_summary', 'month_start', NULL, 'datetime', NULL, NULL, NULL, true, true, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\0441\044f\0446'))::json, false, true),
  ('employee_salary_summary', 'salary_fixed', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043a\043b\0430\0434'))::json, false, true),
  ('employee_salary_summary', 'order_percent', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\043e\0446\0435\043d\0442'))::json, false, true),
  ('employee_salary_summary', 'orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0443\043c\043c\0430 \0437\0430\043a\0430\0437\043e\0432'))::json, false, true),
  ('employee_salary_summary', 'paid_orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('employee_salary_summary', 'unpaid_orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0435 \043e\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('employee_salary_summary', 'commission_accrued', NULL, 'input', NULL, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\043e\0446\0435\043d\0442\044b'))::json, false, true),
  ('employee_salary_summary', 'salary_accrued', NULL, 'input', NULL, NULL, NULL, true, false, 12, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0447\0438\0441\043b\0435\043d\043e'))::json, false, true),
  ('employee_salary_summary', 'salary_paid', NULL, 'input', NULL, NULL, NULL, true, false, 13, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\044b\043f\043b\0430\0447\0435\043d\043e \0417\041f'))::json, false, true),
  ('employee_salary_summary', 'advances_paid', NULL, 'input', NULL, NULL, NULL, true, false, 14, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0410\0432\0430\043d\0441\044b'))::json, false, true),
  ('employee_salary_summary', 'bonus_paid', NULL, 'input', NULL, NULL, NULL, true, false, 15, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0435\043c\0438\0438'))::json, false, true),
  ('employee_salary_summary', 'salary_debt', NULL, 'input', NULL, NULL, NULL, true, false, 16, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043b\0433 \043f\043e \0417\041f'))::json, false, true),
  ('manager_finance_summary', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('manager_finance_summary', 'employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, true, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('manager_finance_summary', 'directus_user', NULL, 'input', NULL, NULL, NULL, true, true, 3, 'half', NULL, false, true),
  ('manager_finance_summary', 'employee_name', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('manager_finance_summary', 'order_percent', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\043e\0446\0435\043d\0442'))::json, false, true),
  ('manager_finance_summary', 'orders_count', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437\043e\0432'))::json, false, true),
  ('manager_finance_summary', 'orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\044b\0440\0443\0447\043a\0430'))::json, false, true),
  ('manager_finance_summary', 'paid_orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('manager_finance_summary', 'unpaid_orders_sum', NULL, 'input', NULL, NULL, NULL, true, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0435 \043e\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('manager_finance_summary', 'commission_total', NULL, 'input', NULL, NULL, NULL, true, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation', 'Процент от всех'))::json, false, true),
  ('manager_finance_summary', 'commission_accrued', NULL, 'input', NULL, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', 'Начислено'))::json, false, true),
  ('manager_finance_summary', 'commission_expected', NULL, 'input', NULL, NULL, NULL, true, false, 12, 'half', json_build_array(json_build_object('language','ru-RU','translation', 'Ожидается'))::json, false, true),
  ('manager_finance_summary', 'commission_paid', NULL, 'input', NULL, NULL, NULL, true, false, 13, 'half', json_build_array(json_build_object('language','ru-RU','translation', 'Выплачено'))::json, false, true),
  ('manager_finance_summary', 'commission_to_pay', NULL, 'input', NULL, NULL, NULL, true, false, 14, 'half', json_build_array(json_build_object('language','ru-RU','translation', 'К выплате'))::json, false, true),
  ('employee_salary_monthly', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'half', NULL, true, true),
  ('employee_salary_monthly', 'employee_name', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\043e\0442\0440\0443\0434\043d\0438\043a'))::json, false, true),
  ('employee_salary_monthly', 'position_name', NULL, 'input', NULL, NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043b\0436\043d\043e\0441\0442\044c'))::json, false, true),
  ('employee_salary_monthly', 'month_label', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\0441\044f\0446'))::json, false, true),
  ('employee_salary_monthly', 'salary_accrued', NULL, 'input', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\0430\0447\0438\0441\043b\0435\043d\043e'))::json, false, true),
  ('employee_salary_monthly', 'salary_paid', NULL, 'input', NULL, NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\044b\043f\043b\0430\0447\0435\043d\043e'))::json, false, true),
  ('employee_salary_monthly', 'bonus_paid', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0435\043c\0438\0438'))::json, false, true),
  ('employee_salary_monthly', 'salary_debt', NULL, 'input', NULL, NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043b\0433'))::json, false, true);

DELETE FROM directus_relations
WHERE many_collection = 'business_expenses';

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_collection_field,
  one_allowed_collections, junction_field, sort_field, one_deselect_action
) VALUES
  ('business_expenses', 'employee', 'employees', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('business_expenses', 'payment_type', 'payment_types', NULL, NULL, NULL, NULL, NULL, 'nullify');

DELETE FROM directus_permissions
WHERE collection IN ('finance_dashboard_metrics', 'finance_dashboard_monthly', 'finance_dashboard_series', 'business_expenses', 'finance_settings', 'contractor_payments', 'employee_salary_summary', 'employee_salary_monthly', 'manager_finance_summary')
  AND policy = '00000000-0000-4000-8000-000000000205';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'
FROM (VALUES ('finance_dashboard_metrics'), ('finance_dashboard_monthly'), ('finance_dashboard_series'), ('finance_settings'), ('employee_salary_summary'), ('employee_salary_monthly'), ('manager_finance_summary')) AS finance(collection_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'finance_settings', action_value, '{}'::json, '{}'::json, NULL, '*', '00000000-0000-4000-8000-000000000205'
FROM (VALUES ('update')) AS actions(action_value);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'business_expenses', action_value, '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'
FROM (VALUES ('create'), ('read'), ('update'), ('delete')) AS actions(action_value);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'contractor_payments', action_value, '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'
FROM (VALUES ('create'), ('read'), ('update'), ('delete')) AS actions(action_value);

DELETE FROM directus_permissions
WHERE collection = 'manager_finance_summary'
  AND policy = '00000000-0000-4000-8000-000000000201';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES (
  'manager_finance_summary',
  'read',
  '{"directus_user":{"_eq":"$CURRENT_USER"}}'::json,
  NULL,
  NULL,
  'id,employee,employee_name,order_percent,orders_count,orders_sum,paid_orders_sum,unpaid_orders_sum,commission_total,commission_accrued,commission_expected,commission_paid,commission_to_pay',
  '00000000-0000-4000-8000-000000000201'
);

INSERT INTO directus_dashboards (id, name, icon, note, color)
VALUES (
  '00000000-0000-4000-8000-000000000901',
  U&'\0424\0438\043d\0430\043d\0441\044b',
  'monitoring',
  U&'\0412\044b\0440\0443\0447\043a\0430, \043e\043f\043b\0430\0442\044b, \043f\0440\0438\0431\044b\043b\044c, \0440\0430\0441\0445\043e\0434\044b \0438 \0432\0437\0430\0438\043c\043e\0440\0430\0441\0447\0435\0442\044b.',
  '#F97316'
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  color = EXCLUDED.color;

DELETE FROM directus_panels
WHERE dashboard = '00000000-0000-4000-8000-000000000901';

WITH finance_panels(panel_id, panel_name, filter_key, x, y, w, h, color_value, suffix_value) AS (VALUES
  ('00000000-0000-4000-8000-000000000911'::uuid, U&'\0412\044b\0440\0443\0447\043a\0430 \0437\0430 \043c\0435\0441\044f\0446', 'revenue_month', 1, 1, 28, 9, '#F97316', ' ₽'),
  ('00000000-0000-4000-8000-000000000912'::uuid, U&'\041f\0440\0438\0431\044b\043b\044c \0437\0430 \043c\0435\0441\044f\0446', 'profit_month', 30, 1, 28, 9, '#14B8A6', ' ₽'),
  ('00000000-0000-4000-8000-000000000913'::uuid, U&'\041e\043f\043b\0430\0447\0435\043d\043e \0437\0430 \043c\0435\0441\044f\0446', 'paid_month', 1, 11, 28, 9, '#22C55E', ' ₽'),
  ('00000000-0000-4000-8000-000000000914'::uuid, U&'\041d\0430\043c \0434\043e\043b\0436\043d\044b', 'receivable', 30, 11, 28, 9, '#EAB308', ' ₽'),
  ('00000000-0000-4000-8000-000000000915'::uuid, U&'\0412\044b\0440\0443\0447\043a\0430 \0437\0430 \0433\043e\0434', 'revenue_year', 1, 21, 28, 9, '#FB923C', ' ₽'),
  ('00000000-0000-4000-8000-000000000916'::uuid, U&'\041f\0440\0438\0431\044b\043b\044c \0437\0430 \0433\043e\0434', 'profit_year', 30, 21, 28, 9, '#0D9488', ' ₽'),
  ('00000000-0000-4000-8000-000000000917'::uuid, U&'\0410\043a\0442\0438\0432\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432', 'orders_active', 1, 31, 28, 9, '#38BDF8', ''),
  ('00000000-0000-4000-8000-000000000918'::uuid, U&'\041d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0445 \0437\0430\043a\0430\0437\043e\0432', 'orders_unpaid', 30, 31, 28, 9, '#F43F5E', '')
)
INSERT INTO directus_panels (
  id, dashboard, name, icon, color, show_header, type,
  position_x, position_y, width, height, options
)
SELECT
  panel_id,
  '00000000-0000-4000-8000-000000000901',
  panel_name,
  'payments',
  color_value,
  true,
  'metric',
  x,
  y,
  w,
  h,
  json_build_object(
    'collection', 'finance_dashboard_metrics',
    'field', 'value',
    'function', 'sum',
    'filter', json_build_object('metric_key', json_build_object('_eq', filter_key)),
    'prefix', '',
    'suffix', suffix_value,
    'decimals', 0
  )::json
FROM finance_panels;

INSERT INTO directus_panels (
  id, dashboard, name, icon, color, show_header, type,
  position_x, position_y, width, height, options
) VALUES
  (
    '00000000-0000-4000-8000-000000000922',
    '00000000-0000-4000-8000-000000000901',
    U&'\0414\0438\043d\0430\043c\0438\043a\0430 \0434\0435\043d\0435\0433 \0437\0430 12 \043c\0435\0441\044f\0446\0435\0432',
    'show_chart',
    '#F97316',
    true,
    'line-chart',
    1,
    41,
    57,
    17,
    json_build_object(
      'collection', 'finance_dashboard_series',
      'xAxis', 'month_label',
      'yAxis', 'value',
      'aggregation', 'sum',
      'grouping', 'metric_name',
      'filter', json_build_object('metric_key', json_build_object('_in', json_build_array('revenue', 'paid', 'profit', 'expenses'))),
      'decimals', 0,
      'color', '#F97316',
      'curveType', 'smooth',
      'fillType', 'gradient',
      'showAxisLabels', 'both',
      'showMarker', true,
      'showLegend', true
    )::json
  ),
  (
    '00000000-0000-4000-8000-000000000923',
    '00000000-0000-4000-8000-000000000901',
    U&'\0412\0437\0430\0438\043c\043e\0440\0430\0441\0447\0435\0442\044b',
    'bar_chart',
    '#EAB308',
    true,
    'bar-chart',
    1,
    59,
    28,
    14,
    json_build_object(
      'collection', 'finance_dashboard_metrics',
      'horizontal', true,
      'xAxis', 'title',
      'yAxis', 'value',
      'function', 'sum',
      'filter', json_build_object('metric_group', json_build_object('_eq', 'balance')),
      'decimals', 0,
      'color', '#EAB308',
      'showAxisLabels', 'both',
      'showDataLabel', true
    )::json
  ),
  (
    '00000000-0000-4000-8000-000000000924',
    '00000000-0000-4000-8000-000000000901',
    U&'\0414\0435\0431\0438\0442\043e\0440\043a\0430 \043f\043e \043c\0435\0441\044f\0446\0430\043c',
    'stacked_line_chart',
    '#38BDF8',
    true,
    'line-chart',
    30,
    59,
    28,
    14,
    json_build_object(
      'collection', 'finance_dashboard_series',
      'xAxis', 'month_label',
      'yAxis', 'value',
      'aggregation', 'sum',
      'grouping', 'metric_name',
      'filter', json_build_object('metric_key', json_build_object('_eq', 'receivable')),
      'decimals', 0,
      'color', '#38BDF8',
      'curveType', 'smooth',
      'fillType', 'gradient',
      'showAxisLabels', 'both',
      'showMarker', true,
      'showLegend', false
    )::json
  );

SELECT sync_office_issue_order(id)
FROM orders
WHERE shipping_method = 'office_pickup';

SELECT refresh_finance_dashboard_metrics();

SELECT refresh_customer_reconciliation();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'contractor_costing'
      AND c.relkind = 'v'
  ) THEN
    EXECUTE 'DROP VIEW contractor_costing CASCADE';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS contractor_costing (
  id integer PRIMARY KEY,
  "order" integer,
  order_link integer,
  order_number varchar(255),
  date timestamp without time zone,
  order_deadline timestamp without time zone,
  customer integer,
  customer_company integer,
  manager_employee integer,
  product_name varchar(255),
  quantity numeric(10,2),
  price_per_unit numeric(10,2),
  order_sum numeric(10,2),
  product_category integer,
  product_subcategory integer,
  application_method integer,
  blank_source varchar(255) DEFAULT 'none',
  blank_ordered boolean NOT NULL DEFAULT false,
  contractor_1 integer,
  contractor_2 integer,
  contractor_1_cost numeric(10,2) DEFAULT 0,
  contractor_2_cost numeric(10,2) DEFAULT 0,
  unit_cost numeric(10,2) DEFAULT 0,
  total_cost numeric(10,2) DEFAULT 0,
  manager_commission_sum numeric(10,2) DEFAULT 0,
  tax_sum numeric(10,2) DEFAULT 0,
  profit_sum numeric(10,2) DEFAULT 0,
  margin_percent numeric(10,2) DEFAULT 0,
  item_status varchar(255),
  production_status integer,
  deadline timestamp without time zone
);

ALTER TABLE contractor_costing ADD COLUMN IF NOT EXISTS blank_source varchar(255) DEFAULT 'none';
ALTER TABLE contractor_costing ADD COLUMN IF NOT EXISTS blank_ordered boolean NOT NULL DEFAULT false;
ALTER TABLE contractor_costing ADD COLUMN IF NOT EXISTS manager_commission_sum numeric(10,2) DEFAULT 0;
ALTER TABLE contractor_costing ADD COLUMN IF NOT EXISTS tax_sum numeric(10,2) DEFAULT 0;

CREATE OR REPLACE FUNCTION sync_contractor_costing_item(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO contractor_costing (
    id, "order", order_link, order_number, date, order_deadline, customer, customer_company,
    manager_employee, product_name, quantity, price_per_unit, order_sum, product_category,
    product_subcategory, application_method, blank_source, blank_ordered, contractor_1,
    contractor_2, contractor_1_cost, contractor_2_cost, unit_cost, total_cost,
    manager_commission_sum, tax_sum, profit_sum, margin_percent, item_status, production_status, deadline
  )
  SELECT
    oi.id,
    oi."order",
    oi.order_link,
    o.order_number,
    o.date,
    o.deadline,
    o.customer,
    o.customer_company,
    o.manager_employee,
    oi.product_name,
    oi.quantity,
    oi.price_per_unit,
    oi.order_sum,
    oi.product_category,
    oi.product_subcategory,
    oi.application_method,
    COALESCE(oi.blank_source, 'none'),
    COALESCE(oi.blank_ordered, false),
    oi.contractor_1,
    oi.contractor_2,
    oi.contractor_1_cost,
    oi.contractor_2_cost,
    oi.unit_cost,
    oi.total_cost,
    oi.manager_commission_sum,
    oi.tax_sum,
    oi.profit_sum,
    oi.margin_percent,
    oi.item_status,
    oi.production_status,
    oi.deadline
  FROM orders_items oi
  LEFT JOIN orders o ON o.id = oi."order"
  WHERE oi.id = item_id
  ON CONFLICT (id) DO UPDATE SET
    "order" = EXCLUDED."order",
    order_link = EXCLUDED.order_link,
    order_number = EXCLUDED.order_number,
    date = EXCLUDED.date,
    order_deadline = EXCLUDED.order_deadline,
    customer = EXCLUDED.customer,
    customer_company = EXCLUDED.customer_company,
    manager_employee = EXCLUDED.manager_employee,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    price_per_unit = EXCLUDED.price_per_unit,
    order_sum = EXCLUDED.order_sum,
    product_category = EXCLUDED.product_category,
    product_subcategory = EXCLUDED.product_subcategory,
    application_method = EXCLUDED.application_method,
    blank_source = EXCLUDED.blank_source,
    blank_ordered = EXCLUDED.blank_ordered,
    contractor_1 = EXCLUDED.contractor_1,
    contractor_2 = EXCLUDED.contractor_2,
    contractor_1_cost = EXCLUDED.contractor_1_cost,
    contractor_2_cost = EXCLUDED.contractor_2_cost,
    unit_cost = EXCLUDED.unit_cost,
    total_cost = EXCLUDED.total_cost,
    manager_commission_sum = EXCLUDED.manager_commission_sum,
    tax_sum = EXCLUDED.tax_sum,
    profit_sum = EXCLUDED.profit_sum,
    margin_percent = EXCLUDED.margin_percent,
    item_status = EXCLUDED.item_status,
    production_status = EXCLUDED.production_status,
    deadline = EXCLUDED.deadline;
END;
$$;

CREATE OR REPLACE FUNCTION sync_contractor_costing_item_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM contractor_costing WHERE id = OLD.id;
    RETURN OLD;
  END IF;

  PERFORM sync_contractor_costing_item(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_contractor_costing_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  item_row record;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM contractor_costing WHERE "order" = OLD.id;
    RETURN OLD;
  END IF;

  FOR item_row IN SELECT id FROM orders_items WHERE "order" = NEW.id LOOP
    PERFORM sync_contractor_costing_item(item_row.id);
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION push_contractor_costing_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  UPDATE orders_items
  SET
    contractor_1 = NEW.contractor_1,
    contractor_2 = NEW.contractor_2,
    blank_source = COALESCE(NEW.blank_source, 'none'),
    blank_ordered = COALESCE(NEW.blank_ordered, false),
    contractor_1_cost = COALESCE(NEW.contractor_1_cost, 0),
    contractor_2_cost = COALESCE(NEW.contractor_2_cost, 0)
  WHERE id = NEW.id
    AND (
      contractor_1 IS DISTINCT FROM NEW.contractor_1
      OR contractor_2 IS DISTINCT FROM NEW.contractor_2
      OR blank_source IS DISTINCT FROM COALESCE(NEW.blank_source, 'none')
      OR blank_ordered IS DISTINCT FROM COALESCE(NEW.blank_ordered, false)
      OR contractor_1_cost IS DISTINCT FROM COALESCE(NEW.contractor_1_cost, 0)
      OR contractor_2_cost IS DISTINCT FROM COALESCE(NEW.contractor_2_cost, 0)
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contractor_costing_sync_item ON orders_items;
CREATE TRIGGER contractor_costing_sync_item
AFTER INSERT OR DELETE OR UPDATE OF
  "order", order_link, product_name, quantity, price_per_unit, order_sum,
  product_category, product_subcategory, application_method,
  blank_source, blank_ordered, contractor_1, contractor_2,
  contractor_1_cost, contractor_2_cost, unit_cost, total_cost,
  manager_commission_sum, tax_sum, profit_sum, margin_percent,
  item_status, production_status, deadline
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_costing_item_trigger();

DROP TRIGGER IF EXISTS contractor_costing_sync_order ON orders;
CREATE TRIGGER contractor_costing_sync_order
AFTER DELETE OR UPDATE OF
  order_number, date, deadline, customer, customer_company, manager_employee
ON orders
FOR EACH ROW
EXECUTE FUNCTION sync_contractor_costing_order_trigger();

DROP TRIGGER IF EXISTS contractor_costing_push_update ON contractor_costing;
CREATE TRIGGER contractor_costing_push_update
AFTER UPDATE OF contractor_1, contractor_2, contractor_1_cost, contractor_2_cost, blank_source, blank_ordered ON contractor_costing
FOR EACH ROW
EXECUTE FUNCTION push_contractor_costing_update();

CREATE OR REPLACE FUNCTION ensure_procurement_batch_task(batch_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  batch_row record;
  admin_employee integer;
  managing_employee integer;
  purchase_task_id integer;
  managing_task_id integer;
  purchase_task_status varchar(32);
  purchase_task_title text;
  purchase_task_description text;
BEGIN
  SELECT
    pb.*,
    c.name AS supplier_name,
    COALESCE(string_agg(
      concat(
        COALESCE(NULLIF(pr.product_name, ''), 'Позиция'),
        ' — ', trim(to_char(COALESCE(pr.quantity, 0), 'FM999999990.###')), ' ', COALESCE(pr.unit, 'шт.'),
        CASE WHEN o.order_number IS NOT NULL THEN concat(' (', o.order_number, ')') ELSE '' END,
        CASE WHEN NULLIF(pr.product_url, '') IS NOT NULL THEN concat(E'\n', pr.product_url) ELSE '' END,
        CASE WHEN NULLIF(pr.comment, '') IS NOT NULL THEN concat(E'\n', pr.comment) ELSE '' END
      ),
      E'\n' ORDER BY pr.id
    ), '') AS request_lines
  INTO batch_row
  FROM procurement_batches pb
  LEFT JOIN contractors c ON c.id = pb.supplier
  LEFT JOIN procurement_requests pr ON pr.procurement_batch = pb.id
  LEFT JOIN orders o ON o.id = pr.related_order
  WHERE pb.id = batch_id
  GROUP BY pb.id, c.name;

  IF NOT FOUND OR COALESCE(batch_row.item_count, 0) = 0 THEN
    RETURN;
  END IF;

  SELECT e.id
  INTO admin_employee
  FROM employees e
  JOIN directus_users u ON u.id = e.directus_user
  JOIN directus_roles r ON r.id = u.role
  WHERE COALESCE(e.is_active, true) = true
    AND COALESCE(u.status, 'active') = 'active'
    AND r.name = 'Administrator'
  ORDER BY CASE WHEN lower(COALESCE(u.email, '')) LIKE 'test-%' THEN 1 ELSE 0 END, e.id
  LIMIT 1;

  SELECT e.id
  INTO managing_employee
  FROM employees e
  JOIN directus_users u ON u.id = e.directus_user
  JOIN directus_roles r ON r.id = u.role
  WHERE COALESCE(e.is_active, true) = true
    AND COALESCE(u.status, 'active') = 'active'
    AND r.name = 'Управляющий'
  ORDER BY e.id
  LIMIT 1;

  purchase_task_id := batch_row.task_order_id;
  IF purchase_task_id IS NULL THEN
    SELECT pr.task_order_id
    INTO purchase_task_id
    FROM procurement_requests pr
    JOIN symbolika_tasks task ON task.id = pr.task_order_id
    WHERE pr.procurement_batch = batch_id
      AND task.task_type = 'procurement'
    ORDER BY pr.id
    LIMIT 1;
  END IF;

  purchase_task_status := CASE
    WHEN batch_row.status = 'cancelled' THEN 'cancelled'
    WHEN batch_row.status = 'need_order' THEN 'new'
    ELSE 'done'
  END;
  purchase_task_title := concat(
    'Закупить у ',
    COALESCE(NULLIF(batch_row.supplier_name, ''), NULLIF(batch_row.purchase_place, ''), 'место закупки не указано'),
    ': ', batch_row.item_count, ' поз.'
  );
  purchase_task_description := concat_ws(E'\n',
    concat('Закупка: ', batch_row.batch_number),
    concat('Поставщик: ', COALESCE(batch_row.supplier_name, 'не назначен')),
    concat('Где покупаем: ', COALESCE(batch_row.purchase_place, batch_row.supplier_name, 'не указано')),
    concat('Позиций: ', batch_row.item_count),
    concat('Плановая сумма: ', trim(to_char(COALESCE(batch_row.estimated_total, 0), 'FM999999990.00'))),
    concat('Получение: ', COALESCE(batch_row.delivery_method, 'unknown')),
    NULLIF(batch_row.request_lines, ''),
    NULLIF(batch_row.comment, '')
  );

  IF purchase_task_id IS NULL THEN
    INSERT INTO symbolika_tasks (
      title, description, task_type, status, priority, due_date, completed_at,
      assigned_to, created_by_employee, date_updated
    ) VALUES (
      purchase_task_title, purchase_task_description, 'procurement', purchase_task_status, 'high',
      COALESCE(batch_row.pickup_deadline, current_date),
      CASE WHEN purchase_task_status = 'done' THEN now() ELSE NULL END,
      admin_employee, admin_employee, now()
    ) RETURNING id INTO purchase_task_id;
  ELSE
    UPDATE symbolika_tasks
    SET title = purchase_task_title,
        description = purchase_task_description,
        task_type = 'procurement',
        status = purchase_task_status,
        priority = 'high',
        due_date = COALESCE(batch_row.pickup_deadline, due_date, current_date),
        completed_at = CASE WHEN purchase_task_status = 'done' THEN COALESCE(completed_at, now()) ELSE NULL END,
        assigned_to = COALESCE(admin_employee, assigned_to),
        date_updated = now()
    WHERE id = purchase_task_id;
  END IF;

  UPDATE procurement_batches
  SET task_order_id = purchase_task_id,
      responsible_employee = COALESCE(admin_employee, responsible_employee),
      date_updated = now()
  WHERE id = batch_id;

  -- Procurement currently has a single responsible person: the administrator.
  -- Preserve completed historical tasks, but remove secondary management tasks
  -- from active work and do not create new duplicates for the manager role.
  managing_task_id := batch_row.management_task_id;
  IF managing_task_id IS NOT NULL
     AND managing_task_id IS DISTINCT FROM purchase_task_id THEN
    UPDATE symbolika_tasks
    SET status = CASE WHEN status = 'done' THEN status ELSE 'cancelled' END,
        assigned_to = COALESCE(admin_employee, assigned_to),
        date_updated = now()
    WHERE id = managing_task_id;

    UPDATE procurement_batches
    SET management_task_id = NULL,
        date_updated = now()
    WHERE id = batch_id;
  END IF;

  managing_task_id := NULL;
  managing_employee := NULL;
  IF managing_employee IS NOT NULL AND managing_employee IS DISTINCT FROM admin_employee THEN
    IF managing_task_id IS NULL THEN
      INSERT INTO symbolika_tasks (
        title, description, task_type, status, priority, due_date, completed_at,
        assigned_to, created_by_employee, date_updated
      ) VALUES (
        purchase_task_title, purchase_task_description, 'procurement', purchase_task_status, 'high',
        COALESCE(batch_row.pickup_deadline, current_date),
        CASE WHEN purchase_task_status = 'done' THEN now() ELSE NULL END,
        managing_employee, COALESCE(admin_employee, managing_employee), now()
      ) RETURNING id INTO managing_task_id;
    ELSE
      UPDATE symbolika_tasks
      SET title = purchase_task_title,
          description = purchase_task_description,
          status = purchase_task_status,
          due_date = COALESCE(batch_row.pickup_deadline, due_date, current_date),
          completed_at = CASE WHEN purchase_task_status = 'done' THEN COALESCE(completed_at, now()) ELSE NULL END,
          assigned_to = managing_employee,
          date_updated = now()
      WHERE id = managing_task_id;
    END IF;

    UPDATE procurement_batches
    SET management_task_id = managing_task_id,
        date_updated = now()
    WHERE id = batch_id;
  END IF;

  UPDATE procurement_requests
  SET task_order_id = NULL,
      responsible_employee = COALESCE(admin_employee, responsible_employee),
      date_updated = now()
  WHERE procurement_batch = batch_id
    AND task_order_id IS NOT NULL;
END;
$$;

-- Remove the former duplicate procurement task for the manager. The primary
-- batch task remains assigned to the administrator; completed history stays
-- completed, while an unfinished duplicate is archived as cancelled.
UPDATE symbolika_tasks task
SET status = CASE WHEN task.status = 'done' THEN task.status ELSE 'cancelled' END,
    assigned_to = COALESCE(
      (SELECT primary_task.assigned_to
       FROM symbolika_tasks primary_task
       WHERE primary_task.id = batch.task_order_id),
      batch.responsible_employee,
      task.assigned_to
    ),
    date_updated = now()
FROM procurement_batches batch
WHERE task.id = batch.management_task_id
  AND batch.management_task_id IS NOT NULL
  AND batch.management_task_id IS DISTINCT FROM batch.task_order_id;

UPDATE procurement_batches
SET management_task_id = NULL,
    date_updated = now()
WHERE management_task_id IS NOT NULL
  AND management_task_id IS DISTINCT FROM task_order_id;

CREATE OR REPLACE FUNCTION refresh_procurement_batch(batch_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  request_count integer;
BEGIN
  SELECT count(*)::integer
  INTO request_count
  FROM procurement_requests
  WHERE procurement_batch = batch_id;

  IF request_count = 0 THEN
    UPDATE symbolika_tasks
    SET status = CASE WHEN status = 'done' THEN status ELSE 'cancelled' END,
        date_updated = now()
    WHERE id IN (
      SELECT task_order_id FROM procurement_batches WHERE id = batch_id
      UNION ALL
      SELECT management_task_id FROM procurement_batches WHERE id = batch_id
    );
    DELETE FROM procurement_batches WHERE id = batch_id AND status = 'need_order';
    RETURN;
  END IF;

  UPDATE procurement_batches pb
  SET item_count = totals.item_count,
      estimated_total = totals.estimated_total,
      pickup_deadline = totals.pickup_deadline,
      date_updated = now()
  FROM (
    SELECT
      count(*)::integer AS item_count,
      COALESCE(sum(COALESCE(quantity, 0) * COALESCE(estimated_cost, 0)), 0)::numeric(14,2) AS estimated_total,
      min(pickup_deadline) AS pickup_deadline
    FROM procurement_requests
    WHERE procurement_batch = batch_id
  ) totals
  WHERE pb.id = batch_id;

  PERFORM ensure_procurement_batch_task(batch_id);
END;
$$;

UPDATE procurement_batches pb
SET item_count = totals.item_count,
    estimated_total = totals.estimated_total,
    pickup_deadline = totals.pickup_deadline,
    date_updated = now()
FROM (
  SELECT
    procurement_batch AS batch_id,
    count(*)::integer AS item_count,
    COALESCE(sum(COALESCE(quantity, 0) * COALESCE(estimated_cost, 0)), 0)::numeric(14,2) AS estimated_total,
    min(pickup_deadline) AS pickup_deadline
  FROM procurement_requests
  WHERE procurement_batch IS NOT NULL
  GROUP BY procurement_batch
) totals
WHERE pb.id = totals.batch_id
  AND (
    pb.item_count IS DISTINCT FROM totals.item_count
    OR pb.estimated_total IS DISTINCT FROM totals.estimated_total
    OR pb.pickup_deadline IS DISTINCT FROM totals.pickup_deadline
  );

CREATE OR REPLACE FUNCTION sync_procurement_batch_for_request(request_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  request_row procurement_requests%ROWTYPE;
  current_batch procurement_batches%ROWTYPE;
  target_batch_id integer;
  old_batch_id integer;
  grouping_key text;
BEGIN
  SELECT * INTO request_row FROM procurement_requests WHERE id = request_id;
  IF NOT FOUND THEN RETURN; END IF;

  old_batch_id := request_row.procurement_batch;

  IF request_row.status <> 'need_order' THEN
    IF old_batch_id IS NOT NULL THEN PERFORM refresh_procurement_batch(old_batch_id); END IF;
    RETURN;
  END IF;

  IF old_batch_id IS NOT NULL THEN
    SELECT * INTO current_batch FROM procurement_batches WHERE id = old_batch_id;
    IF FOUND
       AND current_batch.status = 'need_order'
       AND current_batch.supplier IS NOT DISTINCT FROM request_row.supplier
       AND current_batch.purchase_source_type IS NOT DISTINCT FROM COALESCE(request_row.purchase_source_type, 'supplier')
       AND current_batch.purchase_place IS NOT DISTINCT FROM request_row.purchase_place
       AND current_batch.delivery_method IS NOT DISTINCT FROM COALESCE(request_row.delivery_method, 'unknown')
       AND current_batch.transport_company IS NOT DISTINCT FROM request_row.transport_company
       AND current_batch.supplier_city IS NOT DISTINCT FROM request_row.supplier_city
       AND current_batch.pickup_address IS NOT DISTINCT FROM request_row.pickup_address THEN
      PERFORM refresh_procurement_batch(old_batch_id);
      RETURN;
    END IF;
  END IF;

  grouping_key := concat_ws('|',
    COALESCE(request_row.supplier::text, 'none'),
    COALESCE(request_row.purchase_source_type, 'supplier'),
    lower(COALESCE(request_row.purchase_place, '')),
    COALESCE(request_row.delivery_method, 'unknown'),
    COALESCE(request_row.transport_company, ''),
    COALESCE(request_row.supplier_city, ''),
    COALESCE(request_row.pickup_address, '')
  );
  PERFORM pg_advisory_xact_lock(hashtext(grouping_key));

  SELECT id
  INTO target_batch_id
  FROM procurement_batches
  WHERE status = 'need_order'
    AND supplier IS NOT DISTINCT FROM request_row.supplier
    AND purchase_source_type IS NOT DISTINCT FROM COALESCE(request_row.purchase_source_type, 'supplier')
    AND purchase_place IS NOT DISTINCT FROM request_row.purchase_place
    AND delivery_method IS NOT DISTINCT FROM COALESCE(request_row.delivery_method, 'unknown')
    AND transport_company IS NOT DISTINCT FROM request_row.transport_company
    AND supplier_city IS NOT DISTINCT FROM request_row.supplier_city
    AND pickup_address IS NOT DISTINCT FROM request_row.pickup_address
  ORDER BY id
  LIMIT 1;

  IF target_batch_id IS NULL THEN
    INSERT INTO procurement_batches (
      supplier, purchase_source_type, purchase_place, status, delivery_method, transport_company, supplier_city, pickup_address, pickup_deadline, date_updated
    ) VALUES (
      request_row.supplier, COALESCE(request_row.purchase_source_type, 'supplier'), request_row.purchase_place,
      'need_order', COALESCE(request_row.delivery_method, 'unknown'),
      request_row.transport_company, request_row.supplier_city, request_row.pickup_address,
      request_row.pickup_deadline, now()
    ) RETURNING id INTO target_batch_id;
  END IF;

  UPDATE procurement_requests
  SET procurement_batch = target_batch_id,
      date_updated = now()
  WHERE id = request_id;

  PERFORM refresh_procurement_batch(target_batch_id);
  IF old_batch_id IS NOT NULL AND old_batch_id <> target_batch_id THEN
    PERFORM refresh_procurement_batch(old_batch_id);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sync_procurement_batch_request_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM sync_procurement_batch_for_request(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procurement_batch_request_sync ON procurement_requests;
CREATE TRIGGER procurement_batch_request_sync
AFTER INSERT OR UPDATE OF supplier, request_source, purchase_source_type, purchase_place, product_url, delivery_method, transport_company, supplier_city, pickup_address, pickup_deadline, product_name, quantity, unit, estimated_cost, comment, status ON procurement_requests
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_batch_request_trigger();

CREATE OR REPLACE FUNCTION ensure_procurement_purchase_task(request_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  request_row record;
  admin_employee integer;
  author_employee integer;
  purchase_task_id integer;
  purchase_task_status varchar(32);
  purchase_task_title text;
  purchase_task_description text;
BEGIN
  SELECT
    pr.*,
    c.name AS supplier_name,
    o.order_number
  INTO request_row
  FROM procurement_requests pr
  LEFT JOIN contractors c ON c.id = pr.supplier
  LEFT JOIN orders o ON o.id = pr.related_order
  WHERE pr.id = request_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF request_row.procurement_batch IS NOT NULL THEN
    RETURN;
  END IF;

  SELECT e.id
  INTO admin_employee
  FROM employees e
  JOIN directus_users u ON u.id = e.directus_user
  JOIN directus_roles r ON r.id = u.role
  WHERE COALESCE(e.is_active, true) = true
    AND COALESCE(u.status, 'active') = 'active'
    AND r.name = 'Administrator'
  ORDER BY
    CASE WHEN lower(COALESCE(u.email, '')) LIKE 'test-%' THEN 1 ELSE 0 END,
    e.id
  LIMIT 1;

  IF admin_employee IS NULL THEN
    SELECT e.id
    INTO admin_employee
    FROM employees e
    LEFT JOIN employee_positions ep ON ep.id = e.position
    WHERE COALESCE(e.is_active, true) = true
      AND lower(COALESCE(ep.name, '')) IN ('админ', 'администратор')
    ORDER BY e.id
    LIMIT 1;
  END IF;

  author_employee := COALESCE(
    request_row.requested_by_employee,
    request_row.manager_employee,
    request_row.responsible_employee,
    admin_employee
  );

  purchase_task_status := CASE
    WHEN request_row.status = 'cancelled' THEN 'cancelled'
    WHEN request_row.status = 'need_order' THEN 'new'
    ELSE 'done'
  END;

  purchase_task_title := concat('Закупить: ', COALESCE(NULLIF(request_row.product_name, ''), 'позиция'));
  purchase_task_description := concat_ws(E'\n',
    concat('Количество: ', trim(to_char(COALESCE(request_row.quantity, 0), 'FM999999990.###')), ' ', COALESCE(request_row.unit, 'шт.')),
    concat('Участок: ', CASE COALESCE(request_row.section, 'general')
      WHEN 'production' THEN 'Производство'
      WHEN 'screen_printing' THEN 'Шелкография'
      WHEN 'office' THEN 'Офис'
      ELSE 'Общее'
    END),
    concat('Поставщик: ', COALESCE(request_row.supplier_name, 'не выбран')),
    CASE WHEN request_row.order_number IS NOT NULL THEN concat('Заказ: ', request_row.order_number) END,
    CASE WHEN request_row.auto_generated THEN 'Источник: минимальный остаток склада' ELSE 'Источник: ручная заявка' END,
    NULLIF(request_row.comment, '')
  );

  purchase_task_id := request_row.task_order_id;

  IF purchase_task_id IS NULL THEN
    INSERT INTO symbolika_tasks (
      title,
      description,
      task_type,
      status,
      priority,
      due_date,
      completed_at,
      assigned_to,
      created_by_employee,
      related_order,
      related_order_item,
      date_updated
    )
    VALUES (
      purchase_task_title,
      purchase_task_description,
      'procurement',
      purchase_task_status,
      'high',
      COALESCE(request_row.pickup_deadline, current_date),
      CASE WHEN purchase_task_status = 'done' THEN now() ELSE NULL END,
      admin_employee,
      author_employee,
      request_row.related_order,
      request_row.order_item,
      now()
    )
    RETURNING id INTO purchase_task_id;

    UPDATE procurement_requests
    SET task_order_id = purchase_task_id,
        responsible_employee = COALESCE(admin_employee, responsible_employee),
        date_updated = now()
    WHERE id = request_row.id;
  ELSE
    UPDATE symbolika_tasks
    SET title = purchase_task_title,
        description = purchase_task_description,
        task_type = 'procurement',
        status = purchase_task_status,
        priority = 'high',
        due_date = COALESCE(request_row.pickup_deadline, due_date, current_date),
        completed_at = CASE
          WHEN purchase_task_status = 'done' THEN COALESCE(completed_at, now())
          ELSE NULL
        END,
        assigned_to = COALESCE(admin_employee, assigned_to),
        created_by_employee = COALESCE(created_by_employee, author_employee),
        related_order = request_row.related_order,
        related_order_item = request_row.order_item,
        date_updated = now()
    WHERE id = purchase_task_id;

    UPDATE procurement_requests
    SET responsible_employee = COALESCE(admin_employee, responsible_employee),
        date_updated = now()
    WHERE id = request_row.id
      AND responsible_employee IS DISTINCT FROM COALESCE(admin_employee, responsible_employee);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sync_procurement_purchase_task_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM ensure_procurement_purchase_task(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procurement_purchase_task_sync ON procurement_requests;
CREATE TRIGGER procurement_purchase_task_sync
AFTER INSERT OR UPDATE OF product_name, quantity, unit, section, supplier, request_source, purchase_source_type, purchase_place, product_url, pickup_deadline, comment, status ON procurement_requests
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_purchase_task_trigger();

CREATE OR REPLACE FUNCTION sync_inventory_low_stock_request(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  item_row record;
  shortage numeric(14,3);
BEGIN
  SELECT
    i.*,
    c.default_delivery_method,
    c.default_transport_company,
    c.city AS supplier_city,
    c.pickup_address
  INTO item_row
  FROM inventory_items i
  LEFT JOIN contractors c ON c.id = i.default_supplier
  WHERE i.id = item_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF COALESCE(item_row.is_active, false)
     AND COALESCE(item_row.min_qty, 0) > 0
     AND COALESCE(item_row.current_qty, 0) < item_row.min_qty THEN
    shortage := item_row.min_qty - COALESCE(item_row.current_qty, 0);

    INSERT INTO procurement_requests (
      request_type,
      request_source,
      purchase_source_type,
      purchase_place,
      section,
      status,
      supplier,
      inventory_item,
      product_name,
      quantity,
      unit,
      delivery_method,
      transport_company,
      supplier_city,
      pickup_address,
      auto_generated,
      date_updated
    )
    VALUES (
      CASE WHEN item_row.item_type = 'blank' THEN 'blank' ELSE 'consumable' END,
      'inventory_minimum',
      CASE WHEN item_row.default_supplier IS NULL THEN 'other' ELSE 'supplier' END,
      CASE WHEN item_row.default_supplier IS NULL THEN 'Не указано' ELSE NULL END,
      COALESCE(item_row.section, 'general'),
      'need_order',
      item_row.default_supplier,
      item_row.id,
      item_row.name,
      shortage,
      item_row.unit,
      COALESCE(item_row.default_delivery_method, 'unknown'),
      item_row.default_transport_company,
      item_row.supplier_city,
      item_row.pickup_address,
      true,
      now()
    )
    ON CONFLICT (inventory_item)
      WHERE inventory_item IS NOT NULL
        AND auto_generated = true
        AND status NOT IN ('received', 'cancelled')
    DO UPDATE SET
      request_type = EXCLUDED.request_type,
      request_source = EXCLUDED.request_source,
      purchase_source_type = EXCLUDED.purchase_source_type,
      purchase_place = EXCLUDED.purchase_place,
      section = EXCLUDED.section,
      supplier = EXCLUDED.supplier,
      product_name = EXCLUDED.product_name,
      quantity = CASE
        WHEN procurement_requests.status = 'need_order' THEN EXCLUDED.quantity
        ELSE procurement_requests.quantity
      END,
      unit = EXCLUDED.unit,
      delivery_method = CASE
        WHEN procurement_requests.status = 'need_order' THEN EXCLUDED.delivery_method
        ELSE procurement_requests.delivery_method
      END,
      transport_company = CASE
        WHEN procurement_requests.status = 'need_order' THEN EXCLUDED.transport_company
        ELSE procurement_requests.transport_company
      END,
      supplier_city = CASE
        WHEN procurement_requests.status = 'need_order' THEN EXCLUDED.supplier_city
        ELSE procurement_requests.supplier_city
      END,
      pickup_address = CASE
        WHEN procurement_requests.status = 'need_order' THEN EXCLUDED.pickup_address
        ELSE procurement_requests.pickup_address
      END,
      date_updated = now();
  ELSE
    UPDATE procurement_requests
    SET status = 'cancelled',
        date_updated = now()
    WHERE inventory_item = item_row.id
      AND auto_generated = true
      AND status = 'need_order';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sync_inventory_low_stock_request_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM sync_inventory_low_stock_request(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS inventory_low_stock_procurement_sync ON inventory_items;
CREATE TRIGGER inventory_low_stock_procurement_sync
AFTER INSERT OR UPDATE OF name, section, item_type, unit, current_qty, min_qty, default_supplier, is_active ON inventory_items
FOR EACH ROW
EXECUTE FUNCTION sync_inventory_low_stock_request_trigger();

CREATE OR REPLACE FUNCTION sync_blank_procurement_request(item_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  item_row record;
  supplier_row record;
  request_row procurement_requests%ROWTYPE;
  order_task_title text;
  pickup_task_title text;
  task_description text;
  pickup_description text;
  computed_pickup_deadline date;
  source_section text;
BEGIN
  SELECT
    oi.id,
    oi."order" AS order_id,
    oi.product_name,
    oi.quantity,
    oi.contractor_1,
    oi.contractor_1_cost,
    COALESCE(oi.blank_source, 'none') AS blank_source,
    o.order_number,
    o.customer,
    o.customer_company,
    o.manager_employee,
    o.deadline AS order_deadline,
    c.name AS customer_name,
    cc.name AS company_name
  INTO item_row
  FROM orders_items oi
  LEFT JOIN orders o ON o.id = oi."order"
  LEFT JOIN customers c ON c.id = o.customer
  LEFT JOIN customer_companies cc ON cc.id = o.customer_company
  WHERE oi.id = item_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF item_row.blank_source <> 'supplier' OR item_row.contractor_1 IS NULL THEN
    UPDATE procurement_requests
    SET status = CASE WHEN status = 'received' THEN status ELSE 'cancelled' END,
        comment = concat_ws(E'\n', NULLIF(comment, ''), 'Автоматически отменено: заготовка больше не закупается у поставщика.'),
        date_updated = now()
    WHERE order_item = item_row.id
      AND request_type = 'blank'
      AND status NOT IN ('received', 'cancelled');
    RETURN;
  END IF;

  SELECT *
  INTO supplier_row
  FROM contractors
  WHERE id = item_row.contractor_1;

  source_section := 'production';

  computed_pickup_deadline := CASE
    WHEN supplier_row.default_pickup_days IS NOT NULL THEN current_date + supplier_row.default_pickup_days
    ELSE NULL
  END;

    INSERT INTO procurement_requests (
    request_type, request_source, purchase_source_type, section, status, supplier, related_order, order_item, customer, customer_company,
    manager_employee, product_name, quantity, unit, estimated_cost, delivery_method, transport_company,
    supplier_city, pickup_address, pickup_deadline, responsible_employee, comment, date_updated
  )
  VALUES (
    'blank',
    'order_blank',
    'supplier',
    source_section,
    'need_order',
    item_row.contractor_1,
    item_row.order_id,
    item_row.id,
    item_row.customer,
    item_row.customer_company,
    item_row.manager_employee,
    item_row.product_name,
    COALESCE(item_row.quantity, 0),
    'шт.',
    COALESCE(item_row.contractor_1_cost, 0),
    COALESCE(supplier_row.default_delivery_method, 'self_pickup'),
    supplier_row.default_transport_company,
    supplier_row.city,
    supplier_row.pickup_address,
    computed_pickup_deadline,
    item_row.manager_employee,
    NULLIF(supplier_row.pickup_notes, ''),
    now()
  )
  ON CONFLICT (order_item, request_type)
    WHERE order_item IS NOT NULL AND request_type = 'blank'
  DO UPDATE SET
    request_source = EXCLUDED.request_source,
    purchase_source_type = EXCLUDED.purchase_source_type,
    section = EXCLUDED.section,
    status = CASE
      WHEN procurement_requests.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received') THEN procurement_requests.status
      ELSE 'need_order'
    END,
    supplier = EXCLUDED.supplier,
    related_order = EXCLUDED.related_order,
    customer = EXCLUDED.customer,
    customer_company = EXCLUDED.customer_company,
    manager_employee = EXCLUDED.manager_employee,
    product_name = EXCLUDED.product_name,
    quantity = EXCLUDED.quantity,
    estimated_cost = EXCLUDED.estimated_cost,
    delivery_method = EXCLUDED.delivery_method,
    transport_company = EXCLUDED.transport_company,
    supplier_city = EXCLUDED.supplier_city,
    pickup_address = EXCLUDED.pickup_address,
    pickup_deadline = COALESCE(procurement_requests.pickup_deadline, EXCLUDED.pickup_deadline),
    responsible_employee = COALESCE(procurement_requests.responsible_employee, EXCLUDED.responsible_employee),
    date_updated = now()
  RETURNING * INTO request_row;

  -- The generic procurement trigger may attach the administrator task after INSERT.
  SELECT *
  INTO request_row
  FROM procurement_requests
  WHERE id = request_row.id;

  -- Grouped purchases use one purchase/pickup workflow for the whole supplier batch.
  IF request_row.procurement_batch IS NOT NULL THEN
    PERFORM refresh_procurement_batch(request_row.procurement_batch);
    RETURN;
  END IF;

  order_task_title := concat('Заказать заготовку: ', COALESCE(item_row.product_name, 'позиция'));
  task_description := concat_ws(E'\n',
    concat('Заказ: ', COALESCE(item_row.order_number, '-')),
    concat('Заказчик: ', COALESCE(item_row.company_name, item_row.customer_name, '-')),
    concat('Позиция: ', COALESCE(item_row.product_name, '-')),
    concat('Количество: ', trim(to_char(COALESCE(item_row.quantity, 0), 'FM999999990.##')), ' шт.'),
    concat('Поставщик: ', COALESCE(supplier_row.name, '-')),
    concat('Город: ', COALESCE(supplier_row.city, '-')),
    concat('Адрес: ', COALESCE(supplier_row.pickup_address, '-')),
    concat('Получение: ', COALESCE(supplier_row.default_delivery_method, 'self_pickup')),
    concat('ТК: ', COALESCE(supplier_row.default_transport_company, '-')),
    concat('Комментарий: ', COALESCE(supplier_row.pickup_notes, '-'))
  );

  IF request_row.task_order_id IS NULL THEN
    INSERT INTO symbolika_tasks (
      title, description, status, priority, due_date, assigned_to, created_by_employee,
      related_order, related_order_item, related_customer, related_company, date_updated
    )
    VALUES (
      order_task_title, task_description, 'new', 'normal', COALESCE(computed_pickup_deadline, item_row.order_deadline::date),
      item_row.manager_employee, item_row.manager_employee, item_row.order_id, item_row.id,
      item_row.customer, item_row.customer_company, now()
    )
    RETURNING id INTO request_row.task_order_id;

    UPDATE procurement_requests
    SET task_order_id = request_row.task_order_id,
        date_updated = now()
    WHERE id = request_row.id;
  ELSE
    UPDATE symbolika_tasks
    SET title = order_task_title,
        description = task_description,
        due_date = COALESCE(computed_pickup_deadline, item_row.order_deadline::date, due_date),
        assigned_to = COALESCE(assigned_to, item_row.manager_employee),
        related_order = item_row.order_id,
        related_order_item = item_row.id,
        related_customer = item_row.customer,
        related_company = item_row.customer_company,
        date_updated = now()
    WHERE id = request_row.task_order_id
      AND status <> 'done';
  END IF;

  IF supplier_row.pickup_address IS NOT NULL OR supplier_row.default_transport_company IS NOT NULL THEN
    pickup_task_title := concat('Забрать/получить заготовку: ', COALESCE(item_row.product_name, 'позиция'));
    pickup_description := concat_ws(E'\n',
      concat('Заказ: ', COALESCE(item_row.order_number, '-')),
      concat('Поставщик: ', COALESCE(supplier_row.name, '-')),
      concat('Адрес/ПВЗ: ', COALESCE(supplier_row.pickup_address, '-')),
      concat('Транспортная компания: ', COALESCE(supplier_row.default_transport_company, '-')),
      concat('Ориентировочный срок: ', COALESCE(to_char(computed_pickup_deadline, 'DD.MM.YYYY'), 'уточнить')),
      concat('Позиция: ', COALESCE(item_row.product_name, '-')),
      concat('Количество: ', trim(to_char(COALESCE(item_row.quantity, 0), 'FM999999990.##')), ' шт.')
    );

    IF request_row.task_pickup_id IS NULL THEN
      INSERT INTO symbolika_tasks (
        title, description, status, priority, due_date, assigned_to, created_by_employee,
        related_order, related_order_item, related_customer, related_company, date_updated
      )
      VALUES (
        pickup_task_title, pickup_description, 'waiting', 'normal', computed_pickup_deadline,
        item_row.manager_employee, item_row.manager_employee, item_row.order_id, item_row.id,
        item_row.customer, item_row.customer_company, now()
      )
      RETURNING id INTO request_row.task_pickup_id;

      UPDATE procurement_requests
      SET task_pickup_id = request_row.task_pickup_id,
          date_updated = now()
      WHERE id = request_row.id;
    ELSE
      UPDATE symbolika_tasks
      SET title = pickup_task_title,
          description = pickup_description,
          due_date = COALESCE(computed_pickup_deadline, due_date),
          assigned_to = COALESCE(assigned_to, item_row.manager_employee),
          related_order = item_row.order_id,
          related_order_item = item_row.id,
          related_customer = item_row.customer,
          related_company = item_row.customer_company,
          date_updated = now()
      WHERE id = request_row.task_pickup_id
        AND status <> 'done';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sync_blank_procurement_request_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE procurement_requests
    SET status = CASE WHEN status = 'received' THEN status ELSE 'cancelled' END,
        date_updated = now()
    WHERE order_item = OLD.id
      AND request_type = 'blank'
      AND status NOT IN ('received', 'cancelled');
    RETURN OLD;
  END IF;

  PERFORM sync_blank_procurement_request(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_procurement_received_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'received' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    UPDATE orders_items
    SET blank_ordered = true
    WHERE id = NEW.order_item
      AND NEW.request_type = 'blank';

    IF NEW.task_order_id IS NOT NULL THEN
      UPDATE symbolika_tasks
      SET status = 'done',
          completed_at = COALESCE(completed_at, now()),
          date_updated = now()
      WHERE id = NEW.task_order_id;
    END IF;

    IF NEW.task_pickup_id IS NOT NULL THEN
      UPDATE symbolika_tasks
      SET status = 'done',
          completed_at = COALESCE(completed_at, now()),
          date_updated = now()
      WHERE id = NEW.task_pickup_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS blank_procurement_sync_item ON orders_items;
CREATE TRIGGER blank_procurement_sync_item
AFTER INSERT OR UPDATE OF "order", product_name, quantity, blank_source, contractor_1, contractor_1_cost, deadline ON orders_items
FOR EACH ROW
EXECUTE FUNCTION sync_blank_procurement_request_trigger();

DROP TRIGGER IF EXISTS blank_procurement_received_sync ON procurement_requests;
CREATE TRIGGER blank_procurement_received_sync
AFTER UPDATE OF status ON procurement_requests
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_received_trigger();

CREATE OR REPLACE FUNCTION sync_procurement_status_workflow_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  payment_task_id integer;
  payment_task_title text;
  payment_description text;
  assignee integer;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  assignee := COALESCE(NEW.responsible_employee, NEW.manager_employee);

  IF NEW.procurement_batch IS NOT NULL THEN
    IF NEW.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received') AND NEW.ordered_at IS NULL THEN
      UPDATE procurement_requests
      SET ordered_at = now(), date_updated = now()
      WHERE id = NEW.id;
    END IF;

    IF NEW.status = 'received' THEN
      UPDATE procurement_requests
      SET received_at = COALESCE(received_at, now()), date_updated = now()
      WHERE id = NEW.id;

      UPDATE orders_items
      SET blank_ordered = true
      WHERE id = NEW.order_item
        AND NEW.request_type = 'blank';
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received') THEN
    IF NEW.ordered_at IS NULL THEN
      UPDATE procurement_requests
      SET ordered_at = now(),
          date_updated = now()
      WHERE id = NEW.id;
    END IF;

    IF NEW.task_order_id IS NOT NULL THEN
      UPDATE symbolika_tasks
      SET status = 'done',
          completed_at = COALESCE(completed_at, now()),
          date_updated = now()
      WHERE id = NEW.task_order_id
        AND status <> 'done';
    END IF;
  END IF;

  IF NEW.status = 'ordered' THEN
    payment_task_title := concat('Оплатить закупку: ', COALESCE(NEW.product_name, 'позиция'));
    payment_description := concat_ws(E'\n',
      concat('Поставщик: ', COALESCE((SELECT name FROM contractors WHERE id = NEW.supplier), '-')),
      concat('Позиция: ', COALESCE(NEW.product_name, '-')),
      concat('Количество: ', trim(to_char(COALESCE(NEW.quantity, 0), 'FM999999990.##')), ' ', COALESCE(NEW.unit, 'шт.')),
      concat('Сумма: ', trim(to_char(COALESCE(NEW.quantity, 0) * COALESCE(NEW.estimated_cost, 0), 'FM999999990.00'))),
      concat('Получение: ', COALESCE(NEW.delivery_method, '-')),
      concat('Адрес/ПВЗ: ', COALESCE(NEW.pickup_address, '-')),
      concat('Комментарий: ', COALESCE(NEW.comment, '-'))
    );

    IF NEW.task_payment_id IS NULL THEN
      INSERT INTO symbolika_tasks (
        title, description, status, priority, due_date, assigned_to, created_by_employee,
        related_order, related_order_item, related_customer, related_company, date_updated
      )
      VALUES (
        payment_task_title, payment_description, 'new', 'high', current_date,
        assignee, NEW.manager_employee, NEW.related_order, NEW.order_item,
        NEW.customer, NEW.customer_company, now()
      )
      RETURNING id INTO payment_task_id;

      UPDATE procurement_requests
      SET task_payment_id = payment_task_id,
          date_updated = now()
      WHERE id = NEW.id;
    ELSE
      UPDATE symbolika_tasks
      SET title = payment_task_title,
          description = payment_description,
          status = CASE WHEN status = 'done' THEN status ELSE 'new' END,
          priority = 'high',
          due_date = COALESCE(due_date, current_date),
          assigned_to = COALESCE(assigned_to, assignee),
          date_updated = now()
      WHERE id = NEW.task_payment_id;
    END IF;
  END IF;

  IF NEW.status IN ('ready_for_pickup', 'in_transit', 'received') AND NEW.task_payment_id IS NOT NULL THEN
    UPDATE symbolika_tasks
    SET status = 'done',
        completed_at = COALESCE(completed_at, now()),
        date_updated = now()
    WHERE id = NEW.task_payment_id
      AND status <> 'done';
  END IF;

  IF NEW.status IN ('ready_for_pickup', 'in_transit') AND NEW.task_pickup_id IS NOT NULL THEN
    UPDATE symbolika_tasks
    SET status = CASE WHEN status = 'done' THEN status ELSE 'new' END,
        priority = 'high',
        assigned_to = COALESCE(assigned_to, assignee),
        date_updated = now()
    WHERE id = NEW.task_pickup_id;
  END IF;

  IF NEW.status = 'received' THEN
    IF NEW.received_at IS NULL THEN
      UPDATE procurement_requests
      SET received_at = now(),
          date_updated = now()
      WHERE id = NEW.id;
    END IF;

    UPDATE orders_items
    SET blank_ordered = true
    WHERE id = NEW.order_item
      AND NEW.request_type = 'blank';

    IF NEW.task_pickup_id IS NOT NULL THEN
      UPDATE symbolika_tasks
      SET status = 'done',
          completed_at = COALESCE(completed_at, now()),
          date_updated = now()
      WHERE id = NEW.task_pickup_id
        AND status <> 'done';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procurement_status_workflow_sync ON procurement_requests;
CREATE TRIGGER procurement_status_workflow_sync
AFTER UPDATE OF status ON procurement_requests
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_status_workflow_trigger();

CREATE OR REPLACE FUNCTION sync_procurement_batch_status_workflow_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  payment_task_id integer;
  pickup_task_id integer;
  supplier_name text;
  task_assignee integer;
  task_description text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  SELECT name INTO supplier_name FROM contractors WHERE id = NEW.supplier;
  task_assignee := NEW.responsible_employee;
  task_description := concat_ws(E'\n',
    concat('Закупка: ', NEW.batch_number),
    concat('Поставщик: ', COALESCE(supplier_name, 'не назначен')),
    concat('Позиций: ', NEW.item_count),
    concat('Сумма: ', trim(to_char(COALESCE(NEW.estimated_total, 0), 'FM999999990.00'))),
    concat('Получение: ', COALESCE(NEW.delivery_method, 'unknown')),
    concat('Адрес/ПВЗ: ', COALESCE(NEW.pickup_address, '-'))
  );

  UPDATE procurement_requests
  SET status = NEW.status,
      ordered_at = CASE
        WHEN NEW.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received') THEN COALESCE(ordered_at, now())
        ELSE ordered_at
      END,
      received_at = CASE WHEN NEW.status = 'received' THEN COALESCE(received_at, now()) ELSE received_at END,
      date_updated = now()
  WHERE procurement_batch = NEW.id
    AND status IS DISTINCT FROM NEW.status;

  IF NEW.task_order_id IS NOT NULL OR NEW.management_task_id IS NOT NULL THEN
    UPDATE symbolika_tasks
    SET status = CASE
          WHEN NEW.status = 'need_order' THEN 'new'
          WHEN NEW.status = 'cancelled' THEN 'cancelled'
          ELSE 'done'
        END,
        completed_at = CASE
          WHEN NEW.status IN ('need_order', 'cancelled') THEN NULL
          ELSE COALESCE(completed_at, now())
        END,
        date_updated = now()
    WHERE id IN (NEW.task_order_id, NEW.management_task_id);
  END IF;

  IF NEW.status = 'ordered' THEN
    payment_task_id := NEW.task_payment_id;
    IF payment_task_id IS NULL THEN
      INSERT INTO symbolika_tasks (
        title, description, task_type, status, priority, due_date, assigned_to, created_by_employee, date_updated
      ) VALUES (
        concat('Оплатить закупку: ', COALESCE(supplier_name, NEW.batch_number)),
        task_description, 'general', 'new', 'high', current_date,
        task_assignee, task_assignee, now()
      ) RETURNING id INTO payment_task_id;

      UPDATE procurement_batches
      SET task_payment_id = payment_task_id, date_updated = now()
      WHERE id = NEW.id;
    ELSE
      UPDATE symbolika_tasks
      SET status = CASE WHEN status = 'done' THEN status ELSE 'new' END,
          description = task_description,
          date_updated = now()
      WHERE id = payment_task_id;
    END IF;
  END IF;

  IF NEW.status IN ('ready_for_pickup', 'in_transit', 'received') AND NEW.task_payment_id IS NOT NULL THEN
    UPDATE symbolika_tasks
    SET status = 'done', completed_at = COALESCE(completed_at, now()), date_updated = now()
    WHERE id = NEW.task_payment_id AND status <> 'done';
  END IF;

  IF NEW.status IN ('ready_for_pickup', 'in_transit') THEN
    pickup_task_id := NEW.task_pickup_id;
    IF pickup_task_id IS NULL THEN
      INSERT INTO symbolika_tasks (
        title, description, task_type, status, priority, due_date, assigned_to, created_by_employee, date_updated
      ) VALUES (
        concat('Получить закупку: ', COALESCE(supplier_name, NEW.batch_number)),
        task_description, 'general', 'new', 'high', NEW.pickup_deadline,
        task_assignee, task_assignee, now()
      ) RETURNING id INTO pickup_task_id;

      UPDATE procurement_batches
      SET task_pickup_id = pickup_task_id, date_updated = now()
      WHERE id = NEW.id;
    ELSE
      UPDATE symbolika_tasks
      SET status = CASE WHEN status = 'done' THEN status ELSE 'new' END,
          description = task_description,
          date_updated = now()
      WHERE id = pickup_task_id;
    END IF;
  END IF;

  IF NEW.status = 'received' AND NEW.task_pickup_id IS NOT NULL THEN
    UPDATE symbolika_tasks
    SET status = 'done', completed_at = COALESCE(completed_at, now()), date_updated = now()
    WHERE id = NEW.task_pickup_id AND status <> 'done';
  END IF;

  IF NEW.status = 'cancelled' THEN
    UPDATE symbolika_tasks
    SET status = CASE WHEN status = 'done' THEN status ELSE 'cancelled' END,
        date_updated = now()
    WHERE id IN (NEW.task_payment_id, NEW.task_pickup_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procurement_batch_status_workflow_sync ON procurement_batches;
CREATE TRIGGER procurement_batch_status_workflow_sync
AFTER UPDATE OF status ON procurement_batches
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_batch_status_workflow_trigger();

CREATE OR REPLACE FUNCTION sync_procurement_status_from_purchase_task_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF pg_trigger_depth() > 1
     OR OLD.status IS NOT DISTINCT FROM NEW.status
     OR NEW.task_type <> 'procurement' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'done' THEN
    UPDATE procurement_batches
    SET status = 'ordered',
        date_updated = now()
    WHERE (task_order_id = NEW.id OR management_task_id = NEW.id)
      AND (supplier IS NOT NULL OR NULLIF(purchase_place, '') IS NOT NULL)
      AND status = 'need_order';

    UPDATE procurement_requests
    SET status = 'ordered',
        ordered_at = COALESCE(ordered_at, now()),
        date_updated = now()
    WHERE task_order_id = NEW.id
      AND status = 'need_order';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procurement_status_sync_from_task ON symbolika_tasks;
CREATE TRIGGER procurement_status_sync_from_task
AFTER UPDATE OF status ON symbolika_tasks
FOR EACH ROW
EXECUTE FUNCTION sync_procurement_status_from_purchase_task_trigger();

SELECT sync_contractor_costing_item(id)
FROM orders_items;

SELECT sync_blank_procurement_request(id)
FROM orders_items;

SELECT sync_inventory_low_stock_request(id)
FROM inventory_items;

SELECT sync_procurement_batch_for_request(id)
FROM procurement_requests
WHERE status = 'need_order';

UPDATE procurement_requests pr
SET status = 'ordered',
    ordered_at = COALESCE(pr.ordered_at, now()),
    date_updated = now()
FROM symbolika_tasks task
WHERE task.id = pr.task_order_id
  AND task.task_type = 'procurement'
  AND task.status = 'done'
  AND pr.status = 'need_order';

SELECT ensure_procurement_purchase_task(id)
FROM procurement_requests;

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, translations,
  archive_app_filter, accountability, sort, collapse, versioning
) VALUES (
  'contractor_costing',
  'price_check',
  'Quick workspace for admins and managers to assign contractors and item costs.',
  '{{order_number}} — {{product_name}}',
  false,
  false,
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043f\043e\043b\043d\0435\043d\0438\0435 \0441\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\0438'))::json,
  true,
  'all',
  27,
  'open',
  false
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  translations = EXCLUDED.translations,
  archive_app_filter = EXCLUDED.archive_app_filter,
  accountability = EXCLUDED.accountability,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse,
  versioning = EXCLUDED.versioning;

DELETE FROM directus_relations
WHERE many_collection = 'contractor_costing';

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_collection_field,
  one_allowed_collections, junction_field, sort_field, one_deselect_action
) VALUES
  ('contractor_costing', 'order', 'orders', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'order_link', 'orders', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'customer', 'customers', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'customer_company', 'customer_companies', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'manager_employee', 'employees', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'product_category', 'product_categories', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'product_subcategory', 'product_subcategories', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'application_method', 'product_application_methods', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'contractor_1', 'contractors', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'contractor_2', 'contractors', NULL, NULL, NULL, NULL, NULL, 'nullify'),
  ('contractor_costing', 'production_status', 'production_statuses', NULL, NULL, NULL, NULL, NULL, 'nullify');

DELETE FROM directus_fields
WHERE collection = 'contractor_costing';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, note, conditions,
  required, "group", validation, validation_message, searchable
) VALUES
  ('contractor_costing', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'order_link', NULL, 'symbolika-order-link', NULL, NULL, NULL, true, false, 1, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0435\0440\0435\0439\0442\0438 \0432 \0437\0430\043a\0430\0437'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'order_number', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041d\043e\043c\0435\0440 \0437\0430\043a\0430\0437\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'order', 'm2o', 'select-dropdown-m2o', NULL, NULL, NULL, true, true, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\043a\0430\0437'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'date', NULL, 'datetime', NULL, NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\0430\0442\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'order_deadline', NULL, 'datetime', NULL, NULL, NULL, true, true, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0440\043e\043a \0437\0430\043a\0430\0437\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\0438\0435\043d\0442'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043c\043f\0430\043d\0438\044f'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0435\043d\0435\0434\0436\0435\0440'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'product_name', NULL, 'input', NULL, NULL, NULL, true, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0437\0438\0446\0438\044f'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'quantity', NULL, 'input', NULL, NULL, NULL, true, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043e\043b\0438\0447\0435\0441\0442\0432\043e'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'price_per_unit', NULL, 'input', NULL, NULL, NULL, true, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0426\0435\043d\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'order_sum', NULL, 'input', NULL, NULL, NULL, true, false, 12, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0443\043c\043c\0430 \043f\043e\0437\0438\0446\0438\0438'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'deadline', NULL, 'datetime', NULL, NULL, NULL, true, true, 13, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0440\043e\043a \043f\043e\0437\0438\0446\0438\0438'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'product_category', 'm2o', 'select-dropdown-m2o', NULL, NULL, NULL, true, true, 14, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\0430\0442\0435\0433\043e\0440\0438\044f'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'product_subcategory', 'm2o', 'select-dropdown-m2o', NULL, NULL, NULL, true, true, 15, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0434\043a\0430\0442\0435\0433\043e\0440\0438\044f'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'application_method', 'm2o', 'select-dropdown-m2o', NULL, NULL, NULL, true, true, 16, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\0438\0434 \043d\0430\043d\0435\0441\0435\043d\0438\044f'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'blank_source', NULL, 'select-dropdown', '{"choices":[{"text":"Не требуется","value":"none"},{"text":"Закупить у поставщика","value":"supplier"},{"text":"Заготовка заказчика","value":"customer"},{"text":"Со склада","value":"warehouse"},{"text":"Подрядчик под ключ","value":"contractor"}]}'::json, 'labels', '{"choices":[{"text":"Не требуется","value":"none","foreground":"#C9D1D9","background":"#30363D"},{"text":"Закупить у поставщика","value":"supplier","foreground":"#FFD7A8","background":"#4A3423"},{"text":"Заготовка заказчика","value":"customer","foreground":"#B7F7D2","background":"#173C2B"},{"text":"Со склада","value":"warehouse","foreground":"#BFDBFE","background":"#1E3A5F"},{"text":"Подрядчик под ключ","value":"contractor","foreground":"#FFE0B2","background":"#5A3218"}]}'::json, false, false, 17, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'blank_ordered', 'cast-boolean', 'boolean', NULL, 'boolean', NULL, false, false, 18, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0417\0430\0433\043e\0442\043e\0432\043a\0430 \0437\0430\043a\0430\0437\0430\043d\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'contractor_1', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 19, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0434\0440\044f\0434\0447\0438\043a 1'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'contractor_1_cost', NULL, 'input', NULL, NULL, NULL, false, false, 20, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c 1'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'contractor_2', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 21, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\043e\0434\0440\044f\0434\0447\0438\043a 2'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'contractor_2_cost', NULL, 'input', NULL, NULL, NULL, false, false, 22, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c 2'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'unit_cost', NULL, 'input', NULL, NULL, NULL, true, false, 23, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c \0437\0430 \0435\0434.'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'total_cost', NULL, 'input', NULL, NULL, NULL, true, false, 24, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\044c \0432\0441\0435\0433\043e'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'profit_sum', NULL, 'input', NULL, NULL, NULL, true, false, 25, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041f\0440\0438\0431\044b\043b\044c'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'margin_percent', NULL, 'input', NULL, NULL, NULL, true, false, 26, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\041c\0430\0440\0436\0430, %'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'item_status', NULL, 'select-dropdown', NULL, NULL, NULL, true, true, 27, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043f\043e\0437\0438\0446\0438\0438'))::json, NULL, NULL, false, NULL, NULL, NULL, true),
  ('contractor_costing', 'production_status', 'm2o', 'select-dropdown-m2o', NULL, NULL, NULL, true, true, 28, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0442\0430\0442\0443\0441 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\0430'))::json, NULL, NULL, false, NULL, NULL, NULL, true);

UPDATE directus_fields
SET sort = CASE field
    WHEN 'blank_source' THEN 1
    WHEN 'contractor_1' THEN 2
    WHEN 'contractor_1_cost' THEN 3
    WHEN 'blank_ordered' THEN 4
    WHEN 'contractor_2' THEN 5
    WHEN 'contractor_2_cost' THEN 6
    WHEN 'order_link' THEN 7
    WHEN 'order_number' THEN 8
    WHEN 'product_name' THEN 9
    WHEN 'quantity' THEN 10
    WHEN 'price_per_unit' THEN 11
    WHEN 'order_sum' THEN 12
    WHEN 'customer' THEN 13
    WHEN 'customer_company' THEN 14
    WHEN 'manager_employee' THEN 15
    WHEN 'date' THEN 16
    WHEN 'unit_cost' THEN 17
    WHEN 'total_cost' THEN 18
    WHEN 'profit_sum' THEN 19
    WHEN 'margin_percent' THEN 20
    ELSE sort
  END,
  width = CASE
    WHEN field IN ('blank_source', 'blank_ordered', 'contractor_1', 'contractor_1_cost', 'contractor_2', 'contractor_2_cost') THEN 'half'
    WHEN field = 'order_link' THEN 'half'
    ELSE width
  END
WHERE collection = 'contractor_costing';

DELETE FROM directus_permissions
WHERE collection = 'contractor_costing';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'contractor_costing', action_value, '{}'::json, NULL::json, NULL::json, fields_value, policy_id
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000205'::uuid, 'read', 'id,order_link,order_number,date,customer,customer_company,manager_employee,product_name,quantity,deadline,item_status,production_status,price_per_unit,order_sum,product_category,product_subcategory,application_method,blank_source,blank_ordered,contractor_1,contractor_1_cost,contractor_2,contractor_2_cost'),
    ('00000000-0000-4000-8000-000000000205'::uuid, 'update', 'blank_source,blank_ordered,contractor_1,contractor_2,contractor_1_cost,contractor_2_cost')
) AS managing_permissions(policy_id, action_value, fields_value)
UNION ALL
SELECT 'contractor_costing', action_value, '{}'::json, NULL::json, NULL::json, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES ('read'), ('update')) AS admin_actions(action_value)
WHERE p.admin_access = true;

DELETE FROM directus_presets
WHERE collection = 'contractor_costing'
  AND bookmark IS NULL;

INSERT INTO directus_presets (bookmark, "user", role, collection, search, layout, layout_query, layout_options, refresh_interval, filter, icon, color)
SELECT NULL::varchar, NULL::uuid, admin_roles.role, 'contractor_costing', NULL::varchar, 'tabular',
       '{"tabular":{"fields":["order_number","date","customer","manager_employee","product_name","quantity","order_sum","contractor_1","contractor_1_cost","contractor_2","contractor_2_cost","unit_cost","total_cost","profit_sum","margin_percent"],"page":1}}'::json,
       '{"tabular":{"spacing":"compact","widths":{"order_number":130,"date":120,"customer":170,"manager_employee":170,"product_name":240,"quantity":100,"order_sum":130,"contractor_1":200,"contractor_1_cost":150,"contractor_2":200,"contractor_2_cost":150,"unit_cost":130,"total_cost":130,"profit_sum":120,"margin_percent":110}}}'::json,
       NULL::integer, NULL::json, 'price_check', '#F97316'
FROM (
  SELECT id AS role FROM directus_roles WHERE name = 'Administrator'
  UNION
  SELECT role FROM directus_users WHERE email = 'dimon96af@yandex.ru'
) admin_roles
WHERE admin_roles.role IS NOT NULL
UNION ALL
SELECT NULL::varchar, NULL::uuid, directus_roles.id, 'contractor_costing', NULL::varchar, 'tabular',
       '{"tabular":{"fields":["order_number","date","customer","manager_employee","product_name","quantity","order_sum","contractor_1","contractor_1_cost","contractor_2","contractor_2_cost"],"page":1}}'::json,
       '{"tabular":{"spacing":"compact","widths":{"order_number":130,"date":120,"customer":170,"manager_employee":170,"product_name":260,"quantity":100,"order_sum":130,"contractor_1":220,"contractor_1_cost":150,"contractor_2":220,"contractor_2_cost":150}}}'::json,
       NULL::integer, NULL::json, 'price_check', '#F97316'
FROM directus_roles
WHERE name = U&'\0423\043f\0440\0430\0432\043b\044f\044e\0449\0438\0439';

ALTER TABLE customers
ADD COLUMN IF NOT EXISTS vk_page_url varchar(255);

DELETE FROM directus_fields
WHERE collection = 'customers'
  AND field = 'vk_page_url';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, note, conditions,
  required, "group", validation, validation_message, searchable
) VALUES (
  'customers',
  'vk_page_url',
  NULL,
  'input',
  '{"iconLeft":"link"}'::json,
  NULL,
  NULL,
  false,
  false,
  4,
  'half',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0421\0441\044b\043b\043a\0430 \043d\0430 \0441\0442\0440\0430\043d\0438\0446\0443 \0412\041a'))::json,
  U&'\0411\0443\0434\0435\0442 \0438\0441\043f\043e\043b\044c\0437\043e\0432\0430\0442\044c\0441\044f \0434\043b\044f \0431\0443\0434\0443\0449\0438\0445 \0443\0432\0435\0434\043e\043c\043b\0435\043d\0438\0439 \0412\041a.',
  NULL,
  false,
  NULL,
  NULL,
  NULL,
  true
);

UPDATE directus_permissions
SET fields = fields || ',vk_page_url'
WHERE collection = 'customers'
  AND action IN ('create', 'update')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND position('vk_page_url' in fields) = 0;

INSERT INTO directus_collections (
  collection, icon, hidden, singleton, sort, collapse, translations
) VALUES
  ('symbolika_clients_group', 'contacts', false, false, 3, 'open',
   json_build_array(json_build_object('language','ru-RU','translation', U&'\041a\043b\0438\0435\043d\0442\044b \0438 \043a\043e\043c\043f\0430\043d\0438\0438'))::json),
  ('symbolika_office_group', 'storefront', false, false, 4, 'open',
   json_build_array(json_build_object('language','ru-RU','translation', U&'\041e\0444\0438\0441'))::json)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse,
  translations = EXCLUDED.translations;

UPDATE directus_collections
SET hidden = true
WHERE collection IN (
  'order_payments',
  'payment_allocations',
  'customer_company_links',
  'orders_overview_items',
  'office_issue_items',
  'office_issue_archive_items',
  'my_orders_in_work_items',
  'my_orders_completed_items',
  'my_orders_unpaid_items',
  'my_orders_in_work_payments',
  'my_orders_completed_payments',
  'my_orders_unpaid_payments',
  'service_directory',
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
  'contractor_payments',
  'contractor_work',
  'finance_dashboard_metrics',
  'finance_dashboard_monthly',
  'finance_dashboard_series'
);

WITH menu(collection_name, icon_value, label_value, sort_value, group_value, collapse_value) AS (VALUES
  ('orders_overview', 'assignment', U&'\0412\0441\0435 \0437\0430\043a\0430\0437\044b \0028\0441\043e \0441\0440\043e\043a\0430\043c\0438\0029', 1, NULL::varchar, 'open'),
  ('orders_due_urgent', 'priority_high', U&'\0413\043e\0440\044f\0449\0438\0435 \0437\0430\043a\0430\0437\044b', 1, 'orders_overview', 'open'),
  ('orders_due_today', 'today', U&'\0421\0435\0433\043e\0434\043d\044f', 2, 'orders_overview', 'open'),
  ('orders_due_this_week', 'calendar_view_week', U&'\041d\0430 \044d\0442\043e\0439 \043d\0435\0434\0435\043b\0435', 3, 'orders_overview', 'open'),
  ('orders_due_next_week', 'next_week', U&'\041d\0430 \0441\043b\0435\0434\0443\044e\0449\0435\0439 \043d\0435\0434\0435\043b\0435', 4, 'orders_overview', 'open'),
  ('orders_due_this_month', 'calendar_month', U&'\0412 \044d\0442\043e\043c \043c\0435\0441\044f\0446\0435', 5, 'orders_overview', 'open'),
  ('orders_due_next_month', 'event_upcoming', U&'\0412 \0441\043b\0435\0434\0443\044e\0449\0435\043c \043c\0435\0441\044f\0446\0435', 6, 'orders_overview', 'open'),
  ('orders', 'work', U&'\041c\043e\0438 \0437\0430\043a\0430\0437\044b', 2, NULL::varchar, 'open'),
  ('my_orders_in_work', 'work_history', U&'\0417\0430\043a\0430\0437\044b \0432 \0440\0430\0431\043e\0442\0435', 1, 'orders', 'open'),
  ('orders_items', 'list_alt', U&'\041f\043e\0437\0438\0446\0438\0438 \0437\0430\043a\0430\0437\0430', 2, 'orders', 'open'),
  ('my_orders_completed', 'task_alt', U&'\0417\0430\0432\0435\0440\0448\0435\043d\043d\044b\0435 \0437\0430\043a\0430\0437\044b', 3, 'orders', 'open'),
  ('my_orders_unpaid', 'payments', U&'\041d\0435\043e\043f\043b\0430\0447\0435\043d\043d\044b\0435 \0437\0430\043a\0430\0437\044b', 4, 'orders', 'open'),
  ('customers', 'person', U&'\041a\043b\0438\0435\043d\0442\044b', 1, 'symbolika_clients_group', 'open'),
  ('customer_companies', 'business', U&'\041a\043e\043c\043f\0430\043d\0438\0438', 2, 'symbolika_clients_group', 'open'),
  ('customer_reconciliation', 'request_quote', U&'\0421\0432\0435\0440\043a\0430 \043f\043e \043a\043b\0438\0435\043d\0442\0430\043c', 3, 'symbolika_clients_group', 'open'),
  ('office_issue', 'storefront', U&'\0412\044b\0434\0430\0447\0430 \0432 \043e\0444\0438\0441\0435', 1, 'symbolika_office_group', 'open'),
  ('office_items_in_office', 'inventory', U&'\0417\0430\043a\0430\0437\044b \0432 \043e\0444\0438\0441\0435', 2, 'symbolika_office_group', 'open'),
  ('office_issue_archive', 'archive', U&'\0410\0440\0445\0438\0432 \0432\044b\0434\0430\0447\0438 \0432 \043e\0444\0438\0441\0435', 3, 'symbolika_office_group', 'open'),
  ('production_work', 'engineering', U&'\041f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e', 5, NULL::varchar, 'open'),
  ('screen_printing_work', 'format_paint', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', 6, NULL::varchar, 'open'),
  ('contractor_costing', 'price_check', U&'\0417\0430\043f\043e\043b\043d\0435\043d\0438\0435 \0441\0435\0431\0435\0441\0442\043e\0438\043c\043e\0441\0442\0438', 7, NULL::varchar, 'open')
)
UPDATE directus_collections dc
SET hidden = false,
    icon = menu.icon_value,
    sort = menu.sort_value,
    "group" = menu.group_value,
    collapse = menu.collapse_value,
    translations = json_build_array(json_build_object('language','ru-RU','translation', menu.label_value))::json
FROM menu
WHERE dc.collection = menu.collection_name;

-- Рабочие представления оставляем в базе и правах, но убираем из бокового меню:
-- основной интерфейс для них теперь модуль "Рабочий центр".
UPDATE directus_collections
SET hidden = true
WHERE collection IN (
  'orders_overview',
  'orders_due_urgent',
  'orders_due_today',
  'orders_due_this_week',
  'orders_due_next_week',
  'orders_due_this_month',
  'orders_due_next_month',
  'my_orders_in_work',
  'my_orders_completed',
  'my_orders_unpaid',
  'customer_reconciliation',
  'office_issue',
  'office_items_in_office',
  'office_issue_archive',
  'production_work',
  'screen_printing_work',
  'contractor_work',
  'contractor_costing',
  'order_estimates',
  'order_estimate_items'
);

CREATE SEQUENCE IF NOT EXISTS symbolika_estimate_number_seq START 1;

CREATE TABLE IF NOT EXISTS order_estimates (
  id serial PRIMARY KEY,
  status varchar(32) NOT NULL DEFAULT 'draft',
  estimate_number varchar(32) UNIQUE,
  date date DEFAULT CURRENT_DATE,
  deadline date,
  customer integer REFERENCES customers(id) ON DELETE SET NULL,
  customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  manager_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  shipping_method varchar(64),
  payment_on_receipt boolean DEFAULT false,
  payment_type integer REFERENCES payment_types(id) ON DELETE SET NULL,
  comment text,
  total_sum numeric(14,2) DEFAULT 0,
  converted_order integer REFERENCES orders(id) ON DELETE SET NULL,
  date_created timestamptz DEFAULT now(),
  date_updated timestamptz
);

ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS status varchar(32) NOT NULL DEFAULT 'draft';
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS estimate_number varchar(32) UNIQUE;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS date date DEFAULT CURRENT_DATE;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS deadline date;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS customer integer REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS manager_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS shipping_method varchar(64);
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS payment_on_receipt boolean DEFAULT false;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS payment_type integer REFERENCES payment_types(id) ON DELETE SET NULL;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS comment text;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS total_sum numeric(14,2) DEFAULT 0;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS converted_order integer REFERENCES orders(id) ON DELETE SET NULL;
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS date_created timestamptz DEFAULT now();
ALTER TABLE order_estimates ADD COLUMN IF NOT EXISTS date_updated timestamptz;

CREATE TABLE IF NOT EXISTS order_estimate_items (
  id serial PRIMARY KEY,
  estimate integer REFERENCES order_estimates(id) ON DELETE CASCADE,
  sort integer DEFAULT 1,
  product_name varchar(255) NOT NULL,
  quantity numeric(14,2) DEFAULT 0,
  price_per_unit numeric(14,2) DEFAULT 0,
  line_sum numeric(14,2) DEFAULT 0,
  deadline date,
  product_category integer REFERENCES product_categories(id) ON DELETE SET NULL,
  product_subcategory integer REFERENCES product_subcategories(id) ON DELETE SET NULL,
  application_method integer REFERENCES product_application_methods(id) ON DELETE SET NULL,
  blank_source varchar(32) DEFAULT 'none',
  contractor_1 integer REFERENCES contractors(id) ON DELETE SET NULL,
  contractor_1_cost numeric(14,2) DEFAULT 0,
  technical_task_text text,
  url text,
  date_created timestamptz DEFAULT now(),
  date_updated timestamptz
);

ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS estimate integer REFERENCES order_estimates(id) ON DELETE CASCADE;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS sort integer DEFAULT 1;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS product_name varchar(255) NOT NULL DEFAULT '';
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS quantity numeric(14,2) DEFAULT 0;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS price_per_unit numeric(14,2) DEFAULT 0;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS line_sum numeric(14,2) DEFAULT 0;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS deadline date;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS product_category integer REFERENCES product_categories(id) ON DELETE SET NULL;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS product_subcategory integer REFERENCES product_subcategories(id) ON DELETE SET NULL;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS application_method integer REFERENCES product_application_methods(id) ON DELETE SET NULL;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS blank_source varchar(32) DEFAULT 'none';
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS contractor_1 integer REFERENCES contractors(id) ON DELETE SET NULL;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS contractor_1_cost numeric(14,2) DEFAULT 0;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS technical_task_text text;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS url text;
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS date_created timestamptz DEFAULT now();
ALTER TABLE order_estimate_items ADD COLUMN IF NOT EXISTS date_updated timestamptz;

CREATE OR REPLACE FUNCTION symbolika_set_estimate_number()
RETURNS trigger AS $$
BEGIN
  IF NEW.estimate_number IS NULL OR NEW.estimate_number = '' THEN
    NEW.estimate_number := 'R-' || lpad(nextval('symbolika_estimate_number_seq')::text, 5, '0');
  END IF;
  NEW.date_updated := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_estimates_set_number ON order_estimates;
CREATE TRIGGER order_estimates_set_number
BEFORE INSERT OR UPDATE ON order_estimates
FOR EACH ROW EXECUTE FUNCTION symbolika_set_estimate_number();

CREATE OR REPLACE FUNCTION symbolika_estimate_item_before_save()
RETURNS trigger AS $$
BEGIN
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.price_per_unit := COALESCE(NEW.price_per_unit, 0);
  NEW.line_sum := COALESCE(NEW.quantity, 0) * COALESCE(NEW.price_per_unit, 0);
  NEW.date_updated := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION symbolika_recalc_estimate_total(estimate_id integer)
RETURNS void AS $$
BEGIN
  IF estimate_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE order_estimates
  SET total_sum = COALESCE((
        SELECT SUM(COALESCE(line_sum, 0))
        FROM order_estimate_items
        WHERE estimate = estimate_id
      ), 0),
      date_updated = now()
  WHERE id = estimate_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION symbolika_estimate_item_after_save()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM symbolika_recalc_estimate_total(OLD.estimate);
    RETURN OLD;
  END IF;

  PERFORM symbolika_recalc_estimate_total(NEW.estimate);
  IF TG_OP = 'UPDATE' AND OLD.estimate IS DISTINCT FROM NEW.estimate THEN
    PERFORM symbolika_recalc_estimate_total(OLD.estimate);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_estimate_items_before_save ON order_estimate_items;
CREATE TRIGGER order_estimate_items_before_save
BEFORE INSERT OR UPDATE ON order_estimate_items
FOR EACH ROW EXECUTE FUNCTION symbolika_estimate_item_before_save();

DROP TRIGGER IF EXISTS order_estimate_items_after_save ON order_estimate_items;
CREATE TRIGGER order_estimate_items_after_save
AFTER INSERT OR UPDATE OR DELETE ON order_estimate_items
FOR EACH ROW EXECUTE FUNCTION symbolika_estimate_item_after_save();

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, translations
) VALUES
  ('order_estimates', 'request_quote', 'Saved order estimates used by the custom work center.', '{{estimate_number}}', true, false,
   json_build_array(json_build_object('language','ru-RU','translation','Расчеты'))::json),
  ('order_estimate_items', 'format_list_bulleted', 'Line items for saved order estimates.', '{{product_name}}', true, false,
   json_build_array(json_build_object('language','ru-RU','translation','Позиции расчетов'))::json)
ON CONFLICT (collection) DO UPDATE
SET hidden = EXCLUDED.hidden,
    icon = EXCLUDED.icon,
    note = EXCLUDED.note,
    display_template = EXCLUDED.display_template,
    translations = EXCLUDED.translations;

DELETE FROM directus_fields
WHERE collection IN ('order_estimates', 'order_estimate_items');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('order_estimates', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('order_estimates', 'estimate_number', NULL, 'input', NULL, NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Номер расчета'))::json, false, true),
  ('order_estimates', 'status', NULL, 'select-dropdown', '{"choices":[{"text":"Черновик","value":"draft"},{"text":"Заказ создан","value":"converted"},{"text":"Отменен","value":"cancelled"}]}'::json, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Статус'))::json, false, true),
  ('order_estimates', 'date', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Дата'))::json, false, true),
  ('order_estimates', 'deadline', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Срок'))::json, false, true),
  ('order_estimates', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Клиент'))::json, false, true),
  ('order_estimates', 'customer_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Компания'))::json, false, true),
  ('order_estimates', 'manager_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation','Менеджер'))::json, false, true),
  ('order_estimates', 'total_sum', NULL, 'input', NULL, NULL, NULL, true, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сумма'))::json, false, true),
  ('order_estimates', 'comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 10, 'full', json_build_array(json_build_object('language','ru-RU','translation','Комментарий'))::json, false, true),
  ('order_estimate_items', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('order_estimate_items', 'estimate', 'm2o', 'select-dropdown-m2o', '{"template":"{{estimate_number}}"}'::json, 'related-values', '{"template":"{{estimate_number}}"}'::json, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Расчет'))::json, true, true),
  ('order_estimate_items', 'product_name', NULL, 'input', NULL, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Позиция'))::json, true, true),
  ('order_estimate_items', 'quantity', NULL, 'input', NULL, NULL, NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Количество'))::json, false, true),
  ('order_estimate_items', 'price_per_unit', NULL, 'input', NULL, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Цена'))::json, false, true),
  ('order_estimate_items', 'line_sum', NULL, 'input', NULL, NULL, NULL, true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сумма'))::json, false, true),
  ('order_estimate_items', 'deadline', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Срок'))::json, false, true),
  ('order_estimate_items', 'technical_task_text', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 8, 'full', json_build_array(json_build_object('language','ru-RU','translation','ТЗ'))::json, false, true),
  ('order_estimate_items', 'url', NULL, 'input', NULL, NULL, NULL, false, false, 9, 'full', json_build_array(json_build_object('language','ru-RU','translation','Макет'))::json, false, true);

DELETE FROM directus_relations
WHERE (many_collection = 'order_estimates' AND many_field IN ('customer','customer_company','manager_employee','payment_type','converted_order'))
   OR (many_collection = 'order_estimate_items' AND many_field IN ('estimate','product_category','product_subcategory','application_method','contractor_1'));

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES
  ('order_estimates', 'customer', 'customers', NULL, 'nullify'),
  ('order_estimates', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('order_estimates', 'manager_employee', 'employees', NULL, 'nullify'),
  ('order_estimates', 'payment_type', 'payment_types', NULL, 'nullify'),
  ('order_estimates', 'converted_order', 'orders', NULL, 'nullify'),
  ('order_estimate_items', 'estimate', 'order_estimates', 'items', 'delete'),
  ('order_estimate_items', 'product_category', 'product_categories', NULL, 'nullify'),
  ('order_estimate_items', 'product_subcategory', 'product_subcategories', NULL, 'nullify'),
  ('order_estimate_items', 'application_method', 'product_application_methods', NULL, 'nullify'),
  ('order_estimate_items', 'contractor_1', 'contractors', NULL, 'nullify');

DELETE FROM directus_permissions
WHERE collection IN ('order_estimates', 'order_estimate_items');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES ('order_estimates'), ('order_estimate_items')) AS collections(collection_name)
CROSS JOIN (VALUES ('create'), ('read'), ('update'), ('delete')) AS actions(action_name)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'order_estimates', action_name, permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value)
CROSS JOIN (VALUES ('read'), ('update'), ('delete')) AS actions(action_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'order_estimates', 'create', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'order_estimate_items', action_name, permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"estimate":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000202', '{"estimate":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value)
CROSS JOIN (VALUES ('read'), ('update'), ('delete')) AS actions(action_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'order_estimate_items', 'create', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id);

UPDATE directus_presets
SET layout_query = jsonb_set(
      layout_query::jsonb,
      '{tabular,fields}',
      '["name","phone","email","vk_page_url","company","manager"]'::jsonb,
      true
    )::json
WHERE collection = 'customers'
  AND layout = 'tabular'
  AND layout_query::jsonb ? 'tabular';

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES
  ('symbolika_tasks', 'checklist', 'Internal task tracker for employees.', '{{title}}', true, false, 930, 'all', '#F97316',
   json_build_array(json_build_object('language','ru-RU','translation','Задачи'))::json),
  ('symbolika_task_comments', 'chat_bubble', 'Task comments.', '{{comment}}', true, false, 931, 'all', '#F97316',
   json_build_array(json_build_object('language','ru-RU','translation','Комментарии задач'))::json),
  ('symbolika_task_checklist', 'checklist', 'Task checklist items.', '{{title}}', true, false, 932, 'all', '#F97316',
   json_build_array(json_build_object('language','ru-RU','translation','Чек-листы задач'))::json),
  ('symbolika_task_attachments', 'attachment', 'Task attachments.', '{{title}}', true, false, 933, 'all', '#F97316',
   json_build_array(json_build_object('language','ru-RU','translation','Вложения задач'))::json)
ON CONFLICT (collection) DO UPDATE
SET icon = EXCLUDED.icon,
    note = EXCLUDED.note,
    display_template = EXCLUDED.display_template,
    hidden = EXCLUDED.hidden,
    singleton = EXCLUDED.singleton,
    sort = EXCLUDED.sort,
    accountability = EXCLUDED.accountability,
    color = EXCLUDED.color,
    translations = EXCLUDED.translations;

DELETE FROM directus_fields
WHERE collection IN ('symbolika_tasks', 'symbolika_task_comments', 'symbolika_task_checklist', 'symbolika_task_attachments');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('symbolika_tasks', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('symbolika_tasks', 'title', NULL, 'input', NULL, NULL, NULL, false, false, 2, 'full', json_build_array(json_build_object('language','ru-RU','translation','Название'))::json, true, true),
  ('symbolika_tasks', 'description', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 3, 'full', json_build_array(json_build_object('language','ru-RU','translation','Описание'))::json, false, true),
  ('symbolika_tasks', 'status', NULL, 'select-dropdown', '{"choices":[{"text":"Новая","value":"new"},{"text":"В работе","value":"in_work"},{"text":"Ожидает","value":"waiting"},{"text":"Готово","value":"done"},{"text":"Отменена","value":"cancelled"}]}'::json, 'labels', '{"choices":[{"text":"Новая","value":"new","foreground":"#BFDBFE","background":"#1E3A8A"},{"text":"В работе","value":"in_work","foreground":"#FED7AA","background":"#7C2D12"},{"text":"Ожидает","value":"waiting","foreground":"#FDE68A","background":"#713F12"},{"text":"Готово","value":"done","foreground":"#BBF7D0","background":"#14532D"},{"text":"Отменена","value":"cancelled","foreground":"#D1D5DB","background":"#374151"}]}'::json, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Статус'))::json, true, true),
  ('symbolika_tasks', 'priority', NULL, 'select-dropdown', '{"choices":[{"text":"Низкий","value":"low"},{"text":"Обычный","value":"normal"},{"text":"Важный","value":"high"},{"text":"Срочно","value":"urgent"}]}'::json, 'labels', '{"choices":[{"text":"Низкий","value":"low","foreground":"#D1D5DB","background":"#374151"},{"text":"Обычный","value":"normal","foreground":"#BFDBFE","background":"#1E3A8A"},{"text":"Важный","value":"high","foreground":"#FED7AA","background":"#7C2D12"},{"text":"Срочно","value":"urgent","foreground":"#FDA4AF","background":"#881337"}]}'::json, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Приоритет'))::json, true, true),
  ('symbolika_tasks', 'due_date', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Срок'))::json, false, true),
  ('symbolika_tasks', 'completed_at', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Дата завершения'))::json, false, true),
  ('symbolika_tasks', 'assigned_to', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation','Исполнитель'))::json, false, true),
  ('symbolika_tasks', 'created_by_employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation','Автор'))::json, false, true),
  ('symbolika_tasks', 'related_order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', '{"template":"{{order_number}}"}'::json, false, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation','Заказ'))::json, false, true),
  ('symbolika_tasks', 'related_order_item', 'm2o', 'select-dropdown-m2o', '{"template":"{{product_name}}"}'::json, 'related-values', '{"template":"{{product_name}}"}'::json, false, false, 11, 'half', json_build_array(json_build_object('language','ru-RU','translation','Позиция'))::json, false, true),
  ('symbolika_tasks', 'related_customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 12, 'half', json_build_array(json_build_object('language','ru-RU','translation','Клиент'))::json, false, true),
  ('symbolika_tasks', 'related_company', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', '{"template":"{{name}}"}'::json, false, false, 13, 'half', json_build_array(json_build_object('language','ru-RU','translation','Компания'))::json, false, true),
  ('symbolika_tasks', 'date_created', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, true, true, 14, 'half', json_build_array(json_build_object('language','ru-RU','translation','Создано'))::json, false, true),
  ('symbolika_tasks', 'date_updated', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, true, true, 15, 'half', json_build_array(json_build_object('language','ru-RU','translation','Обновлено'))::json, false, true),
  ('symbolika_task_comments', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('symbolika_task_comments', 'task', 'm2o', 'select-dropdown-m2o', '{"template":"{{title}}"}'::json, 'related-values', '{"template":"{{title}}"}'::json, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Задача'))::json, true, true),
  ('symbolika_task_comments', 'employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сотрудник'))::json, false, true),
  ('symbolika_task_comments', 'comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 4, 'full', json_build_array(json_build_object('language','ru-RU','translation','Комментарий'))::json, true, true),
  ('symbolika_task_checklist', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('symbolika_task_checklist', 'task', 'm2o', 'select-dropdown-m2o', '{"template":"{{title}}"}'::json, 'related-values', '{"template":"{{title}}"}'::json, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Задача'))::json, true, true),
  ('symbolika_task_checklist', 'title', NULL, 'input', NULL, NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Пункт'))::json, true, true),
  ('symbolika_task_checklist', 'is_done', 'cast-boolean', 'boolean', NULL, 'boolean', NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Готово'))::json, false, true),
  ('symbolika_task_attachments', 'id', NULL, 'numeric', NULL, NULL, NULL, true, true, 1, 'full', NULL, false, true),
  ('symbolika_task_attachments', 'task', 'm2o', 'select-dropdown-m2o', '{"template":"{{title}}"}'::json, 'related-values', '{"template":"{{title}}"}'::json, false, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Задача'))::json, true, true),
  ('symbolika_task_attachments', 'file', 'file', 'file', NULL, 'file', NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Файл'))::json, true, true),
  ('symbolika_task_attachments', 'employee', 'm2o', 'select-dropdown-m2o', '{"template":"{{full_name}}"}'::json, 'related-values', '{"template":"{{full_name}}"}'::json, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сотрудник'))::json, false, true),
  ('symbolika_task_attachments', 'title', NULL, 'input', NULL, NULL, NULL, false, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Название'))::json, false, true),
  ('symbolika_task_attachments', 'date_created', NULL, 'datetime', '{"includeSeconds":false}'::json, NULL, NULL, true, true, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Добавлено'))::json, false, true);

DELETE FROM directus_relations
WHERE many_collection IN ('symbolika_tasks', 'symbolika_task_comments', 'symbolika_task_checklist', 'symbolika_task_attachments');

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES
  ('symbolika_tasks', 'assigned_to', 'employees', NULL, 'nullify'),
  ('symbolika_tasks', 'created_by_employee', 'employees', NULL, 'nullify'),
  ('symbolika_tasks', 'related_order', 'orders', NULL, 'nullify'),
  ('symbolika_tasks', 'related_order_item', 'orders_items', NULL, 'nullify'),
  ('symbolika_tasks', 'related_customer', 'customers', NULL, 'nullify'),
  ('symbolika_tasks', 'related_company', 'customer_companies', NULL, 'nullify'),
  ('symbolika_task_comments', 'task', 'symbolika_tasks', 'comments', 'delete'),
  ('symbolika_task_comments', 'employee', 'employees', NULL, 'nullify'),
  ('symbolika_task_checklist', 'task', 'symbolika_tasks', 'checklist', 'delete'),
  ('symbolika_task_attachments', 'task', 'symbolika_tasks', 'attachments', 'delete'),
  ('symbolika_task_attachments', 'file', 'directus_files', NULL, 'delete'),
  ('symbolika_task_attachments', 'employee', 'employees', NULL, 'nullify');

DELETE FROM directus_permissions
WHERE collection IN ('symbolika_tasks', 'symbolika_task_comments', 'symbolika_task_checklist', 'symbolika_task_attachments');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES ('symbolika_tasks'), ('symbolika_task_comments'), ('symbolika_task_checklist'), ('symbolika_task_attachments')) AS collections(collection_name)
CROSS JOIN (VALUES ('create'), ('read'), ('update'), ('delete')) AS actions(action_name)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'symbolika_tasks', action_name, permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}'),
    ('00000000-0000-4000-8000-000000000202', '{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}'),
    ('00000000-0000-4000-8000-000000000203', '{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}'),
    ('00000000-0000-4000-8000-000000000204', '{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}'),
    ('00000000-0000-4000-8000-000000000206', '{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value)
CROSS JOIN (VALUES ('read'), ('update'), ('delete')) AS actions(action_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'symbolika_tasks', 'create', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000206'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, permissions_value::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201', '{"task":{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}}'),
    ('00000000-0000-4000-8000-000000000202', '{"task":{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}}'),
    ('00000000-0000-4000-8000-000000000203', '{"task":{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}}'),
    ('00000000-0000-4000-8000-000000000204', '{"task":{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}}'),
    ('00000000-0000-4000-8000-000000000206', '{"task":{"_or":[{"assigned_to":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"created_by_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}]}}'),
    ('00000000-0000-4000-8000-000000000205', '{}')
) AS policies(policy_id, permissions_value)
CROSS JOIN (VALUES ('symbolika_task_comments'), ('symbolika_task_checklist'), ('symbolika_task_attachments')) AS collections(collection_name)
CROSS JOIN (VALUES ('read'), ('update'), ('delete')) AS actions(action_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'create', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000206'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id)
CROSS JOIN (VALUES ('symbolika_task_comments'), ('symbolika_task_checklist'), ('symbolika_task_attachments')) AS collections(collection_name);

DELETE FROM directus_permissions
WHERE collection = 'directus_files'
  AND action IN ('create', 'read')
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000206'
  );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'directus_files', action_name, '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000205'),
    ('00000000-0000-4000-8000-000000000206')
) AS policies(policy_id)
CROSS JOIN (VALUES ('create'), ('read')) AS actions(action_name);

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES
  ('procurement_batches', 'shopping_cart_checkout', 'Supplier purchase batches assembled from procurement requests.', '{{batch_number}}', true, false, 932, 'all', '#F59E0B',
   json_build_array(json_build_object('language','ru-RU','translation','Заказы поставщикам'))::json),
  ('procurement_requests', 'local_shipping', 'Purchase and pickup requests for blanks and consumables.', '{{product_name}}', true, false, 933, 'all', '#F97316',
   json_build_array(json_build_object('language','ru-RU','translation','Заявки на закупку'))::json),
  ('inventory_items', 'inventory_2', 'Warehouse items and consumables by production section.', '{{name}}', true, false, 934, 'all', '#22C55E',
   json_build_array(json_build_object('language','ru-RU','translation','Склад'))::json),
  ('inventory_movements', 'swap_vert', 'Warehouse stock movements.', '{{inventory_item}}', true, false, 935, 'all', '#22C55E',
   json_build_array(json_build_object('language','ru-RU','translation','Движения склада'))::json)
ON CONFLICT (collection) DO UPDATE
SET icon = EXCLUDED.icon,
    note = EXCLUDED.note,
    display_template = EXCLUDED.display_template,
    hidden = EXCLUDED.hidden,
    singleton = EXCLUDED.singleton,
    sort = EXCLUDED.sort,
    accountability = EXCLUDED.accountability,
    color = EXCLUDED.color,
    translations = EXCLUDED.translations;

DELETE FROM directus_relations
WHERE many_collection IN ('procurement_batches', 'procurement_requests', 'inventory_items', 'inventory_movements');

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_field, one_deselect_action
) VALUES
  ('procurement_batches', 'supplier', 'contractors', NULL, 'nullify'),
  ('procurement_batches', 'responsible_employee', 'employees', NULL, 'nullify'),
  ('procurement_batches', 'task_order_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_batches', 'management_task_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_batches', 'task_payment_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_batches', 'task_pickup_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_requests', 'supplier', 'contractors', NULL, 'nullify'),
  ('procurement_requests', 'procurement_batch', 'procurement_batches', NULL, 'nullify'),
  ('procurement_requests', 'inventory_item', 'inventory_items', NULL, 'nullify'),
  ('procurement_requests', 'related_order', 'orders', NULL, 'nullify'),
  ('procurement_requests', 'order_item', 'orders_items', NULL, 'cascade'),
  ('procurement_requests', 'customer', 'customers', NULL, 'nullify'),
  ('procurement_requests', 'customer_company', 'customer_companies', NULL, 'nullify'),
  ('procurement_requests', 'manager_employee', 'employees', NULL, 'nullify'),
  ('procurement_requests', 'requested_by_employee', 'employees', NULL, 'nullify'),
  ('procurement_requests', 'responsible_employee', 'employees', NULL, 'nullify'),
  ('procurement_requests', 'task_order_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_requests', 'task_payment_id', 'symbolika_tasks', NULL, 'nullify'),
  ('procurement_requests', 'task_pickup_id', 'symbolika_tasks', NULL, 'nullify'),
  ('inventory_items', 'default_supplier', 'contractors', NULL, 'nullify'),
  ('inventory_movements', 'inventory_item', 'inventory_items', NULL, 'cascade'),
  ('inventory_movements', 'supplier', 'contractors', NULL, 'nullify'),
  ('inventory_movements', 'related_order', 'orders', NULL, 'nullify'),
  ('inventory_movements', 'related_order_item', 'orders_items', NULL, 'nullify')
ON CONFLICT DO NOTHING;

DELETE FROM directus_permissions
WHERE collection IN ('procurement_batches', 'procurement_requests', 'inventory_items', 'inventory_movements');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES ('procurement_batches'), ('procurement_requests'), ('inventory_items'), ('inventory_movements')) AS collections(collection_name)
CROSS JOIN (VALUES ('create'), ('read'), ('update'), ('delete')) AS actions(action_name)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000206'),
    ('00000000-0000-4000-8000-000000000205')
) AS policies(policy_id)
CROSS JOIN (VALUES ('procurement_requests'), ('inventory_items'), ('inventory_movements')) AS collections(collection_name)
CROSS JOIN (VALUES ('create'), ('read'), ('update')) AS actions(action_name);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'procurement_batches', 'read', '{}'::json, NULL, NULL, '*', policy_id::uuid
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000202'),
    ('00000000-0000-4000-8000-000000000203'),
    ('00000000-0000-4000-8000-000000000204'),
    ('00000000-0000-4000-8000-000000000205'),
    ('00000000-0000-4000-8000-000000000206')
) AS policies(policy_id);

-- Non-admin roles can submit and edit request details, but only an administrator
-- can move a procurement request through its workflow statuses.
UPDATE directus_permissions
SET fields = 'request_type,request_source,purchase_source_type,purchase_place,product_url,section,supplier,inventory_item,related_order,order_item,customer,customer_company,manager_employee,requested_by_employee,product_name,quantity,unit,estimated_cost,delivery_method,transport_company,supplier_city,pickup_address,pickup_deadline,responsible_employee,comment'
WHERE collection = 'procurement_requests'
  AND action IN ('create', 'update')
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000206'
  );

-- The managing director works with every purchase exactly like an administrator:
-- all requests are visible, workflow statuses are editable and grouped batches
-- can be moved through ordering, payment, pickup and receipt stages.
UPDATE directus_permissions
SET permissions = '{}'::json,
    fields = '*'
WHERE collection = 'procurement_requests'
  AND action IN ('create', 'read', 'update')
  AND policy = '00000000-0000-4000-8000-000000000205';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('procurement_requests', 'delete', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('procurement_batches', 'create', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('procurement_batches', 'update', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('procurement_batches', 'delete', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205');

-- Admins print labels from orders_items in the custom work center.
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'orders_items', 'read', '{}'::json, NULL::json, NULL::json, '*', p.id
FROM directus_policies p
WHERE p.admin_access = true
  AND NOT EXISTS (
    SELECT 1
    FROM directus_permissions dp
    WHERE dp.policy = p.id
      AND dp.collection = 'orders_items'
      AND dp.action = 'read'
  );

UPDATE directus_permissions
SET fields = '*',
    permissions = '{}'::json
WHERE collection = 'orders_items'
  AND action = 'read'
  AND policy IN (SELECT id FROM directus_policies WHERE admin_access = true);

-- Designer workflow: role, item flag, design tasks and restricted access.
INSERT INTO directus_roles (id, name, icon, description, parent)
VALUES ('00000000-0000-4000-8000-000000000308', 'Дизайнер', 'design_services', 'Подготовка макетов по позициям заказов', NULL)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, icon = EXCLUDED.icon, description = EXCLUDED.description;

INSERT INTO employee_positions (name, sort, is_active)
SELECT 'Дизайнер', 60, true
WHERE NOT EXISTS (
  SELECT 1 FROM employee_positions WHERE LOWER(BTRIM(name)) = LOWER('Дизайнер')
);

UPDATE employee_positions
SET is_active = true,
    sort = COALESCE(sort, 60)
WHERE LOWER(BTRIM(name)) = LOWER('Дизайнер');

INSERT INTO directus_policies (id, name, icon, description, ip_access, enforce_tfa, admin_access, app_access)
VALUES ('00000000-0000-4000-8000-000000000208', 'Дизайнер — задачи по макетам', 'design_services', 'Доступ к дизайнерским задачам и связанным позициям', NULL, false, false, true)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, icon = EXCLUDED.icon, description = EXCLUDED.description, admin_access = false, app_access = true;

INSERT INTO directus_access (id, role, "user", policy, sort)
SELECT gen_random_uuid(), '00000000-0000-4000-8000-000000000308'::uuid, NULL, '00000000-0000-4000-8000-000000000208'::uuid, 1
WHERE NOT EXISTS (SELECT 1 FROM directus_access WHERE role = '00000000-0000-4000-8000-000000000308'::uuid AND policy = '00000000-0000-4000-8000-000000000208'::uuid);

DELETE FROM directus_fields WHERE collection = 'orders_items' AND field IN ('needs_designer_help', 'designer_comment', 'designer_source_url');
INSERT INTO directus_fields (collection, field, special, interface, options, display, display_options, readonly, hidden, sort, width, translations, required, searchable)
VALUES
  ('orders_items', 'needs_designer_help', 'cast-boolean', 'boolean', NULL, 'boolean', NULL, false, false, 44, 'half', json_build_array(json_build_object('language','ru-RU','translation','Нужна помощь дизайнера'))::json, false, true),
  ('orders_items', 'designer_comment', NULL, 'input-multiline', NULL, NULL, NULL, false, false, 45, 'full', json_build_array(json_build_object('language','ru-RU','translation','Комментарий для дизайнера'))::json, false, true),
  ('orders_items', 'designer_source_url', NULL, 'input', '{"trim":true}'::json, 'formatted-value', NULL, false, false, 46, 'full', json_build_array(json_build_object('language','ru-RU','translation','Исходный файл / ссылка для дизайнера'))::json, false, true);

DELETE FROM directus_fields WHERE collection = 'symbolika_tasks' AND field IN ('task_type', 'source_url', 'result_url');
INSERT INTO directus_fields (collection, field, special, interface, options, display, display_options, readonly, hidden, sort, width, translations, required, searchable)
VALUES
  ('symbolika_tasks', 'task_type', NULL, 'select-dropdown', '{"choices":[{"text":"Обычная","value":"general"},{"text":"Закупка","value":"procurement"},{"text":"Макет / дизайн","value":"design"}]}'::json, 'labels', NULL, false, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Тип задачи'))::json, true, true),
  ('symbolika_tasks', 'source_url', NULL, 'input', '{"trim":true}'::json, 'formatted-value', NULL, false, false, 14, 'full', json_build_array(json_build_object('language','ru-RU','translation','Исходный файл / ссылка'))::json, false, true),
  ('symbolika_tasks', 'result_url', NULL, 'input', '{"trim":true}'::json, 'formatted-value', NULL, false, false, 15, 'full', json_build_array(json_build_object('language','ru-RU','translation','Ссылка на готовый макет'))::json, false, true);

UPDATE directus_fields
SET options = '{"choices":[{"text":"Новая","value":"new"},{"text":"В работе","value":"in_work"},{"text":"Нужны правки","value":"needs_revision"},{"text":"Ожидает","value":"waiting"},{"text":"Готово","value":"done"},{"text":"Отменена","value":"cancelled"}]}'::json
WHERE collection = 'symbolika_tasks' AND field = 'status';

DELETE FROM directus_permissions WHERE policy = '00000000-0000-4000-8000-000000000208'::uuid;

UPDATE directus_permissions
SET fields = fields || ',needs_designer_help'
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND policy IN ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND fields NOT LIKE '%needs_designer_help%';

UPDATE directus_permissions
SET fields = fields || ',designer_comment,designer_source_url'
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND policy IN ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND fields NOT LIKE '%designer_comment%';

UPDATE directus_permissions
SET fields = fields || ',layout_revision_url_snapshot'
WHERE collection = 'orders_items'
  AND action = 'read'
  AND policy IN ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND fields NOT LIKE '%layout_revision_url_snapshot%';

UPDATE directus_permissions
SET fields = fields || ',layout_disk_path,layout_disk_name,layout_disk_size,layout_disk_mime_type,layout_disk_uploaded_at'
WHERE collection = 'orders_items'
  AND action = 'read'
  AND policy IN ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND fields NOT LIKE '%layout_disk_name%';

UPDATE directus_permissions
SET fields = fields || ',layout_preview_url,layout_preview_disk_path,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at'
WHERE collection = 'orders_items'
  AND action = 'read'
  AND policy IN ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND fields NOT LIKE '%layout_preview_url%';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('symbolika_tasks', 'read', '{"task_type":{"_eq":"design"}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_tasks', 'update', '{"task_type":{"_eq":"design"}}'::json, '{"task_type":{"_eq":"design"}}'::json, NULL, 'status,completed_at,assigned_to,result_url,date_updated', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_comments', 'create', '{}'::json, NULL, NULL, 'task,employee,comment,date_created', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_comments', 'read', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_comments', 'update', '{"task":{"task_type":{"_eq":"design"}}}'::json, '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, 'comment', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_comments', 'delete', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_checklist', 'create', '{}'::json, NULL, NULL, 'task,title,is_done,sort,date_created,date_updated', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_checklist', 'read', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_checklist', 'update', '{"task":{"task_type":{"_eq":"design"}}}'::json, '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, 'title,is_done,sort,date_updated', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_checklist', 'delete', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_attachments', 'create', '{}'::json, NULL, NULL, 'task,file,employee,title,date_created', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_attachments', 'read', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_attachments', 'update', '{"task":{"task_type":{"_eq":"design"}}}'::json, '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, 'title', '00000000-0000-4000-8000-000000000208'),
  ('symbolika_task_attachments', 'delete', '{"task":{"task_type":{"_eq":"design"}}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('directus_files', 'create', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('directus_files', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('orders_items', 'read', '{"needs_designer_help":{"_eq":true}}'::json, NULL, NULL, 'id,order,product_name,quantity,deadline,technical_task_text,url,needs_designer_help,designer_comment,designer_source_url,layout_preview_url,layout_preview_disk_path,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at', '00000000-0000-4000-8000-000000000208'),
  ('orders_items', 'update', '{"needs_designer_help":{"_eq":true}}'::json, NULL, NULL, 'url', '00000000-0000-4000-8000-000000000208'),
  ('orders', 'read', '{}'::json, NULL, NULL, 'id,order_number,customer,customer_company,manager_employee,deadline', '00000000-0000-4000-8000-000000000208'),
  ('employees', 'read', '{}'::json, NULL, NULL, 'id,full_name,directus_user', '00000000-0000-4000-8000-000000000208'),
  ('customers', 'read', '{}'::json, NULL, NULL, 'id,name', '00000000-0000-4000-8000-000000000208'),
  ('customer_companies', 'read', '{}'::json, NULL, NULL, 'id,name', '00000000-0000-4000-8000-000000000208'),
  ('contractors', 'read', '{}'::json, NULL, NULL, 'id,name', '00000000-0000-4000-8000-000000000208'),
  ('procurement_requests', 'create', '{}'::json, NULL, NULL, 'request_type,request_source,purchase_source_type,purchase_place,product_url,section,supplier,requested_by_employee,product_name,quantity,unit,estimated_cost,delivery_method,transport_company,supplier_city,pickup_address,pickup_deadline,responsible_employee,comment', '00000000-0000-4000-8000-000000000208'),
  ('procurement_requests', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('procurement_requests', 'update', '{}'::json, NULL, NULL, 'request_type,request_source,purchase_source_type,purchase_place,product_url,section,supplier,requested_by_employee,product_name,quantity,unit,estimated_cost,delivery_method,transport_company,supplier_city,pickup_address,pickup_deadline,responsible_employee,comment', '00000000-0000-4000-8000-000000000208'),
  ('procurement_batches', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('directus_notifications', 'read', '{"recipient":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208'),
  ('directus_notifications', 'update', '{"recipient":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL, 'status', '00000000-0000-4000-8000-000000000208');

-- Unified event feed based on the native Directus audit trail. The table keeps
-- stable, role-filterable links while directus_revisions remains the source of truth.
CREATE TABLE IF NOT EXISTS symbolika_event_feed (
  event_id integer PRIMARY KEY,
  event_at timestamptz NOT NULL,
  action varchar(45) NOT NULL,
  source_collection varchar(64) NOT NULL,
  source_id integer NOT NULL,
  entity_type varchar(32) NOT NULL,
  entity_title text,
  order_id integer,
  order_number varchar(255),
  item_id integer,
  item_title text,
  task_id integer,
  task_title text,
  actor_user uuid,
  actor_name text,
  delta jsonb,
  before_delta jsonb,
  access_manager_user uuid,
  task_assigned_user uuid,
  task_created_user uuid,
  production_visible boolean NOT NULL DEFAULT false,
  screen_visible boolean NOT NULL DEFAULT false,
  office_visible boolean NOT NULL DEFAULT false,
  designer_visible boolean NOT NULL DEFAULT false
);

ALTER TABLE symbolika_event_feed
  ADD COLUMN IF NOT EXISTS before_delta jsonb;

CREATE INDEX IF NOT EXISTS symbolika_event_feed_event_at_idx ON symbolika_event_feed(event_at DESC);
CREATE INDEX IF NOT EXISTS symbolika_event_feed_order_idx ON symbolika_event_feed(order_id, event_at DESC);
CREATE INDEX IF NOT EXISTS symbolika_event_feed_item_idx ON symbolika_event_feed(item_id, event_at DESC);
CREATE INDEX IF NOT EXISTS symbolika_event_feed_task_idx ON symbolika_event_feed(task_id, event_at DESC);
CREATE INDEX IF NOT EXISTS symbolika_event_feed_manager_idx ON symbolika_event_feed(access_manager_user, event_at DESC);

CREATE OR REPLACE FUNCTION symbolika_capture_directus_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  activity_row directus_activity%ROWTYPE;
  resolved_source_id integer;
  resolved_order_id integer;
  resolved_item_id integer;
  resolved_task_id integer;
  resolved_order orders%ROWTYPE;
  resolved_item orders_items%ROWTYPE;
  resolved_task symbolika_tasks%ROWTYPE;
  resolved_actor text;
  manager_user_id uuid;
  assigned_user_id uuid;
  created_user_id uuid;
BEGIN
  IF NEW.collection NOT IN ('orders', 'orders_items', 'symbolika_tasks')
     OR NEW.item !~ '^[0-9]+$' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO activity_row FROM directus_activity WHERE id = NEW.activity;
  IF NOT FOUND THEN RETURN NEW; END IF;
  resolved_source_id := NEW.item::integer;

  IF NEW.collection = 'orders' THEN
    resolved_order_id := resolved_source_id;
  ELSIF NEW.collection = 'orders_items' THEN
    resolved_item_id := resolved_source_id;
    SELECT * INTO resolved_item FROM orders_items WHERE id = resolved_item_id;
    resolved_order_id := COALESCE(
      resolved_item."order",
      CASE WHEN COALESCE(NEW.data->>'order', '') ~ '^[0-9]+$' THEN (NEW.data->>'order')::integer END
    );
  ELSE
    resolved_task_id := resolved_source_id;
    SELECT * INTO resolved_task FROM symbolika_tasks WHERE id = resolved_task_id;
    resolved_order_id := COALESCE(
      resolved_task.related_order,
      CASE WHEN COALESCE(NEW.data->>'related_order', '') ~ '^[0-9]+$' THEN (NEW.data->>'related_order')::integer END
    );
    resolved_item_id := COALESCE(
      resolved_task.related_order_item,
      CASE WHEN COALESCE(NEW.data->>'related_order_item', '') ~ '^[0-9]+$' THEN (NEW.data->>'related_order_item')::integer END
    );
  END IF;

  IF resolved_item_id IS NOT NULL AND resolved_item.id IS NULL THEN
    SELECT * INTO resolved_item FROM orders_items WHERE id = resolved_item_id;
    resolved_order_id := COALESCE(resolved_order_id, resolved_item."order");
  END IF;
  IF resolved_order_id IS NOT NULL THEN
    SELECT * INTO resolved_order FROM orders WHERE id = resolved_order_id;
  END IF;
  IF resolved_task_id IS NOT NULL AND resolved_task.id IS NULL THEN
    SELECT * INTO resolved_task FROM symbolika_tasks WHERE id = resolved_task_id;
  END IF;

  SELECT e.directus_user INTO manager_user_id
  FROM employees e
  WHERE e.id = COALESCE(resolved_order.manager_employee, resolved_item.manager_employee);
  SELECT e.directus_user INTO assigned_user_id FROM employees e WHERE e.id = resolved_task.assigned_to;
  SELECT e.directus_user INTO created_user_id FROM employees e WHERE e.id = resolved_task.created_by_employee;
  SELECT COALESCE(NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''), u.email, 'Система')
    INTO resolved_actor
    FROM directus_users u
   WHERE u.id = activity_row."user";

  INSERT INTO symbolika_event_feed (
    event_id, event_at, action, source_collection, source_id, entity_type, entity_title,
    order_id, order_number, item_id, item_title, task_id, task_title,
    actor_user, actor_name, delta, access_manager_user, task_assigned_user, task_created_user,
    production_visible, screen_visible, office_visible, designer_visible
  ) VALUES (
    NEW.id, activity_row.timestamp, activity_row.action, NEW.collection, resolved_source_id,
    CASE NEW.collection WHEN 'orders' THEN 'order' WHEN 'orders_items' THEN 'item' ELSE 'task' END,
    CASE NEW.collection
      WHEN 'orders' THEN COALESCE('Заказ ' || resolved_order.order_number, 'Заказ #' || resolved_source_id)
      WHEN 'orders_items' THEN COALESCE(resolved_item.product_name, NEW.data->>'product_name', 'Позиция #' || resolved_source_id)
      ELSE COALESCE(resolved_task.title, NEW.data->>'title', 'Задача #' || resolved_source_id)
    END,
    resolved_order_id,
    COALESCE(resolved_order.order_number, NEW.data->>'order_number'),
    resolved_item_id,
    COALESCE(resolved_item.product_name, NEW.data->>'product_name'),
    resolved_task_id,
    COALESCE(resolved_task.title, NEW.data->>'title'),
    activity_row."user", COALESCE(resolved_actor, 'Система'),
    COALESCE(NEW.delta::jsonb, '{}'::jsonb) - ARRAY[
      'unit_cost', 'total_cost', 'profit_sum', 'margin_percent', 'manager_percent',
      'manager_commission_sum', 'tax_percent', 'tax_sum', 'contractor_2_cost'
    ],
    manager_user_id, assigned_user_id, created_user_id,
    EXISTS (SELECT 1 FROM production_work pw WHERE pw.id = resolved_item_id),
    EXISTS (SELECT 1 FROM screen_printing_work sw WHERE sw.id = resolved_item_id),
    COALESCE(resolved_order.shipping_method = 'office_pickup', false),
    COALESCE(resolved_item.needs_designer_help, false) OR COALESCE(resolved_task.task_type = 'design', false)
  )
  ON CONFLICT (event_id) DO UPDATE SET
    event_at = EXCLUDED.event_at,
    action = EXCLUDED.action,
    entity_title = EXCLUDED.entity_title,
    order_id = EXCLUDED.order_id,
    order_number = EXCLUDED.order_number,
    item_id = EXCLUDED.item_id,
    item_title = EXCLUDED.item_title,
    task_id = EXCLUDED.task_id,
    task_title = EXCLUDED.task_title,
    actor_user = EXCLUDED.actor_user,
    actor_name = EXCLUDED.actor_name,
    delta = EXCLUDED.delta,
    access_manager_user = EXCLUDED.access_manager_user,
    task_assigned_user = EXCLUDED.task_assigned_user,
    task_created_user = EXCLUDED.task_created_user,
    production_visible = EXCLUDED.production_visible,
    screen_visible = EXCLUDED.screen_visible,
    office_visible = EXCLUDED.office_visible,
    designer_visible = EXCLUDED.designer_visible;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_capture_directus_event ON directus_revisions;
CREATE TRIGGER symbolika_capture_directus_event
AFTER INSERT OR UPDATE ON directus_revisions
FOR EACH ROW EXECUTE FUNCTION symbolika_capture_directus_event();

CREATE OR REPLACE FUNCTION symbolika_refresh_order_event_access()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE manager_user_id uuid;
BEGIN
  SELECT directus_user INTO manager_user_id FROM employees WHERE id = NEW.manager_employee;
  UPDATE symbolika_event_feed
     SET access_manager_user = manager_user_id,
         office_visible = COALESCE(NEW.shipping_method = 'office_pickup', false),
         order_number = NEW.order_number
   WHERE order_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_refresh_order_event_access ON orders;
CREATE TRIGGER symbolika_refresh_order_event_access
AFTER INSERT OR UPDATE OF manager_employee, shipping_method, order_number ON orders
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_order_event_access();

CREATE OR REPLACE FUNCTION symbolika_refresh_item_event_access()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE manager_user_id uuid;
BEGIN
  SELECT e.directus_user INTO manager_user_id
    FROM orders o LEFT JOIN employees e ON e.id = COALESCE(o.manager_employee, NEW.manager_employee)
   WHERE o.id = NEW."order";
  UPDATE symbolika_event_feed
     SET order_id = NEW."order",
         item_title = NEW.product_name,
         access_manager_user = manager_user_id,
         production_visible = EXISTS (SELECT 1 FROM production_work pw WHERE pw.id = NEW.id),
         screen_visible = EXISTS (SELECT 1 FROM screen_printing_work sw WHERE sw.id = NEW.id),
         designer_visible = COALESCE(NEW.needs_designer_help, false)
   WHERE item_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_refresh_item_event_access ON orders_items;
DROP TRIGGER IF EXISTS zz_symbolika_refresh_item_event_access ON orders_items;
CREATE TRIGGER zz_symbolika_refresh_item_event_access
AFTER INSERT OR UPDATE OF "order", manager_employee, product_name, needs_designer_help ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_item_event_access();

CREATE OR REPLACE FUNCTION symbolika_refresh_task_event_access()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  resolved_order_id integer;
  manager_user_id uuid;
  assigned_user_id uuid;
  created_user_id uuid;
BEGIN
  SELECT oi."order" INTO resolved_order_id FROM orders_items oi WHERE oi.id = NEW.related_order_item;
  resolved_order_id := COALESCE(NEW.related_order, resolved_order_id);
  SELECT e.directus_user INTO manager_user_id FROM orders o LEFT JOIN employees e ON e.id = o.manager_employee WHERE o.id = resolved_order_id;
  SELECT directus_user INTO assigned_user_id FROM employees WHERE id = NEW.assigned_to;
  SELECT directus_user INTO created_user_id FROM employees WHERE id = NEW.created_by_employee;
  UPDATE symbolika_event_feed
     SET order_id = resolved_order_id,
         item_id = NEW.related_order_item,
         task_title = NEW.title,
         access_manager_user = manager_user_id,
         task_assigned_user = assigned_user_id,
         task_created_user = created_user_id,
         designer_visible = COALESCE(NEW.task_type = 'design', false)
   WHERE task_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_refresh_task_event_access ON symbolika_tasks;
CREATE TRIGGER symbolika_refresh_task_event_access
AFTER INSERT OR UPDATE OF assigned_to, created_by_employee, related_order, related_order_item, title, task_type ON symbolika_tasks
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_task_event_access();

-- Backfill the existing history through the same trigger without changing its data.
UPDATE directus_revisions
SET item = item
WHERE collection IN ('orders', 'orders_items', 'symbolika_tasks');

-- Older Directus revisions only store the new delta. Reconstruct the value that
-- was active immediately before every update so historical events can also be
-- rolled back. Future events are enriched with exact values by the calculations hook.
UPDATE symbolika_event_feed event_row
SET before_delta = (
  SELECT jsonb_object_agg(
    changed.field_key,
    COALESCE((
      SELECT CASE
        WHEN COALESCE(previous_revision.delta::jsonb, '{}'::jsonb) ? changed.field_key
          THEN previous_revision.delta::jsonb -> changed.field_key
        ELSE previous_revision.data::jsonb -> changed.field_key
      END
      FROM directus_revisions previous_revision
      JOIN directus_activity previous_activity ON previous_activity.id = previous_revision.activity
      WHERE previous_revision.id < event_row.event_id
        AND previous_activity.collection = event_row.source_collection
        AND previous_activity.item = event_row.source_id::text
        AND (
          COALESCE(previous_revision.delta::jsonb, '{}'::jsonb) ? changed.field_key
          OR COALESCE(previous_revision.data::jsonb, '{}'::jsonb) ? changed.field_key
        )
      ORDER BY previous_revision.id DESC
      LIMIT 1
    ), 'null'::jsonb)
  ) AS before_delta
  FROM jsonb_object_keys(COALESCE(event_row.delta, '{}'::jsonb)) AS changed(field_key)
)
WHERE event_row.action = 'update'
  AND event_row.before_delta IS NULL
  AND event_row.delta IS NOT NULL
  AND event_row.delta <> '{}'::jsonb;

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES (
  'symbolika_event_feed', 'history', 'Unified history for orders, order items and tasks.', '{{entity_title}}', true, false, 936, 'all', '#F97316',
  json_build_array(json_build_object('language','ru-RU','translation','Лента событий'))::json
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  accountability = EXCLUDED.accountability,
  color = EXCLUDED.color,
  translations = EXCLUDED.translations;

DELETE FROM directus_permissions WHERE collection = 'symbolika_event_feed';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'symbolika_event_feed', 'read', '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('symbolika_event_feed', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('symbolika_event_feed', 'read', '{"_or":[{"access_manager_user":{"_eq":"$CURRENT_USER"}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}},{"actor_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('symbolika_event_feed', 'read', '{"_or":[{"office_visible":{"_eq":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202'),
  ('symbolika_event_feed', 'read', '{"_or":[{"office_visible":{"_eq":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000203'),
  ('symbolika_event_feed', 'read', '{"_or":[{"production_visible":{"_eq":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000204'),
  ('symbolika_event_feed', 'read', '{"_or":[{"screen_visible":{"_eq":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000206'),
  ('symbolika_event_feed', 'read', '{"_or":[{"designer_visible":{"_eq":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208');

-- Pilot feedback captured from every working module.
CREATE TABLE IF NOT EXISTS symbolika_feedback_reports (
  id bigserial PRIMARY KEY,
  reported_at timestamptz NOT NULL DEFAULT now(),
  reported_by uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  page_url text NOT NULL,
  page_title text,
  module_section varchar(80),
  active_tab varchar(100),
  entity_type varchar(40),
  entity_id integer,
  order_number varchar(100),
  entity_title text,
  comment text NOT NULL,
  browser_info text,
  status varchar(30) NOT NULL DEFAULT 'new',
  resolved_at timestamptz,
  resolved_by uuid REFERENCES directus_users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS symbolika_feedback_reports_status_idx
  ON symbolika_feedback_reports(status, reported_at DESC);

-- Last known state of the background and trigger-based handlers.
CREATE TABLE IF NOT EXISTS symbolika_automation_runs (
  handler_key varchar(100) PRIMARY KEY,
  title text NOT NULL,
  status varchar(30) NOT NULL DEFAULT 'unknown',
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  last_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO symbolika_automation_runs (handler_key, title, status)
VALUES
  ('workflow_consistency', 'Сверка статусов и связей', 'unknown'),
  ('customer_notifications', 'Уведомления клиентам', 'unknown')
ON CONFLICT (handler_key) DO NOTHING;

-- Admin-only automation control: materialized issue list refreshed after relevant changes.
CREATE TABLE IF NOT EXISTS symbolika_automation_issues (
  id varchar(100) PRIMARY KEY,
  issue_type varchar(80) NOT NULL,
  severity varchar(20) NOT NULL DEFAULT 'warning',
  title text NOT NULL,
  detail text,
  actual_value text,
  expected_value text,
  order_id integer,
  order_number varchar(100),
  item_id integer,
  item_title text,
  procurement_request_id integer,
  procurement_batch_id integer,
  task_id integer,
  task_title text,
  detected_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS symbolika_automation_issues_type_idx
  ON symbolika_automation_issues(issue_type, severity);

CREATE OR REPLACE FUNCTION refresh_symbolika_automation_issues()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Serialize concurrent refreshes without taking an ACCESS EXCLUSIVE table lock.
  PERFORM pg_advisory_xact_lock(hashtext('symbolika_automation_issues_refresh'));
  INSERT INTO symbolika_automation_runs (handler_key, title, status, last_attempt_at, updated_at)
  VALUES ('workflow_consistency', 'Сверка статусов и связей', 'running', now(), now())
  ON CONFLICT (handler_key) DO UPDATE SET
    status = EXCLUDED.status,
    last_attempt_at = EXCLUDED.last_attempt_at,
    updated_at = EXCLUDED.updated_at;
  DELETE FROM symbolika_automation_issues;

  WITH item_rollup AS (
    SELECT
      o.id AS order_id,
      o.order_number,
      os.name AS actual_status,
      count(oi.id) AS item_count,
      string_agg(DISTINCT CASE symbolika_normalize_item_status(oi.item_status)
        WHEN 'new' THEN 'Новый'
        WHEN 'approval' THEN 'Согласование'
        WHEN 'layout_revision' THEN 'Доработка макета'
        WHEN 'sent_to_work' THEN 'Отправлен в работу'
        WHEN 'in_work' THEN 'В работе'
        WHEN 'ready' THEN 'Готов'
        WHEN 'delivered' THEN 'Доставлен'
        WHEN 'cancelled' THEN 'Отменен'
        ELSE COALESCE(oi.item_status, 'Без статуса')
      END, ', ') AS item_statuses,
      CASE
        WHEN bool_and(symbolika_normalize_item_status(oi.item_status) = 'cancelled') THEN 'Отменен'
        WHEN bool_and(symbolika_normalize_item_status(oi.item_status) IN ('delivered', 'cancelled')) AND bool_or(symbolika_normalize_item_status(oi.item_status) = 'delivered') THEN 'Доставлен'
        WHEN bool_and(symbolika_normalize_item_status(oi.item_status) IN ('ready', 'cancelled')) AND bool_or(symbolika_normalize_item_status(oi.item_status) = 'ready') THEN 'Готов'
        WHEN bool_or(symbolika_normalize_item_status(oi.item_status) = 'layout_revision') THEN 'Доработка макета'
        WHEN bool_or(symbolika_normalize_item_status(oi.item_status) = 'cancellation_requested') THEN 'В работе'
        WHEN bool_or(symbolika_normalize_item_status(oi.item_status) = 'in_work') THEN 'В работе'
        WHEN bool_or(symbolika_normalize_item_status(oi.item_status) = 'sent_to_work') THEN 'Отправлен в работу'
        WHEN bool_or(symbolika_normalize_item_status(oi.item_status) = 'approval') THEN 'Согласование'
        ELSE 'Новый'
      END AS expected_status
    FROM orders o
    JOIN orders_items oi ON oi."order" = o.id
    LEFT JOIN order_statuses os ON os.id = o.order_status
    GROUP BY o.id, o.order_number, os.name
  )
  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    order_id, order_number, detected_at
  )
  SELECT
    'order-status:' || order_id,
    'status_mismatch',
    'critical',
    'Статусы заказа и позиций не согласованы',
    format('Заказ %s · позиций: %s · статусы позиций: %s', COALESCE(order_number, order_id::text), item_count, item_statuses),
    COALESCE(actual_status, 'Без статуса'),
    expected_status,
    order_id,
    order_number,
    now()
  FROM item_rollup
  WHERE COALESCE(actual_status, '') <> expected_status;

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, procurement_batch_id, detected_at
  )
  SELECT
    'procurement-task:batch:' || b.id,
    'procurement_without_task',
    'critical',
    'Закупка без активной задачи',
    format('Пакет %s · позиций: %s', COALESCE(b.batch_number, '#' || b.id), COALESCE(b.item_count, 0)),
    CASE WHEN b.task_order_id IS NULL OR t.id IS NULL THEN 'Задача отсутствует' ELSE 'Задача отменена' END,
    'Активная задача на закупку',
    (SELECT min(r.id) FROM procurement_requests r WHERE r.procurement_batch = b.id),
    b.id,
    now()
  FROM procurement_batches b
  LEFT JOIN symbolika_tasks t ON t.id = b.task_order_id
  WHERE b.status NOT IN ('received', 'cancelled')
    AND (b.task_order_id IS NULL OR t.id IS NULL OR t.status = 'cancelled');

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, detected_at
  )
  SELECT
    'procurement-task:request:' || r.id,
    'procurement_without_task',
    'critical',
    'Закупочная заявка без активной задачи',
    format('%s · количество: %s %s', COALESCE(r.product_name, 'Без названия'), COALESCE(r.quantity::text, '—'), COALESCE(r.unit, '')),
    CASE WHEN r.task_order_id IS NULL OR t.id IS NULL THEN 'Задача отсутствует' ELSE 'Задача отменена' END,
    'Активная задача на закупку',
    r.id,
    now()
  FROM procurement_requests r
  LEFT JOIN symbolika_tasks t ON t.id = r.task_order_id
  WHERE r.procurement_batch IS NULL
    AND r.status NOT IN ('received', 'cancelled')
    AND (r.task_order_id IS NULL OR t.id IS NULL OR t.status = 'cancelled');

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, procurement_batch_id, task_id, task_title, detected_at
  )
  SELECT
    'completed-task:batch-order:' || b.id,
    'completed_task_open_procurement',
    'warning',
    'Задача выполнена, но закупка не переведена в «Заказано»',
    format('Пакет %s', COALESCE(b.batch_number, '#' || b.id)),
    'Нужно заказать',
    'Заказано',
    (SELECT min(r.id) FROM procurement_requests r WHERE r.procurement_batch = b.id),
    b.id,
    t.id,
    t.title,
    now()
  FROM procurement_batches b
  JOIN symbolika_tasks t ON t.id = b.task_order_id AND t.status = 'done'
  WHERE b.status = 'need_order';

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, task_id, task_title, detected_at
  )
  SELECT
    'completed-task:request-order:' || r.id,
    'completed_task_open_procurement',
    'warning',
    'Задача выполнена, но заявка не переведена в «Заказано»',
    COALESCE(r.product_name, 'Закупочная заявка #' || r.id),
    'Нужно заказать',
    'Заказано',
    r.id,
    t.id,
    t.title,
    now()
  FROM procurement_requests r
  JOIN symbolika_tasks t ON t.id = r.task_order_id AND t.status = 'done'
  WHERE r.procurement_batch IS NULL AND r.status = 'need_order';

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, procurement_batch_id, task_id, task_title, detected_at
  )
  SELECT
    'completed-task:batch-pickup:' || b.id,
    'completed_task_open_procurement',
    'warning',
    'Задача получения выполнена, но закупка не закрыта',
    format('Пакет %s', COALESCE(b.batch_number, '#' || b.id)),
    CASE b.status
      WHEN 'need_order' THEN 'Нужно заказать'
      WHEN 'ordered' THEN 'Заказано'
      WHEN 'ready_for_pickup' THEN 'Готово к получению'
      WHEN 'in_transit' THEN 'В пути'
      ELSE b.status
    END,
    'Получено',
    (SELECT min(r.id) FROM procurement_requests r WHERE r.procurement_batch = b.id),
    b.id,
    t.id,
    t.title,
    now()
  FROM procurement_batches b
  JOIN symbolika_tasks t ON t.id = b.task_pickup_id AND t.status = 'done'
  WHERE b.status NOT IN ('received', 'cancelled');

  INSERT INTO symbolika_automation_issues (
    id, issue_type, severity, title, detail, actual_value, expected_value,
    procurement_request_id, task_id, task_title, detected_at
  )
  SELECT
    'completed-task:request-pickup:' || r.id,
    'completed_task_open_procurement',
    'warning',
    'Задача получения выполнена, но заявка не закрыта',
    COALESCE(r.product_name, 'Закупочная заявка #' || r.id),
    CASE r.status
      WHEN 'need_order' THEN 'Нужно заказать'
      WHEN 'ordered' THEN 'Заказано'
      WHEN 'ready_for_pickup' THEN 'Готово к получению'
      WHEN 'in_transit' THEN 'В пути'
      ELSE r.status
    END,
    'Получено',
    r.id,
    t.id,
    t.title,
    now()
  FROM procurement_requests r
  JOIN symbolika_tasks t ON t.id = r.task_pickup_id AND t.status = 'done'
  WHERE r.procurement_batch IS NULL AND r.status NOT IN ('received', 'cancelled');

  INSERT INTO symbolika_automation_runs (
    handler_key, title, status, last_attempt_at, last_success_at, last_error, last_context, updated_at
  ) VALUES (
    'workflow_consistency', 'Сверка статусов и связей', 'ok', now(), now(), NULL,
    jsonb_build_object('issues_count', (SELECT count(*) FROM symbolika_automation_issues)), now()
  )
  ON CONFLICT (handler_key) DO UPDATE SET
    status = EXCLUDED.status,
    last_attempt_at = EXCLUDED.last_attempt_at,
    last_success_at = EXCLUDED.last_success_at,
    last_error = NULL,
    last_context = EXCLUDED.last_context,
    updated_at = EXCLUDED.updated_at;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_refresh_automation_issues_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Consistency control is derived data and must never delay the user's write.
  -- If another transaction is already rebuilding it, that transaction will
  -- include all committed changes and a later/manual refresh remains available.
  IF NOT pg_try_advisory_xact_lock(hashtext('symbolika_automation_issues_refresh')) THEN
    RETURN NULL;
  END IF;

  PERFORM refresh_symbolika_automation_issues();
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS zz_symbolika_refresh_automation_orders ON orders;
CREATE TRIGGER zz_symbolika_refresh_automation_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH STATEMENT EXECUTE FUNCTION symbolika_refresh_automation_issues_trigger();

DROP TRIGGER IF EXISTS zz_symbolika_refresh_automation_items ON orders_items;
CREATE TRIGGER zz_symbolika_refresh_automation_items
AFTER INSERT OR UPDATE OR DELETE ON orders_items
FOR EACH STATEMENT EXECUTE FUNCTION symbolika_refresh_automation_issues_trigger();

DROP TRIGGER IF EXISTS zz_symbolika_refresh_automation_requests ON procurement_requests;
CREATE TRIGGER zz_symbolika_refresh_automation_requests
AFTER INSERT OR UPDATE OR DELETE ON procurement_requests
FOR EACH STATEMENT EXECUTE FUNCTION symbolika_refresh_automation_issues_trigger();

DROP TRIGGER IF EXISTS zz_symbolika_refresh_automation_batches ON procurement_batches;
CREATE TRIGGER zz_symbolika_refresh_automation_batches
AFTER INSERT OR UPDATE OR DELETE ON procurement_batches
FOR EACH STATEMENT EXECUTE FUNCTION symbolika_refresh_automation_issues_trigger();

DROP TRIGGER IF EXISTS zz_symbolika_refresh_automation_tasks ON symbolika_tasks;
CREATE TRIGGER zz_symbolika_refresh_automation_tasks
AFTER INSERT OR UPDATE OR DELETE ON symbolika_tasks
FOR EACH STATEMENT EXECUTE FUNCTION symbolika_refresh_automation_issues_trigger();

SELECT refresh_symbolika_automation_issues();

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES (
  'symbolika_automation_issues', 'rule', 'Admin-only control of failed or inconsistent workflow automations.', '{{title}}', true, false, 937, 'all', '#F97316',
  json_build_array(json_build_object('language','ru-RU','translation','Контроль автоматизаций'))::json
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  accountability = EXCLUDED.accountability,
  color = EXCLUDED.color,
  translations = EXCLUDED.translations;

DELETE FROM directus_permissions WHERE collection = 'symbolika_automation_issues';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'symbolika_automation_issues', 'read', '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
WHERE p.admin_access = true;

-- Client operations outside orders: marketplace purchases, cash hand-offs and
-- other adjustments that affect reconciliation without becoming revenue.
CREATE TABLE IF NOT EXISTS customer_operations (
  id serial PRIMARY KEY,
  operation_date date NOT NULL DEFAULT CURRENT_DATE,
  operation_type varchar(64) NOT NULL DEFAULT 'other',
  direction varchar(32) NOT NULL DEFAULT 'customer_owes_us',
  amount numeric(14,2) NOT NULL DEFAULT 0,
  customer integer REFERENCES customers(id) ON DELETE SET NULL,
  customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  manager_employee integer REFERENCES employees(id) ON DELETE SET NULL,
  status varchar(32) NOT NULL DEFAULT 'confirmed',
  description text NOT NULL DEFAULT '',
  reference text,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customer_operations_amount_positive CHECK (amount > 0),
  CONSTRAINT customer_operations_direction_valid CHECK (direction IN ('customer_owes_us', 'we_owe_customer')),
  CONSTRAINT customer_operations_status_valid CHECK (status IN ('draft', 'confirmed', 'cancelled')),
  CONSTRAINT customer_operations_party_required CHECK (customer IS NOT NULL OR customer_company IS NOT NULL)
);

ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS operation_date date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS operation_type varchar(64) NOT NULL DEFAULT 'other';
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS direction varchar(32) NOT NULL DEFAULT 'customer_owes_us';
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS amount numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS customer integer REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS manager_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS status varchar(32) NOT NULL DEFAULT 'confirmed';
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '';
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS reference text;
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS date_created timestamptz NOT NULL DEFAULT now();
ALTER TABLE customer_operations ADD COLUMN IF NOT EXISTS date_updated timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS customer_operations_customer_idx ON customer_operations(customer);
CREATE INDEX IF NOT EXISTS customer_operations_company_idx ON customer_operations(customer_company);
CREATE INDEX IF NOT EXISTS customer_operations_manager_idx ON customer_operations(manager_employee);
CREATE INDEX IF NOT EXISTS customer_operations_date_idx ON customer_operations(operation_date);
CREATE INDEX IF NOT EXISTS customer_operations_status_idx ON customer_operations(status);

CREATE OR REPLACE FUNCTION symbolika_prepare_customer_operation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.operation_date := COALESCE(NEW.operation_date, CURRENT_DATE);
  NEW.amount := round(COALESCE(NEW.amount, 0), 2);
  NEW.description := btrim(COALESCE(NEW.description, ''));
  NEW.date_updated := now();

  IF NEW.customer IS NULL AND NEW.customer_company IS NULL THEN
    RAISE EXCEPTION 'Укажите клиента или компанию для операции';
  END IF;
  IF NEW.amount <= 0 THEN
    RAISE EXCEPTION 'Сумма клиентской операции должна быть больше нуля';
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

DROP TRIGGER IF EXISTS symbolika_prepare_customer_operation ON customer_operations;
CREATE TRIGGER symbolika_prepare_customer_operation
BEFORE INSERT OR UPDATE ON customer_operations
FOR EACH ROW EXECUTE FUNCTION symbolika_prepare_customer_operation();

CREATE OR REPLACE FUNCTION symbolika_recalc_customer_operation_balance(customer_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  orders_sum numeric(14,2) := 0;
  payments_in numeric(14,2) := 0;
  refunds_out numeric(14,2) := 0;
  charges numeric(14,2) := 0;
  credits numeric(14,2) := 0;
  next_balance numeric(14,2) := 0;
BEGIN
  IF customer_id IS NULL THEN RETURN; END IF;

  SELECT COALESCE(sum(COALESCE(o.order_sum, 0)), 0) INTO orders_sum
  FROM orders o WHERE o.customer = customer_id AND o.customer_company IS NULL;

  SELECT
    COALESCE(sum(CASE WHEN op.payment_direction <> 'outgoing_refund' THEN COALESCE(op.amount, 0) ELSE 0 END), 0),
    COALESCE(sum(CASE WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN COALESCE(op.amount, 0) ELSE 0 END), 0)
  INTO payments_in, refunds_out
  FROM order_payments op WHERE op.customer = customer_id AND op.customer_company IS NULL;

  SELECT
    COALESCE(sum(CASE WHEN co.direction = 'customer_owes_us' THEN co.amount ELSE 0 END), 0),
    COALESCE(sum(CASE WHEN co.direction = 'we_owe_customer' THEN co.amount ELSE 0 END), 0)
  INTO charges, credits
  FROM customer_operations co
  WHERE co.customer = customer_id AND co.customer_company IS NULL AND co.status = 'confirmed';

  next_balance := payments_in - refunds_out - orders_sum - charges + credits;
  UPDATE customers
  SET orders_total_sum = orders_sum,
      payments_total_in = payments_in,
      refunds_total_out = refunds_out,
      balance = next_balance,
      debt_to_us = GREATEST(-next_balance, 0),
      our_debt_to_customer = GREATEST(next_balance, 0)
  WHERE id = customer_id;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_recalc_company_operation_balance(company_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  orders_sum numeric(14,2) := 0;
  payments_in numeric(14,2) := 0;
  refunds_out numeric(14,2) := 0;
  charges numeric(14,2) := 0;
  credits numeric(14,2) := 0;
  next_balance numeric(14,2) := 0;
BEGIN
  IF company_id IS NULL THEN RETURN; END IF;

  SELECT COALESCE(sum(COALESCE(o.order_sum, 0)), 0) INTO orders_sum
  FROM orders o WHERE o.customer_company = company_id;

  SELECT
    COALESCE(sum(CASE WHEN op.payment_direction <> 'outgoing_refund' THEN COALESCE(op.amount, 0) ELSE 0 END), 0),
    COALESCE(sum(CASE WHEN op.payment_direction = 'outgoing_refund' OR op.allocation_mode = 'refund' THEN COALESCE(op.amount, 0) ELSE 0 END), 0)
  INTO payments_in, refunds_out
  FROM order_payments op WHERE op.customer_company = company_id;

  SELECT
    COALESCE(sum(CASE WHEN co.direction = 'customer_owes_us' THEN co.amount ELSE 0 END), 0),
    COALESCE(sum(CASE WHEN co.direction = 'we_owe_customer' THEN co.amount ELSE 0 END), 0)
  INTO charges, credits
  FROM customer_operations co
  WHERE co.customer_company = company_id AND co.status = 'confirmed';

  next_balance := payments_in - refunds_out - orders_sum - charges + credits;
  UPDATE customer_companies
  SET orders_total_sum = orders_sum,
      payments_total_in = payments_in,
      refunds_total_out = refunds_out,
      balance = next_balance,
      debt_to_us = GREATEST(-next_balance, 0),
      our_debt_to_customer = GREATEST(next_balance, 0)
  WHERE id = company_id;
END;
$$;

ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS entry_type varchar(32) NOT NULL DEFAULT 'order';
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS client_operation integer;
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS operation_type varchar(64);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS direction varchar(32);
ALTER TABLE customer_reconciliation ADD COLUMN IF NOT EXISTS description text;

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
    CASE WHEN co.direction = 'we_owe_customer' THEN co.amount ELSE 0 END,
    CASE WHEN co.direction = 'customer_owes_us' THEN co.amount ELSE 0 END,
    CASE WHEN co.direction = 'we_owe_customer' THEN co.amount ELSE 0 END,
    CASE WHEN co.direction = 'customer_owes_us' THEN co.amount ELSE 0 END,
    CASE WHEN co.direction = 'we_owe_customer' THEN co.amount ELSE 0 END,
    CASE WHEN co.direction = 'customer_owes_us' THEN 'Клиент должен' ELSE 'Мы должны' END,
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

CREATE OR REPLACE FUNCTION symbolika_refresh_customer_operation()
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

DROP TRIGGER IF EXISTS symbolika_refresh_customer_operation ON customer_operations;
CREATE TRIGGER symbolika_refresh_customer_operation
AFTER INSERT OR UPDATE OR DELETE ON customer_operations
FOR EACH ROW EXECUTE FUNCTION symbolika_refresh_customer_operation();

DO $$
DECLARE row_item record;
BEGIN
  FOR row_item IN SELECT id FROM customers LOOP
    PERFORM symbolika_recalc_customer_operation_balance(row_item.id);
  END LOOP;
  FOR row_item IN SELECT id FROM customer_companies LOOP
    PERFORM symbolika_recalc_company_operation_balance(row_item.id);
  END LOOP;
END;
$$;
SELECT refresh_customer_reconciliation();

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES (
  'customer_operations', 'swap_horiz', 'Операции с заказчиками вне заказов, влияющие на взаиморасчеты.', '{{description}}', false, false, 938, 'all', '#F97316',
  json_build_array(json_build_object('language','ru-RU','translation','Клиентские операции'))::json
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon, note = EXCLUDED.note, display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden, accountability = EXCLUDED.accountability,
  color = EXCLUDED.color, translations = EXCLUDED.translations;

DELETE FROM directus_fields WHERE collection = 'customer_operations';
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required
) VALUES
  ('customer_operations','id',NULL,'input',NULL,NULL,NULL,true,true,1,'half',NULL,false),
  ('customer_operations','operation_date',NULL,'datetime','{"includeSeconds":false,"use24":true}'::json,'datetime',NULL,false,false,2,'half',json_build_array(json_build_object('language','ru-RU','translation','Дата'))::json,true),
  ('customer_operations','operation_type',NULL,'select-dropdown','{"choices":[{"text":"Покупка на маркетплейсе","value":"marketplace_purchase"},{"text":"Выдача / снятие наличных","value":"cash_withdrawal"},{"text":"Прочая просьба","value":"other"}]}'::json,'labels',NULL,false,false,3,'half',json_build_array(json_build_object('language','ru-RU','translation','Тип операции'))::json,true),
  ('customer_operations','direction',NULL,'select-dropdown','{"choices":[{"text":"Клиент должен нам","value":"customer_owes_us"},{"text":"Мы должны клиенту","value":"we_owe_customer"}]}'::json,'labels',NULL,false,false,4,'half',json_build_array(json_build_object('language','ru-RU','translation','Влияние на баланс'))::json,true),
  ('customer_operations','amount',NULL,'input',NULL,NULL,NULL,false,false,5,'half',json_build_array(json_build_object('language','ru-RU','translation','Сумма'))::json,true),
  ('customer_operations','customer','m2o','select-dropdown-m2o','{"template":"{{name}} · {{phone}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,6,'half',json_build_array(json_build_object('language','ru-RU','translation','Клиент'))::json,false),
  ('customer_operations','customer_company','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,7,'half',json_build_array(json_build_object('language','ru-RU','translation','Компания'))::json,false),
  ('customer_operations','manager_employee','m2o','select-dropdown-m2o','{"template":"{{full_name}}"}'::json,'related-values','{"template":"{{full_name}}"}'::json,true,true,8,'half',json_build_array(json_build_object('language','ru-RU','translation','Менеджер'))::json,false),
  ('customer_operations','status',NULL,'select-dropdown','{"choices":[{"text":"Черновик","value":"draft"},{"text":"Подтверждена","value":"confirmed"},{"text":"Отменена","value":"cancelled"}]}'::json,'labels',NULL,false,false,9,'half',json_build_array(json_build_object('language','ru-RU','translation','Статус'))::json,true),
  ('customer_operations','description',NULL,'input-multiline',NULL,NULL,NULL,false,false,10,'full',json_build_array(json_build_object('language','ru-RU','translation','Что сделали'))::json,true),
  ('customer_operations','reference',NULL,'input',NULL,NULL,NULL,false,false,11,'full',json_build_array(json_build_object('language','ru-RU','translation','Ссылка / номер / примечание'))::json,false),
  ('customer_operations','date_created','date-created',NULL,NULL,'datetime',NULL,true,true,12,'half',NULL,false),
  ('customer_operations','date_updated','date-updated',NULL,NULL,'datetime',NULL,true,true,13,'half',NULL,false);

DELETE FROM directus_relations
WHERE many_collection = 'customer_operations' AND many_field IN ('customer','customer_company','manager_employee');
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_deselect_action) VALUES
  ('customer_operations','customer','customers','nullify'),
  ('customer_operations','customer_company','customer_companies','nullify'),
  ('customer_operations','manager_employee','employees','nullify');

DELETE FROM directus_permissions WHERE collection = 'customer_operations';
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('customer_operations','read','{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000201'),
  ('customer_operations','create','{}'::json,'{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,'operation_date,operation_type,direction,amount,customer,customer_company,manager_employee,status,description,reference','00000000-0000-4000-8000-000000000201'),
  ('customer_operations','update','{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,'{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,'operation_date,operation_type,direction,amount,customer,customer_company,status,description,reference','00000000-0000-4000-8000-000000000201'),
  ('customer_operations','read','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205'),
  ('customer_operations','create','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205'),
  ('customer_operations','update','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205'),
  ('customer_operations','delete','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'customer_operations', action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES ('read'),('create'),('update'),('delete')) actions(action_name)
WHERE p.admin_access = true;

-- Technical audit fields: visible to the calculation layer, hidden from normal
-- forms so operational reassignment cannot accidentally move commission.
DELETE FROM directus_fields
WHERE (collection = 'orders' AND field = 'commission_manager_employee')
   OR (collection = 'orders_items' AND field = 'commission_manager_employee');

INSERT INTO directus_fields (
  collection, field, special, interface, display, readonly, hidden, width
) VALUES
  ('orders', 'commission_manager_employee', 'm2o', 'select-dropdown-m2o', 'related-values', true, true, 'half'),
  ('orders_items', 'commission_manager_employee', 'm2o', 'select-dropdown-m2o', 'related-values', true, true, 'half');

DELETE FROM directus_relations
WHERE (many_collection = 'orders' AND many_field = 'commission_manager_employee')
   OR (many_collection = 'orders_items' AND many_field = 'commission_manager_employee');

INSERT INTO directus_relations (
  many_collection, many_field, one_collection, one_deselect_action
) VALUES
  ('orders', 'commission_manager_employee', 'employees', 'nullify'),
  ('orders_items', 'commission_manager_employee', 'employees', 'nullify');

-- Internal work-area routing is managed in the custom order/item cards. It does
-- not replace contractors and is hidden from the standard Directus item form.
DELETE FROM directus_fields
WHERE collection = 'orders_items'
  AND field IN ('internal_route_production', 'internal_route_screen');

INSERT INTO directus_fields (
  collection, field, interface, display, readonly, hidden, width, translations
) VALUES
  ('orders_items', 'internal_route_production', 'boolean', 'boolean', false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043f. \043c\0430\0440\0448\0440\0443\0442: \041f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'))::json),
  ('orders_items', 'internal_route_screen', 'boolean', 'boolean', false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation', U&'\0414\043e\043f. \043c\0430\0440\0448\0440\0443\0442: \0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'))::json);

-- Every authenticated application role receives only the file operations needed
-- to upload and display avatars. Profile contacts and salary are served by the
-- scoped symbolika-profile endpoint and never exposed here as unrestricted data.
INSERT INTO directus_policies (id, name, icon, description, ip_access, enforce_tfa, admin_access, app_access)
VALUES (
  '00000000-0000-4000-8000-000000000209',
  'Личный кабинет',
  'account_circle',
  'Загрузка аватара для собственного профиля.',
  NULL,
  false,
  false,
  true
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  description = EXCLUDED.description,
  admin_access = EXCLUDED.admin_access,
  app_access = EXCLUDED.app_access;

DELETE FROM directus_access
WHERE policy = '00000000-0000-4000-8000-000000000209';

INSERT INTO directus_access (id, role, "user", policy, sort)
SELECT gen_random_uuid(), r.id, NULL, '00000000-0000-4000-8000-000000000209', 100
FROM directus_roles r
WHERE r.name IN ('Управляющий', 'Менеджер', 'Производство', 'Шелкография', 'Дизайнер', 'Контрагент');

DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000209';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('directus_files', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000209'),
  ('directus_files', 'create', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000209');

-- Public item links and the single customer notification scenario: an order is
-- ready and physically available for office pickup.
ALTER TABLE orders_items
  ADD COLUMN IF NOT EXISTS public_token uuid DEFAULT gen_random_uuid();

UPDATE orders_items
SET public_token = gen_random_uuid()
WHERE public_token IS NULL;

ALTER TABLE orders_items
  ALTER COLUMN public_token SET DEFAULT gen_random_uuid(),
  ALTER COLUMN public_token SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS orders_items_public_token_uidx
  ON orders_items(public_token);

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS notification_channel varchar(32) NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS telegram_chat_id varchar(100),
  ADD COLUMN IF NOT EXISTS vk_peer_id varchar(100);

ALTER TABLE customer_companies
  ADD COLUMN IF NOT EXISTS notification_channel varchar(32) NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS telegram_chat_id varchar(100),
  ADD COLUMN IF NOT EXISTS vk_peer_id varchar(100);

CREATE TABLE IF NOT EXISTS symbolika_customer_notification_settings (
  id integer PRIMARY KEY,
  office_address text,
  office_hours text,
  website_url text,
  vk_group_url text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT symbolika_customer_notification_settings_singleton CHECK (id = 1)
);

INSERT INTO symbolika_customer_notification_settings (
  id, office_address, office_hours, website_url, vk_group_url
) VALUES (1, NULL, NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS symbolika_customer_notifications (
  id bigserial PRIMARY KEY,
  "order" integer NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  customer integer REFERENCES customers(id) ON DELETE SET NULL,
  customer_company integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  event_key varchar(80) NOT NULL DEFAULT 'ready_in_office',
  channel varchar(32),
  recipient text,
  subject text,
  message text,
  status varchar(32) NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  UNIQUE ("order", event_key)
);

CREATE INDEX IF NOT EXISTS symbolika_customer_notifications_status_idx
  ON symbolika_customer_notifications(status, updated_at);

DELETE FROM directus_fields
WHERE (collection = 'orders_items' AND field = 'public_token')
   OR (collection IN ('customers', 'customer_companies') AND field IN ('notification_channel', 'telegram_chat_id', 'vk_peer_id'));

INSERT INTO directus_fields (
  collection, field, interface, options, display, readonly, hidden, width, translations
) VALUES
  ('orders_items', 'public_token', 'input', NULL, NULL, true, true, 'full', json_build_array(json_build_object('language','ru-RU','translation','Публичный токен позиции'))::json),
  ('customers', 'notification_channel', 'select-dropdown', '{"choices":[{"text":"Не отправлять","value":"none"},{"text":"Email","value":"email"},{"text":"ВКонтакте","value":"vk"},{"text":"Telegram","value":"telegram"},{"text":"SMS","value":"sms"}]}'::json, 'labels', false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','Основной канал уведомлений'))::json),
  ('customers', 'telegram_chat_id', 'input', NULL, NULL, false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','Telegram chat ID'))::json),
  ('customers', 'vk_peer_id', 'input', NULL, NULL, false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','VK peer ID'))::json),
  ('customer_companies', 'notification_channel', 'select-dropdown', '{"choices":[{"text":"Не отправлять","value":"none"},{"text":"Email","value":"email"},{"text":"ВКонтакте","value":"vk"},{"text":"Telegram","value":"telegram"},{"text":"SMS","value":"sms"}]}'::json, 'labels', false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','Основной канал уведомлений'))::json),
  ('customer_companies', 'telegram_chat_id', 'input', NULL, NULL, false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','Telegram chat ID'))::json),
  ('customer_companies', 'vk_peer_id', 'input', NULL, NULL, false, true, 'half', json_build_array(json_build_object('language','ru-RU','translation','VK peer ID'))::json);

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES
  ('symbolika_customer_notification_settings', 'notifications_active', 'Адрес, режим работы и публичные ссылки для уведомления о готовом заказе.', '{{office_address}}', true, false, 941, 'all', '#F97316', json_build_array(json_build_object('language','ru-RU','translation','Настройки уведомлений клиентам'))::json),
  ('symbolika_customer_notifications', 'outgoing_mail', 'Журнал автоматической отправки уведомлений о готовых заказах в офисе.', '{{subject}}', true, false, 942, 'all', '#F97316', json_build_array(json_build_object('language','ru-RU','translation','Уведомления клиентам'))::json)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  singleton = EXCLUDED.singleton,
  accountability = EXCLUDED.accountability,
  color = EXCLUDED.color,
  translations = EXCLUDED.translations;

DELETE FROM directus_fields
WHERE collection IN ('symbolika_customer_notification_settings', 'symbolika_customer_notifications');

INSERT INTO directus_fields (
  collection, field, interface, options, display, readonly, hidden, sort, width, translations
) VALUES
  ('symbolika_customer_notification_settings', 'id', 'input', NULL, NULL, true, true, 1, 'half', NULL),
  ('symbolika_customer_notification_settings', 'office_address', 'input', NULL, NULL, false, false, 2, 'full', json_build_array(json_build_object('language','ru-RU','translation','Адрес офиса'))::json),
  ('symbolika_customer_notification_settings', 'office_hours', 'input', NULL, NULL, false, false, 3, 'full', json_build_array(json_build_object('language','ru-RU','translation','Время работы офиса'))::json),
  ('symbolika_customer_notification_settings', 'website_url', 'input', NULL, NULL, false, false, 4, 'full', json_build_array(json_build_object('language','ru-RU','translation','Сайт'))::json),
  ('symbolika_customer_notification_settings', 'vk_group_url', 'input', NULL, NULL, false, false, 5, 'full', json_build_array(json_build_object('language','ru-RU','translation','Группа ВКонтакте'))::json),
  ('symbolika_customer_notification_settings', 'updated_at', 'datetime', NULL, 'datetime', true, true, 6, 'half', NULL),
  ('symbolika_customer_notifications', 'id', 'input', NULL, NULL, true, true, 1, 'half', NULL),
  ('symbolika_customer_notifications', 'order', 'select-dropdown-m2o', NULL, 'related-values', true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Заказ'))::json),
  ('symbolika_customer_notifications', 'channel', 'input', NULL, NULL, true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Канал'))::json),
  ('symbolika_customer_notifications', 'recipient', 'input', NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Получатель'))::json),
  ('symbolika_customer_notifications', 'subject', 'input', NULL, NULL, true, false, 5, 'full', json_build_array(json_build_object('language','ru-RU','translation','Тема'))::json),
  ('symbolika_customer_notifications', 'message', 'input-multiline', NULL, NULL, true, false, 6, 'full', json_build_array(json_build_object('language','ru-RU','translation','Сообщение'))::json),
  ('symbolika_customer_notifications', 'status', 'input', NULL, NULL, true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Статус отправки'))::json),
  ('symbolika_customer_notifications', 'attempts', 'input', NULL, NULL, true, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation','Попыток'))::json),
  ('symbolika_customer_notifications', 'last_error', 'input-multiline', NULL, NULL, true, false, 9, 'full', json_build_array(json_build_object('language','ru-RU','translation','Ошибка'))::json),
  ('symbolika_customer_notifications', 'sent_at', 'datetime', NULL, 'datetime', true, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation','Отправлено'))::json);

DELETE FROM directus_relations
WHERE many_collection = 'symbolika_customer_notifications'
  AND many_field IN ('order', 'customer', 'customer_company');

INSERT INTO directus_relations (many_collection, many_field, one_collection, one_deselect_action) VALUES
  ('symbolika_customer_notifications', 'order', 'orders', 'delete'),
  ('symbolika_customer_notifications', 'customer', 'customers', 'nullify'),
  ('symbolika_customer_notifications', 'customer_company', 'customer_companies', 'nullify');

-- Managers may configure delivery details only for their own clients/companies;
-- admin and managerial policies retain unrestricted access.
UPDATE directus_permissions
SET fields = fields || ',notification_channel,telegram_chat_id,vk_peer_id'
WHERE collection IN ('customers', 'customer_companies')
  AND action IN ('read', 'create', 'update')
  AND fields <> '*'
  AND position('notification_channel' in fields) = 0;

DELETE FROM directus_permissions
WHERE collection IN ('symbolika_customer_notification_settings', 'symbolika_customer_notifications');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES
  ('symbolika_customer_notification_settings', 'read'),
  ('symbolika_customer_notification_settings', 'update'),
  ('symbolika_customer_notifications', 'read')
) permissions(collection_name, action_name)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('symbolika_customer_notification_settings', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('symbolika_customer_notification_settings', 'update', '{}'::json, NULL, NULL, 'office_address,office_hours,website_url,vk_group_url,updated_at', '00000000-0000-4000-8000-000000000205'),
  ('symbolika_customer_notifications', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205');

-- Operational modules preload a few compact dictionaries for forms, status
-- labels and inventory supplier selectors. Keep these reads deliberately
-- narrow so a role does not gain access to contractor finance or contacts.
DELETE FROM directus_permissions
WHERE collection = 'contractors'
  AND action = 'read'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206'
  );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'contractors', 'read', '{}'::json, NULL, NULL,
       'id,name,supplies_textile_blanks,supplies_merch_blanks', policy_id::uuid
FROM (VALUES
  ('00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000204'),
  ('00000000-0000-4000-8000-000000000206')
) AS policies(policy_id);

DELETE FROM directus_permissions
WHERE collection IN ('order_statuses', 'production_statuses')
  AND action = 'read'
  AND policy = '00000000-0000-4000-8000-000000000208';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, 'read', '{}'::json, NULL, NULL, 'id,name,sort,is_active',
       '00000000-0000-4000-8000-000000000208'::uuid
FROM (VALUES ('order_statuses'), ('production_statuses')) AS dictionaries(collection_name);

-- Working modules request compact related dictionaries on startup. These
-- permissions match the fields used by the UI and do not expose costing totals,
-- contractor prices or private customer data to production roles.
DELETE FROM directus_permissions
WHERE action = 'read'
  AND (
    (collection = 'symbolika_automation_issues' AND policy = '00000000-0000-4000-8000-000000000205')
    OR (collection = 'contractor_costing' AND policy = '00000000-0000-4000-8000-000000000201')
    OR (collection = 'product_application_methods' AND policy = '00000000-0000-4000-8000-000000000204')
    OR (collection IN ('order_statuses', 'product_categories', 'product_subcategories', 'product_application_methods')
        AND policy = '00000000-0000-4000-8000-000000000206')
  );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('symbolika_automation_issues', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('contractor_costing', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL, NULL,
    'id,order_link,order_number,date,customer,customer_company,manager_employee,product_name,quantity,deadline,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,production_status,price_per_unit,order_sum',
    '00000000-0000-4000-8000-000000000201'),
  ('product_application_methods', 'read', '{}'::json, NULL, NULL, 'id,name,category,is_active,sort', '00000000-0000-4000-8000-000000000204'),
  ('order_statuses', 'read', '{}'::json, NULL, NULL, 'id,name,sort,is_active', '00000000-0000-4000-8000-000000000206'),
  ('product_categories', 'read', '{}'::json, NULL, NULL, 'id,name,detail_mode,is_active,sort', '00000000-0000-4000-8000-000000000206'),
  ('product_subcategories', 'read', '{}'::json, NULL, NULL, 'id,name,category,is_active,sort', '00000000-0000-4000-8000-000000000206'),
  ('product_application_methods', 'read', '{}'::json, NULL, NULL, 'id,name,category,is_active,sort', '00000000-0000-4000-8000-000000000206');

-- Personal sales for every internal employee. Production, screen printing and
-- design retain their operational access and additionally receive a private
-- manager workspace for orders they create themselves. The create hooks force
-- manager_employee to the current employee, so these permissions cannot be used
-- to create an order on behalf of somebody else.
DELETE FROM directus_permissions
WHERE policy IN (
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  )
  AND (
    (collection = 'orders' AND action = 'create')
    OR (collection = 'orders_items' AND action = 'create')
    OR (collection = 'orders_items' AND action = 'delete')
  );

DELETE FROM directus_permissions
WHERE collection = 'orders_items'
  AND action = 'delete'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('orders_items', 'delete', '{"_and":[{"item_status":{"_in":["new","approval"]}},{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000201'),
  ('orders_items', 'delete', '{"_and":[{"item_status":{"_in":["new","approval"]}},{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000202'),
  ('orders_items', 'delete', '{"_and":[{"item_status":{"_in":["new","approval"]}},{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000204'),
  ('orders_items', 'delete', '{"item_status":{"_in":["new","approval"]}}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('orders_items', 'delete', '{"_and":[{"item_status":{"_in":["new","approval"]}},{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000206'),
  ('orders_items', 'delete', '{"_and":[{"item_status":{"_in":["new","approval"]}},{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000208');

WITH self_sales_policies(policy) AS (
  VALUES
    ('00000000-0000-4000-8000-000000000204'::uuid),
    ('00000000-0000-4000-8000-000000000206'::uuid),
    ('00000000-0000-4000-8000-000000000208'::uuid)
), permission_rows(collection, action, permissions, validation, presets, fields) AS (
  VALUES
    ('orders', 'create', '{}'::json,
      NULL::json, NULL::json,
      'date,deadline,customer,customer_company,order_status,comment,shipping_method,shipping_comment,payment_type,order_items,payment_on_receipt,office_status,order_number,manager_employee'),
    ('orders', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,
      NULL::json, NULL::json,
      'id,order_number,date,deadline,manager_employee,customer,customer_company,order_status,comment,shipping_method,shipping_comment,order_sum,paid_amount,payment_due,office_payment_due,payment_type,order_items,payments,payment_on_receipt,office_status'),
    ('orders', 'update', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,
      NULL::json, NULL::json,
      'date,deadline,customer,customer_company,order_status,comment,shipping_method,shipping_comment,payment_type,order_items,payment_on_receipt,office_status'),
    ('orders_items', 'create', '{}'::json,
      NULL::json, '{"production_status":7}'::json,
      'order,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url,manager_employee'),
    ('orders_items', 'read', '{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json,
      NULL::json, NULL::json,
      'id,order,order_link,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,production_status,deadline,production_comment,technical_task_text,manager_employee,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url,layout_revision_url_snapshot,layout_disk_path,layout_disk_name,layout_disk_size,layout_disk_mime_type,layout_disk_uploaded_at,layout_preview_url,layout_preview_disk_path,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at'),
    ('orders_items', 'update', '{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json,
      NULL::json, NULL::json,
      'product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url'),
    ('customers', 'create', '{}'::json, NULL::json, NULL::json,
      'name,phone,email,manager,company,comment,vk_page_url,notification_channel,telegram_chat_id,vk_peer_id'),
    ('customers', 'read', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL::json, NULL::json, '*'),
    ('customers', 'update', '{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,
      NULL::json, NULL::json,
      'name,phone,email,company,comment,vk_page_url,notification_channel,telegram_chat_id,vk_peer_id'),
    ('customer_companies', 'create', '{}'::json, NULL::json, NULL::json,
      'name,phone,email,manager,comment,notification_channel,telegram_chat_id,vk_peer_id'),
    ('customer_companies', 'read', '{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json,
      NULL::json, NULL::json, '*'),
    ('customer_company_links', 'read', '{"customer":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json,
      NULL::json, NULL::json, '*'),
    ('payment_types', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,is_active,sort'),
    ('contractors', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,supplies_textile_blanks,supplies_merch_blanks'),
    ('product_categories', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,detail_mode,is_active,sort'),
    ('product_subcategories', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,category,is_active,sort'),
    ('product_application_methods', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,category,is_active,sort'),
    ('order_statuses', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,sort,is_active'),
    ('production_statuses', 'read', '{}'::json, NULL::json, NULL::json, 'id,name,sort,is_active')
)
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT pr.collection, pr.action, pr.permissions, pr.validation, pr.presets, pr.fields, sp.policy
FROM self_sales_policies sp
CROSS JOIN permission_rows pr
WHERE NOT EXISTS (
  SELECT 1
  FROM directus_permissions existing
  WHERE existing.policy = sp.policy
    AND existing.collection = pr.collection
    AND existing.action = pr.action
    AND COALESCE(existing.permissions::jsonb, 'null'::jsonb) = COALESCE(pr.permissions::jsonb, 'null'::jsonb)
    AND COALESCE(existing.validation::jsonb, 'null'::jsonb) = COALESCE(pr.validation::jsonb, 'null'::jsonb)
    AND COALESCE(existing.fields, '') = COALESCE(pr.fields, '')
);

-- A customer belongs to an employee not only when the employee is explicitly
-- selected in customers.manager, but also when the employee has already
-- created an order for that customer. This second path keeps a customer
-- available after quick creation inside the new-order dialog even if an old
-- record has an empty or stale manager relation.
UPDATE directus_permissions
SET permissions = '{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"orders":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json
WHERE collection = 'customers'
  AND action IN ('read', 'update')
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

UPDATE directus_permissions
SET permissions = '{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"orders":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}'::json
WHERE collection = 'customer_companies'
  AND action IN ('read', 'update')
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

WITH self_sales_policies(policy) AS (
  VALUES
    ('00000000-0000-4000-8000-000000000204'::uuid),
    ('00000000-0000-4000-8000-000000000206'::uuid),
    ('00000000-0000-4000-8000-000000000208'::uuid)
), private_collections(collection, permissions) AS (
  VALUES
    ('my_orders_in_work', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json),
    ('my_orders_completed', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json),
    ('my_orders_unpaid', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json),
    ('my_orders_in_work_items', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json),
    ('my_orders_completed_items', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json),
    ('my_orders_unpaid_items', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json),
    ('my_orders_in_work_payments', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json),
    ('my_orders_completed_payments', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json),
    ('my_orders_unpaid_payments', '{"bucket_order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json)
)
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT pc.collection, 'read', pc.permissions, NULL, NULL, '*', sp.policy
FROM self_sales_policies sp
CROSS JOIN private_collections pc
WHERE NOT EXISTS (
  SELECT 1 FROM directus_permissions existing
  WHERE existing.policy = sp.policy
    AND existing.collection = pc.collection
    AND existing.action = 'read'
    AND existing.permissions::jsonb = pc.permissions::jsonb
);

-- ---------------------------------------------------------------------------
-- Встроенный почтовый клиент
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS symbolika_mail_folders (
  id bigserial PRIMARY KEY,
  slug varchar(120) NOT NULL UNIQUE,
  name varchar(255) NOT NULL,
  imap_name varchar(500),
  alias_email varchar(255),
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  is_shared boolean NOT NULL DEFAULT false,
  is_system boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  sort integer NOT NULL DEFAULT 100,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS symbolika_mail_threads (
  id bigserial PRIMARY KEY,
  folder_id bigint NOT NULL REFERENCES symbolika_mail_folders(id) ON DELETE CASCADE,
  external_thread_id varchar(500),
  subject text NOT NULL DEFAULT '(без темы)',
  preview text,
  participants jsonb NOT NULL DEFAULT '[]'::jsonb,
  customer_id integer REFERENCES customers(id) ON DELETE SET NULL,
  company_id integer REFERENCES customer_companies(id) ON DELETE SET NULL,
  order_id integer REFERENCES orders(id) ON DELETE SET NULL,
  task_id integer REFERENCES symbolika_tasks(id) ON DELETE SET NULL,
  is_unread boolean NOT NULL DEFAULT true,
  is_starred boolean NOT NULL DEFAULT false,
  is_archived boolean NOT NULL DEFAULT false,
  tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE(folder_id, external_thread_id)
);

ALTER TABLE symbolika_mail_threads ADD COLUMN IF NOT EXISTS tags jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS symbolika_mail_payment_tasks (
  id bigserial PRIMARY KEY,
  thread_id bigint NOT NULL REFERENCES symbolika_mail_threads(id) ON DELETE CASCADE,
  task_id integer NOT NULL REFERENCES symbolika_tasks(id) ON DELETE CASCADE,
  date_created timestamptz NOT NULL DEFAULT now(),
  UNIQUE (thread_id, task_id)
);

ALTER TABLE symbolika_mail_payment_tasks ADD COLUMN IF NOT EXISTS id bigserial;
DO $$
DECLARE
  primary_constraint text;
BEGIN
  SELECT conname INTO primary_constraint
  FROM pg_constraint
  WHERE conrelid = 'symbolika_mail_payment_tasks'::regclass AND contype = 'p';
  IF primary_constraint IS NOT NULL AND primary_constraint <> 'symbolika_mail_payment_tasks_id_pkey' THEN
    EXECUTE format('ALTER TABLE symbolika_mail_payment_tasks DROP CONSTRAINT %I', primary_constraint);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'symbolika_mail_payment_tasks'::regclass AND contype = 'p'
  ) THEN
    ALTER TABLE symbolika_mail_payment_tasks ADD CONSTRAINT symbolika_mail_payment_tasks_id_pkey PRIMARY KEY (id);
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS symbolika_mail_payment_tasks_thread_task_uidx
  ON symbolika_mail_payment_tasks(thread_id, task_id);

CREATE TABLE IF NOT EXISTS symbolika_mail_messages (
  id bigserial PRIMARY KEY,
  thread_id bigint NOT NULL REFERENCES symbolika_mail_threads(id) ON DELETE CASCADE,
  message_id varchar(1000),
  in_reply_to varchar(1000),
  direction varchar(20) NOT NULL DEFAULT 'inbound' CHECK (direction IN ('inbound', 'outbound')),
  from_email varchar(255) NOT NULL,
  from_name varchar(255),
  to_emails jsonb NOT NULL DEFAULT '[]'::jsonb,
  cc_emails jsonb NOT NULL DEFAULT '[]'::jsonb,
  sender_alias varchar(255),
  subject text NOT NULL DEFAULT '(без темы)',
  body_text text,
  body_html text,
  attachments jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_read boolean NOT NULL DEFAULT false,
  is_test boolean NOT NULL DEFAULT false,
  author_user uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  date_created timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS symbolika_mail_messages_message_id_uidx
  ON symbolika_mail_messages(message_id);
CREATE INDEX IF NOT EXISTS symbolika_mail_threads_folder_date_idx
  ON symbolika_mail_threads(folder_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS symbolika_mail_threads_links_idx
  ON symbolika_mail_threads(customer_id, company_id, order_id, task_id);
CREATE INDEX IF NOT EXISTS symbolika_mail_messages_thread_date_idx
  ON symbolika_mail_messages(thread_id, sent_at);

INSERT INTO symbolika_mail_folders (slug, name, imap_name, alias_email, is_shared, is_system, sort)
VALUES
  ('inbox', 'Входящие', 'INBOX', 'start@symb62.ru', true, true, 10),
  ('sent', 'Отправленные', 'Sent', 'start@symb62.ru', true, true, 900),
  ('archive', 'Архив', 'Archive', 'start@symb62.ru', true, true, 950)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  alias_email = COALESCE(symbolika_mail_folders.alias_email, EXCLUDED.alias_email),
  is_shared = true,
  is_system = true;

-- Новые исходящие цепочки должны находиться в «Отправленных», даже если
-- пользователь открыл окно написания из папки «Входящие».
UPDATE symbolika_mail_threads t
SET folder_id = sent.id,
    is_unread = false,
    date_updated = NOW()
FROM symbolika_mail_folders sent
WHERE sent.slug = 'sent'
  AND t.folder_id <> sent.id
  AND EXISTS (
    SELECT 1 FROM symbolika_mail_messages m
    WHERE m.thread_id = t.id AND m.direction = 'outbound'
  )
  AND NOT EXISTS (
    SELECT 1 FROM symbolika_mail_messages m
    WHERE m.thread_id = t.id AND m.direction = 'inbound'
  );

-- Локальная папка менеджера нужна для отладки интерфейса до подключения IMAP.
INSERT INTO symbolika_mail_folders (slug, name, imap_name, alias_email, employee, is_shared, sort)
SELECT
  'manager-' || e.id,
  COALESCE(NULLIF(e.full_name, ''), 'Менеджер'),
  'INBOX/' || COALESCE(NULLIF(e.full_name, ''), 'Менеджер'),
  NULL,
  e.id,
  false,
  100 + e.id
FROM employees e
LEFT JOIN directus_users u ON u.id = e.directus_user
LEFT JOIN directus_roles r ON r.id = u.role
WHERE COALESCE(e.is_active, true) = true
  AND (r.name = 'Менеджер' OR lower(COALESCE(e.full_name, '')) LIKE '%дмитр%')
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  employee = EXCLUDED.employee;

DO $$
DECLARE
  inbox_id bigint;
  manager_folder_id bigint;
  sample_customer integer;
  sample_company integer;
  sample_order integer;
  sample_task integer;
  thread_one bigint;
  thread_two bigint;
  thread_three bigint;
BEGIN
  -- Demo messages are opt-in. Production/release installs must start with an
  -- empty mailbox and must never recreate fixtures during an idempotent apply.
  IF current_setting('symbolika.seed_demo_mail', true) IS DISTINCT FROM 'on' THEN
    RETURN;
  END IF;

  SELECT id INTO inbox_id FROM symbolika_mail_folders WHERE slug = 'inbox';
  SELECT id INTO manager_folder_id FROM symbolika_mail_folders WHERE employee IS NOT NULL ORDER BY sort, id LIMIT 1;
  manager_folder_id := COALESCE(manager_folder_id, inbox_id);
  SELECT id, company INTO sample_customer, sample_company FROM customers ORDER BY id LIMIT 1;
  SELECT id INTO sample_order FROM orders ORDER BY id DESC LIMIT 1;
  SELECT id INTO sample_task FROM symbolika_tasks ORDER BY id DESC LIMIT 1;

  INSERT INTO symbolika_mail_threads (
    folder_id, external_thread_id, subject, preview, participants,
    customer_id, company_id, order_id, is_unread, is_starred, last_message_at
  ) VALUES (
    manager_folder_id, 'demo-order-layout', 'Макет и сроки по заказу',
    'Добрый день! Прикладываю обновлённый макет и подтверждаю количество…',
    '[{"name":"Анна Смирнова","email":"anna.client@example.ru"}]'::jsonb,
    sample_customer, sample_company, sample_order, true, true, now() - interval '18 minutes'
  ) ON CONFLICT (folder_id, external_thread_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    company_id = EXCLUDED.company_id,
    order_id = EXCLUDED.order_id
  RETURNING id INTO thread_one;

  INSERT INTO symbolika_mail_messages (
    thread_id, message_id, direction, from_email, from_name, to_emails, subject,
    body_text, attachments, is_read, is_test, sent_at
  ) VALUES
    (thread_one, '<demo-layout-1@symb62.ru>', 'inbound', 'anna.client@example.ru', 'Анна Смирнова',
      '["manager@symb62.ru"]'::jsonb, 'Макет и сроки по заказу',
      E'Добрый день! Подтверждаем количество — 50 штук.\n\nПрикладываю обновлённый макет. Проверьте, пожалуйста, успеваем ли к пятнице?',
      '[{"name":"maket_v3.pdf","size":1843200,"type":"application/pdf"}]'::jsonb, false, true, now() - interval '32 minutes'),
    (thread_one, '<demo-layout-2@symb62.ru>', 'outbound', 'manager@symb62.ru', 'Дмитрий Афонин',
      '["anna.client@example.ru"]'::jsonb, 'Re: Макет и сроки по заказу',
      E'Анна, добрый день! Макет получили, передал его дизайнеру на проверку. По сроку вернусь сегодня.',
      '[]'::jsonb, true, true, now() - interval '24 minutes'),
    (thread_one, '<demo-layout-3@symb62.ru>', 'inbound', 'anna.client@example.ru', 'Анна Смирнова',
      '["manager@symb62.ru"]'::jsonb, 'Re: Макет и сроки по заказу',
      E'Спасибо! Буду ждать подтверждения.', '[]'::jsonb, false, true, now() - interval '18 minutes')
  ON CONFLICT (message_id) DO NOTHING;

  INSERT INTO symbolika_mail_threads (
    folder_id, external_thread_id, subject, preview, participants,
    customer_id, company_id, is_unread, is_starred, last_message_at
  ) VALUES (
    inbox_id, 'demo-new-request', 'Запрос на печать футболок',
    'Нужно напечатать логотип на 30 футболках, заготовки наши…',
    '[{"name":"Илья Воронов","email":"voronov@example.ru"}]'::jsonb,
    NULL, NULL, true, false, now() - interval '2 hours'
  ) ON CONFLICT (folder_id, external_thread_id) DO NOTHING
  RETURNING id INTO thread_two;
  IF thread_two IS NULL THEN
    SELECT id INTO thread_two FROM symbolika_mail_threads WHERE folder_id = inbox_id AND external_thread_id = 'demo-new-request';
  END IF;

  INSERT INTO symbolika_mail_messages (
    thread_id, message_id, direction, from_email, from_name, to_emails, subject,
    body_text, attachments, is_read, is_test, sent_at
  ) VALUES (
    thread_two, '<demo-request-1@symb62.ru>', 'inbound', 'voronov@example.ru', 'Илья Воронов',
    '["start@symb62.ru"]'::jsonb, 'Запрос на печать футболок',
    E'Здравствуйте! Нужно напечатать логотип на 30 чёрных футболках. Заготовки привезём свои. Подскажите стоимость и ближайший срок.',
    '[{"name":"logo.svg","size":24800,"type":"image/svg+xml"}]'::jsonb, false, true, now() - interval '2 hours'
  ) ON CONFLICT (message_id) DO NOTHING;

  INSERT INTO symbolika_mail_threads (
    folder_id, external_thread_id, subject, preview, participants,
    task_id, is_unread, is_starred, last_message_at
  ) VALUES (
    manager_folder_id, 'demo-supplier-invoice', 'Счёт на бумагу и срок поставки',
    'Счёт во вложении. Машина будет в Рязани завтра после 14:00…',
    '[{"name":"Отдел продаж Бумага-Сервис","email":"sales@paper.example.ru"}]'::jsonb,
    sample_task, false, false, now() - interval '1 day'
  ) ON CONFLICT (folder_id, external_thread_id) DO UPDATE SET task_id = EXCLUDED.task_id
  RETURNING id INTO thread_three;

  INSERT INTO symbolika_mail_messages (
    thread_id, message_id, direction, from_email, from_name, to_emails, subject,
    body_text, attachments, is_read, is_test, sent_at
  ) VALUES (
    thread_three, '<demo-invoice-1@symb62.ru>', 'inbound', 'sales@paper.example.ru', 'Отдел продаж Бумага-Сервис',
    '["manager@symb62.ru"]'::jsonb, 'Счёт на бумагу и срок поставки',
    E'Добрый день! Счёт во вложении. Машина будет в Рязани завтра после 14:00. После оплаты пришлите, пожалуйста, платёжное поручение.',
    '[{"name":"schet-1842.pdf","size":326400,"type":"application/pdf"}]'::jsonb, true, true, now() - interval '1 day'
  ) ON CONFLICT (message_id) DO NOTHING;
END $$;

-- The public website is useful in every contractor picker/list and does not
-- expose financial or personal details. Keep existing narrow role grants, but
-- allow the link to be rendered wherever a contractor is visible.
UPDATE directus_permissions
SET fields = fields || ',website_url'
WHERE collection = 'contractors'
  AND action = 'read'
  AND fields <> '*'
  AND position('website_url' in fields) = 0;

-- Gift certificates are cash equivalents. Their balance is changed only by an
-- incoming order payment, under a row lock, so two employees cannot redeem the
-- same balance concurrently.
ALTER TABLE directus_users
  ADD COLUMN IF NOT EXISTS symbolika_theme varchar(32) NOT NULL DEFAULT 'graphite';

UPDATE directus_users
SET symbolika_theme = 'graphite'
WHERE symbolika_theme IS NULL
   OR symbolika_theme NOT IN ('graphite', 'espresso', 'pearl', 'frost');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'directus_users_symbolika_theme_valid'
  ) THEN
    ALTER TABLE directus_users
      ADD CONSTRAINT directus_users_symbolika_theme_valid
      CHECK (symbolika_theme IN ('graphite', 'espresso', 'pearl', 'frost'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION symbolika_generate_gift_certificate_code()
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT 'SYM-' || substr(token, 1, 4) || '-' || substr(token, 5, 4) || '-' || substr(token, 9, 4)
  FROM (SELECT upper(replace(gen_random_uuid()::text, '-', '')) AS token) generated;
$$;

CREATE TABLE IF NOT EXISTS gift_certificates (
  id bigserial PRIMARY KEY,
  code varchar(32) NOT NULL DEFAULT symbolika_generate_gift_certificate_code(),
  nominal_amount numeric(12,2) NOT NULL,
  remaining_amount numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  valid_until date NOT NULL,
  status varchar(24) NOT NULL DEFAULT 'active',
  comment text,
  CONSTRAINT gift_certificates_code_uidx UNIQUE (code),
  CONSTRAINT gift_certificates_nominal_positive CHECK (nominal_amount > 0),
  CONSTRAINT gift_certificates_remaining_valid CHECK (remaining_amount >= 0 AND remaining_amount <= nominal_amount),
  CONSTRAINT gift_certificates_status_valid CHECK (status IN ('active', 'redeemed', 'cancelled'))
);

ALTER TABLE gift_certificates
  ADD COLUMN IF NOT EXISTS customer integer;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'gift_certificates_customer_foreign'
  ) THEN
    ALTER TABLE gift_certificates
      ADD CONSTRAINT gift_certificates_customer_foreign
      FOREIGN KEY (customer) REFERENCES customers(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS gift_certificates_customer_idx
  ON gift_certificates(customer, created_at DESC);

ALTER TABLE order_payments
  ADD COLUMN IF NOT EXISTS gift_certificate bigint;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'order_payments_gift_certificate_foreign'
  ) THEN
    ALTER TABLE order_payments
      ADD CONSTRAINT order_payments_gift_certificate_foreign
      FOREIGN KEY (gift_certificate) REFERENCES gift_certificates(id) ON DELETE RESTRICT;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS gift_certificate_transactions (
  id bigserial PRIMARY KEY,
  gift_certificate bigint NOT NULL REFERENCES gift_certificates(id) ON DELETE RESTRICT,
  "order" integer REFERENCES orders(id) ON DELETE SET NULL,
  payment integer REFERENCES order_payments(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL,
  operation varchar(24) NOT NULL DEFAULT 'redemption',
  created_at timestamptz NOT NULL DEFAULT now(),
  comment text,
  CONSTRAINT gift_certificate_transactions_amount_nonzero CHECK (amount <> 0),
  CONSTRAINT gift_certificate_transactions_operation_valid CHECK (operation IN ('redemption', 'refund'))
);

CREATE INDEX IF NOT EXISTS gift_certificate_transactions_certificate_idx
  ON gift_certificate_transactions(gift_certificate, created_at DESC);
CREATE INDEX IF NOT EXISTS gift_certificate_transactions_order_idx
  ON gift_certificate_transactions("order", created_at DESC);

CREATE OR REPLACE FUNCTION symbolika_prepare_gift_certificate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  spent numeric(12,2);
BEGIN
  NEW.code := upper(regexp_replace(trim(COALESCE(NEW.code, '')), '[^A-Za-z0-9-]', '', 'g'));
  IF NEW.code = '' THEN
    NEW.code := symbolika_generate_gift_certificate_code();
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.remaining_amount := NEW.nominal_amount;
    NEW.status := COALESCE(NULLIF(NEW.status, ''), 'active');
  ELSE
    spent := OLD.nominal_amount - OLD.remaining_amount;
    IF NEW.customer IS DISTINCT FROM OLD.customer AND spent > 0 THEN
      RAISE EXCEPTION 'Клиента использованного сертификата изменять нельзя';
    END IF;
    IF NEW.nominal_amount <> OLD.nominal_amount THEN
      IF spent > 0 THEN
        RAISE EXCEPTION 'Номинал использованного сертификата изменять нельзя';
      END IF;
      NEW.remaining_amount := NEW.nominal_amount;
    ELSIF NEW.remaining_amount <> OLD.remaining_amount AND pg_trigger_depth() = 1 THEN
      RAISE EXCEPTION 'Остаток сертификата изменяется только через оплату заказа';
    END IF;
  END IF;

  IF NEW.status = 'redeemed' AND NEW.remaining_amount > 0 THEN
    NEW.status := 'active';
  ELSIF NEW.remaining_amount = 0 AND NEW.status <> 'cancelled' THEN
    NEW.status := 'redeemed';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_validate_gift_certificate_customer(certificate_id bigint, payment_customer integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  certificate_customer integer;
BEGIN
  SELECT customer INTO certificate_customer
  FROM gift_certificates
  WHERE id = certificate_id
  FOR SHARE;

  IF certificate_customer IS NOT NULL
     AND payment_customer IS DISTINCT FROM certificate_customer THEN
    RAISE EXCEPTION 'Сертификат привязан к другому клиенту';
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_prepare_gift_certificate ON gift_certificates;
CREATE TRIGGER symbolika_prepare_gift_certificate
BEFORE INSERT OR UPDATE ON gift_certificates
FOR EACH ROW
EXECUTE FUNCTION symbolika_prepare_gift_certificate();

CREATE OR REPLACE FUNCTION symbolika_adjust_gift_certificate(certificate_id bigint, spend_delta numeric, operation_date date)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  certificate gift_certificates%ROWTYPE;
  next_remaining numeric(12,2);
BEGIN
  IF certificate_id IS NULL OR COALESCE(spend_delta, 0) = 0 THEN
    RETURN;
  END IF;

  SELECT * INTO certificate
  FROM gift_certificates
  WHERE id = certificate_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Подарочный сертификат не найден';
  END IF;

  IF spend_delta > 0 THEN
    IF certificate.status = 'cancelled' THEN
      RAISE EXCEPTION 'Подарочный сертификат отменён';
    END IF;
    IF certificate.valid_until < GREATEST(COALESCE(operation_date, CURRENT_DATE), CURRENT_DATE) THEN
      RAISE EXCEPTION 'Срок действия подарочного сертификата истёк';
    END IF;
    IF certificate.remaining_amount < spend_delta THEN
      RAISE EXCEPTION 'На подарочном сертификате недостаточно средств';
    END IF;
  END IF;

  next_remaining := LEAST(certificate.nominal_amount, certificate.remaining_amount - spend_delta);
  IF next_remaining < 0 THEN
    RAISE EXCEPTION 'Остаток подарочного сертификата не может быть отрицательным';
  END IF;

  UPDATE gift_certificates
  SET remaining_amount = next_remaining,
      status = CASE
        WHEN certificate.status = 'cancelled' THEN 'cancelled'
        WHEN next_remaining = 0 THEN 'redeemed'
        ELSE 'active'
      END
  WHERE id = certificate_id;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_gift_certificate_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  payment_customer integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.gift_certificate IS NOT NULL THEN
      IF NEW.payment_direction <> 'incoming' OR COALESCE(NEW.amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Сертификат можно применить только к входящей оплате';
      END IF;
      payment_customer := NEW.customer;
      IF payment_customer IS NULL AND NEW."order" IS NOT NULL THEN
        SELECT customer INTO payment_customer FROM orders WHERE id = NEW."order";
      END IF;
      PERFORM symbolika_validate_gift_certificate_customer(NEW.gift_certificate, payment_customer);
      PERFORM symbolika_adjust_gift_certificate(NEW.gift_certificate, NEW.amount, NEW.payment_date);
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.gift_certificate IS NOT NULL THEN
      PERFORM symbolika_adjust_gift_certificate(OLD.gift_certificate, -OLD.amount, OLD.payment_date);
    END IF;
    IF NEW.gift_certificate IS NOT NULL THEN
      IF NEW.payment_direction <> 'incoming' OR COALESCE(NEW.amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Сертификат можно применить только к входящей оплате';
      END IF;
      payment_customer := NEW.customer;
      IF payment_customer IS NULL AND NEW."order" IS NOT NULL THEN
        SELECT customer INTO payment_customer FROM orders WHERE id = NEW."order";
      END IF;
      PERFORM symbolika_validate_gift_certificate_customer(NEW.gift_certificate, payment_customer);
      PERFORM symbolika_adjust_gift_certificate(NEW.gift_certificate, NEW.amount, NEW.payment_date);
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.gift_certificate IS NOT NULL THEN
    PERFORM symbolika_adjust_gift_certificate(OLD.gift_certificate, -OLD.amount, OLD.payment_date);
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_apply_gift_certificate_payment ON order_payments;
CREATE TRIGGER symbolika_apply_gift_certificate_payment
BEFORE INSERT OR UPDATE OF gift_certificate, amount, payment_direction, payment_date OR DELETE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_gift_certificate_payment();

CREATE OR REPLACE FUNCTION symbolika_log_gift_certificate_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.gift_certificate IS NOT NULL THEN
    INSERT INTO gift_certificate_transactions (gift_certificate, "order", payment, amount, operation, comment)
    VALUES (NEW.gift_certificate, NEW."order", NEW.id, NEW.amount, 'redemption', NEW.comment);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.gift_certificate IS NOT NULL THEN
      INSERT INTO gift_certificate_transactions (gift_certificate, "order", payment, amount, operation, comment)
      VALUES (OLD.gift_certificate, OLD."order", NEW.id, -OLD.amount, 'refund', 'Корректировка оплаты');
    END IF;
    IF NEW.gift_certificate IS NOT NULL THEN
      INSERT INTO gift_certificate_transactions (gift_certificate, "order", payment, amount, operation, comment)
      VALUES (NEW.gift_certificate, NEW."order", NEW.id, NEW.amount, 'redemption', NEW.comment);
    END IF;
  ELSIF TG_OP = 'DELETE' AND OLD.gift_certificate IS NOT NULL THEN
    INSERT INTO gift_certificate_transactions (gift_certificate, "order", payment, amount, operation, comment)
    VALUES (OLD.gift_certificate, OLD."order", NULL, -OLD.amount, 'refund', 'Оплата удалена');
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS symbolika_log_gift_certificate_payment ON order_payments;
CREATE TRIGGER symbolika_log_gift_certificate_payment
AFTER INSERT OR UPDATE OF gift_certificate, amount, payment_direction, payment_date OR DELETE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION symbolika_log_gift_certificate_payment();

INSERT INTO directus_collections (
  collection, icon, note, display_template, hidden, singleton, sort, accountability, color, translations
) VALUES
  ('gift_certificates', 'redeem', 'Подарочные сертификаты и доступные остатки.', '{{code}}', true, false, 950, 'all', '#F97316', json_build_array(json_build_object('language','ru-RU','translation','Подарочные сертификаты'))::json),
  ('gift_certificate_transactions', 'receipt_long', 'История использования подарочных сертификатов.', '{{amount}}', true, false, 951, 'all', '#F97316', json_build_array(json_build_object('language','ru-RU','translation','Использование сертификатов'))::json)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  accountability = EXCLUDED.accountability,
  color = EXCLUDED.color,
  translations = EXCLUDED.translations;

DELETE FROM directus_fields
WHERE collection IN ('gift_certificates', 'gift_certificate_transactions')
   OR (collection = 'order_payments' AND field = 'gift_certificate');

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('gift_certificates', 'id', NULL, 'input', NULL, NULL, true, true, 1, 'half', NULL, false, true),
  ('gift_certificates', 'code', NULL, 'input', NULL, NULL, true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Код сертификата'))::json, false, true),
  ('gift_certificates', 'nominal_amount', NULL, 'input', NULL, NULL, false, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Номинал'))::json, true, true),
  ('gift_certificates', 'remaining_amount', NULL, 'input', NULL, NULL, true, false, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Остаток'))::json, false, true),
  ('gift_certificates', 'created_at', 'date-created', 'datetime', NULL, 'datetime', true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Дата создания'))::json, false, true),
  ('gift_certificates', 'valid_until', NULL, 'datetime', '{"includeSeconds":false}'::json, 'datetime', false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Действует до'))::json, true, true),
  ('gift_certificates', 'status', NULL, 'select-dropdown', '{"choices":[{"text":"Активен","value":"active"},{"text":"Погашен","value":"redeemed"},{"text":"Отменён","value":"cancelled"}]}'::json, 'labels', false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Статус'))::json, true, true),
  ('gift_certificates', 'comment', NULL, 'input-multiline', NULL, NULL, false, false, 8, 'full', json_build_array(json_build_object('language','ru-RU','translation','Комментарий'))::json, false, true),
  ('gift_certificates', 'customer', 'm2o', 'select-dropdown-m2o', '{"template":"{{name}}"}'::json, 'related-values', false, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation','Клиент'))::json, false, true),
  ('gift_certificate_transactions', 'id', NULL, 'input', NULL, NULL, true, true, 1, 'half', NULL, false, true),
  ('gift_certificate_transactions', 'gift_certificate', 'm2o', 'select-dropdown-m2o', '{"template":"{{code}}"}'::json, 'related-values', true, false, 2, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сертификат'))::json, true, true),
  ('gift_certificate_transactions', 'order', 'm2o', 'select-dropdown-m2o', '{"template":"{{order_number}}"}'::json, 'related-values', true, false, 3, 'half', json_build_array(json_build_object('language','ru-RU','translation','Заказ'))::json, false, true),
  ('gift_certificate_transactions', 'payment', 'm2o', 'select-dropdown-m2o', NULL, 'related-values', true, true, 4, 'half', json_build_array(json_build_object('language','ru-RU','translation','Оплата'))::json, false, true),
  ('gift_certificate_transactions', 'amount', NULL, 'input', NULL, NULL, true, false, 5, 'half', json_build_array(json_build_object('language','ru-RU','translation','Сумма операции'))::json, true, true),
  ('gift_certificate_transactions', 'operation', NULL, 'input', NULL, 'labels', true, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Операция'))::json, true, true),
  ('gift_certificate_transactions', 'created_at', 'date-created', 'datetime', NULL, 'datetime', true, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Дата'))::json, false, true),
  ('gift_certificate_transactions', 'comment', NULL, 'input-multiline', NULL, NULL, true, false, 8, 'full', json_build_array(json_build_object('language','ru-RU','translation','Комментарий'))::json, false, true),
  ('order_payments', 'gift_certificate', 'm2o', 'select-dropdown-m2o', '{"template":"{{code}}"}'::json, 'related-values', true, false, 20, 'half', json_build_array(json_build_object('language','ru-RU','translation','Подарочный сертификат'))::json, false, true);

DELETE FROM directus_relations
WHERE (many_collection = 'order_payments' AND many_field = 'gift_certificate')
   OR (many_collection = 'gift_certificates' AND many_field = 'customer')
   OR (many_collection = 'gift_certificate_transactions' AND many_field IN ('gift_certificate', 'order', 'payment'));

INSERT INTO directus_relations (many_collection, many_field, one_collection, one_deselect_action) VALUES
  ('order_payments', 'gift_certificate', 'gift_certificates', 'nullify'),
  ('gift_certificates', 'customer', 'customers', 'nullify'),
  ('gift_certificate_transactions', 'gift_certificate', 'gift_certificates', 'nullify'),
  ('gift_certificate_transactions', 'order', 'orders', 'nullify'),
  ('gift_certificate_transactions', 'payment', 'order_payments', 'nullify');

UPDATE directus_permissions
SET fields = fields || ',gift_certificate'
WHERE collection = 'order_payments'
  AND action IN ('read', 'create', 'update')
  AND fields <> '*'
  AND position('gift_certificate' in fields) = 0;

DELETE FROM directus_permissions
WHERE collection IN ('gift_certificates', 'gift_certificate_transactions');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT collection_name, action_name, '{}'::json, NULL, NULL, '*', p.id
FROM directus_policies p
CROSS JOIN (VALUES
  ('gift_certificates', 'read'),
  ('gift_certificates', 'create'),
  ('gift_certificates', 'update'),
  ('gift_certificate_transactions', 'read')
) permissions(collection_name, action_name)
WHERE p.admin_access = true;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('gift_certificates', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('gift_certificates', 'create', '{}'::json, NULL, '{"status":"active"}'::json, 'nominal_amount,valid_until,status,comment,customer', '00000000-0000-4000-8000-000000000205'),
  ('gift_certificates', 'update', '{}'::json, NULL, NULL, 'valid_until,status,comment,customer', '00000000-0000-4000-8000-000000000205'),
  ('gift_certificate_transactions', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('gift_certificates', 'read', '{}'::json, NULL, NULL, 'id,code,nominal_amount,remaining_amount,created_at,valid_until,status,comment,customer', '00000000-0000-4000-8000-000000000201'),
  ('gift_certificate_transactions', 'read', '{}'::json, NULL, NULL, 'id,gift_certificate,order,amount,operation,created_at,comment', '00000000-0000-4000-8000-000000000201'),
  ('gift_certificates', 'read', '{}'::json, NULL, NULL, 'id,code,nominal_amount,remaining_amount,created_at,valid_until,status,comment,customer', '00000000-0000-4000-8000-000000000202'),
  ('gift_certificates', 'read', '{}'::json, NULL, NULL, 'id,code,nominal_amount,remaining_amount,created_at,valid_until,status,comment,customer', '00000000-0000-4000-8000-000000000203');

-- Opening balances for imported/new customers and companies. The editable
-- fields are an import-friendly source; one generated customer operation is
-- the accounting source used by reconciliation and balance calculations.
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS opening_balance_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS opening_balance_direction varchar(32) NOT NULL DEFAULT 'customer_owes_us',
  ADD COLUMN IF NOT EXISTS opening_balance_date date NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN IF NOT EXISTS opening_balance_comment text;

ALTER TABLE customer_companies
  ADD COLUMN IF NOT EXISTS opening_balance_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS opening_balance_direction varchar(32) NOT NULL DEFAULT 'customer_owes_us',
  ADD COLUMN IF NOT EXISTS opening_balance_date date NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN IF NOT EXISTS opening_balance_comment text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'customers_opening_balance_amount_valid') THEN
    ALTER TABLE customers ADD CONSTRAINT customers_opening_balance_amount_valid CHECK (opening_balance_amount >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'customers_opening_balance_direction_valid') THEN
    ALTER TABLE customers ADD CONSTRAINT customers_opening_balance_direction_valid
      CHECK (opening_balance_direction IN ('customer_owes_us', 'we_owe_customer'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'companies_opening_balance_amount_valid') THEN
    ALTER TABLE customer_companies ADD CONSTRAINT companies_opening_balance_amount_valid CHECK (opening_balance_amount >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'companies_opening_balance_direction_valid') THEN
    ALTER TABLE customer_companies ADD CONSTRAINT companies_opening_balance_direction_valid
      CHECK (opening_balance_direction IN ('customer_owes_us', 'we_owe_customer'));
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS customer_operations_opening_customer_uidx
  ON customer_operations(customer)
  WHERE operation_type = 'opening_balance' AND customer IS NOT NULL AND customer_company IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS customer_operations_opening_company_uidx
  ON customer_operations(customer_company)
  WHERE operation_type = 'opening_balance' AND customer_company IS NOT NULL AND customer IS NULL;

CREATE OR REPLACE FUNCTION symbolika_sync_customer_opening_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  operation_description text;
BEGIN
  NEW.opening_balance_amount := round(COALESCE(NEW.opening_balance_amount, 0), 2);
  NEW.opening_balance_direction := COALESCE(NULLIF(NEW.opening_balance_direction, ''), 'customer_owes_us');
  NEW.opening_balance_date := COALESCE(NEW.opening_balance_date, CURRENT_DATE);

  IF NEW.opening_balance_amount < 0 THEN
    RAISE EXCEPTION 'Сумма начального остатка не может быть отрицательной: выберите направление долга';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_prepare_customer_opening_balance ON customers;
CREATE TRIGGER symbolika_prepare_customer_opening_balance
BEFORE INSERT OR UPDATE OF opening_balance_amount, opening_balance_direction, opening_balance_date, opening_balance_comment
ON customers
FOR EACH ROW EXECUTE FUNCTION symbolika_sync_customer_opening_balance();

DROP TRIGGER IF EXISTS symbolika_prepare_company_opening_balance ON customer_companies;
CREATE TRIGGER symbolika_prepare_company_opening_balance
BEFORE INSERT OR UPDATE OF opening_balance_amount, opening_balance_direction, opening_balance_date, opening_balance_comment
ON customer_companies
FOR EACH ROW EXECUTE FUNCTION symbolika_sync_customer_opening_balance();

CREATE OR REPLACE FUNCTION symbolika_apply_customer_opening_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  operation_description text;
BEGIN
  operation_description := COALESCE(NULLIF(btrim(NEW.opening_balance_comment), ''), 'Начальный остаток при переносе данных');
  IF NEW.opening_balance_amount > 0 THEN
    INSERT INTO customer_operations (
      operation_date, operation_type, direction, amount, customer, customer_company,
      manager_employee, status, description, reference
    ) VALUES (
      NEW.opening_balance_date, 'opening_balance', NEW.opening_balance_direction,
      NEW.opening_balance_amount, NEW.id, NULL, NEW.manager, 'confirmed',
      operation_description, 'opening-balance:customer:' || NEW.id
    )
    ON CONFLICT (customer)
      WHERE operation_type = 'opening_balance' AND customer IS NOT NULL AND customer_company IS NULL
    DO UPDATE SET
      operation_date = EXCLUDED.operation_date,
      direction = EXCLUDED.direction,
      amount = EXCLUDED.amount,
      manager_employee = EXCLUDED.manager_employee,
      status = 'confirmed',
      description = EXCLUDED.description,
      reference = EXCLUDED.reference;
  ELSE
    DELETE FROM customer_operations
    WHERE operation_type = 'opening_balance'
      AND customer = NEW.id
      AND customer_company IS NULL;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_apply_company_opening_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  operation_description text;
BEGIN
  operation_description := COALESCE(NULLIF(btrim(NEW.opening_balance_comment), ''), 'Начальный остаток при переносе данных');
  IF NEW.opening_balance_amount > 0 THEN
    INSERT INTO customer_operations (
      operation_date, operation_type, direction, amount, customer, customer_company,
      manager_employee, status, description, reference
    ) VALUES (
      NEW.opening_balance_date, 'opening_balance', NEW.opening_balance_direction,
      NEW.opening_balance_amount, NULL, NEW.id, NEW.manager, 'confirmed',
      operation_description, 'opening-balance:company:' || NEW.id
    )
    ON CONFLICT (customer_company)
      WHERE operation_type = 'opening_balance' AND customer_company IS NOT NULL AND customer IS NULL
    DO UPDATE SET
      operation_date = EXCLUDED.operation_date,
      direction = EXCLUDED.direction,
      amount = EXCLUDED.amount,
      manager_employee = EXCLUDED.manager_employee,
      status = 'confirmed',
      description = EXCLUDED.description,
      reference = EXCLUDED.reference;
  ELSE
    DELETE FROM customer_operations
    WHERE operation_type = 'opening_balance'
      AND customer_company = NEW.id
      AND customer IS NULL;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_apply_customer_opening_balance ON customers;
CREATE TRIGGER symbolika_apply_customer_opening_balance
AFTER INSERT OR UPDATE OF opening_balance_amount, opening_balance_direction, opening_balance_date, opening_balance_comment, manager
ON customers
FOR EACH ROW EXECUTE FUNCTION symbolika_apply_customer_opening_balance();

DROP TRIGGER IF EXISTS symbolika_apply_company_opening_balance ON customer_companies;
CREATE TRIGGER symbolika_apply_company_opening_balance
AFTER INSERT OR UPDATE OF opening_balance_amount, opening_balance_direction, opening_balance_date, opening_balance_comment, manager
ON customer_companies
FOR EACH ROW EXECUTE FUNCTION symbolika_apply_company_opening_balance();

DELETE FROM directus_fields
WHERE collection IN ('customers', 'customer_companies')
  AND field IN ('opening_balance_amount', 'opening_balance_direction', 'opening_balance_date', 'opening_balance_comment');

INSERT INTO directus_fields (
  collection, field, interface, options, display, readonly, hidden, sort, width,
  translations, note, required, searchable
) VALUES
  ('customers', 'opening_balance_amount', 'input', '{"min":0,"step":0.01}'::json, NULL, false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Начальный остаток'))::json, 'Сумма взаиморасчетов на дату переноса. Укажите направление долга в соседнем поле.', false, true),
  ('customers', 'opening_balance_direction', 'select-dropdown', '{"choices":[{"text":"Клиент должен нам","value":"customer_owes_us"},{"text":"Мы должны клиенту / аванс клиента","value":"we_owe_customer"}]}'::json, 'labels', false, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation','Направление начального остатка'))::json, NULL, false, true),
  ('customers', 'opening_balance_date', 'datetime', '{"includeSeconds":false,"use24":true}'::json, 'datetime', false, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation','Начальный остаток на дату'))::json, NULL, false, true),
  ('customers', 'opening_balance_comment', 'input', NULL, NULL, false, false, 10, 'half', json_build_array(json_build_object('language','ru-RU','translation','Комментарий к начальному остатку'))::json, NULL, false, true),
  ('customer_companies', 'opening_balance_amount', 'input', '{"min":0,"step":0.01}'::json, NULL, false, false, 6, 'half', json_build_array(json_build_object('language','ru-RU','translation','Начальный остаток'))::json, 'Сумма взаиморасчетов на дату переноса. Укажите направление долга в соседнем поле.', false, true),
  ('customer_companies', 'opening_balance_direction', 'select-dropdown', '{"choices":[{"text":"Компания должна нам","value":"customer_owes_us"},{"text":"Мы должны компании / аванс компании","value":"we_owe_customer"}]}'::json, 'labels', false, false, 7, 'half', json_build_array(json_build_object('language','ru-RU','translation','Направление начального остатка'))::json, NULL, false, true),
  ('customer_companies', 'opening_balance_date', 'datetime', '{"includeSeconds":false,"use24":true}'::json, 'datetime', false, false, 8, 'half', json_build_array(json_build_object('language','ru-RU','translation','Начальный остаток на дату'))::json, NULL, false, true),
  ('customer_companies', 'opening_balance_comment', 'input', NULL, NULL, false, false, 9, 'half', json_build_array(json_build_object('language','ru-RU','translation','Комментарий к начальному остатку'))::json, NULL, false, true);

UPDATE directus_fields
SET options = '{"choices":[{"text":"Начальный остаток","value":"opening_balance"},{"text":"Покупка на маркетплейсе","value":"marketplace_purchase"},{"text":"Выдача / снятие наличных","value":"cash_withdrawal"},{"text":"Прочая просьба","value":"other"}]}'::json
WHERE collection = 'customer_operations' AND field = 'operation_type';

-- Office managers own customer relationships in the same way as managers:
-- their calculations, reconciliation and client operations remain scoped by
-- the employee linked to the current Directus user.
DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000202'
  AND collection IN ('customer_operations', 'manager_finance_summary');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('customer_operations','read','{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000202'),
  ('customer_operations','create','{}'::json,'{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,'operation_date,operation_type,direction,amount,customer,customer_company,manager_employee,status,description,reference','00000000-0000-4000-8000-000000000202'),
  ('customer_operations','update','{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,'{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,NULL,'operation_date,operation_type,direction,amount,customer,customer_company,status,description,reference','00000000-0000-4000-8000-000000000202'),
  ('manager_finance_summary','read','{"directus_user":{"_eq":"$CURRENT_USER"}}'::json,NULL,NULL,'id,employee,employee_name,order_percent,orders_count,orders_sum,paid_orders_sum,unpaid_orders_sum,commission_total,commission_accrued,commission_expected,commission_paid,commission_to_pay','00000000-0000-4000-8000-000000000202');

UPDATE directus_permissions
SET fields = fields || ',opening_balance_amount,opening_balance_direction,opening_balance_date,opening_balance_comment'
WHERE collection IN ('customers', 'customer_companies')
  AND action IN ('read', 'create', 'update')
  AND fields IS NOT NULL
  AND fields <> '*'
  AND position('opening_balance_amount' in fields) = 0;

-- A manager dashboard, reconciliation and event feed are always personal.
-- The separate office policy may expose office issue collections, but must not
-- widen personal finance or history to every order currently in the office.
DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000203'
  AND collection IN ('customer_reconciliation', 'customer_reconciliation_items', 'symbolika_event_feed');

UPDATE directus_permissions
SET permissions = '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json
WHERE collection IN ('customer_reconciliation', 'customer_reconciliation_items')
  AND action = 'read'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

UPDATE directus_permissions
SET permissions = '{"_or":[{"access_manager_user":{"_eq":"$CURRENT_USER"}},{"_and":[{"order_id":{"_null":true}},{"task_assigned_user":{"_eq":"$CURRENT_USER"}}]},{"_and":[{"order_id":{"_null":true}},{"task_created_user":{"_eq":"$CURRENT_USER"}}]}]}'::json
WHERE collection = 'symbolika_event_feed'
  AND action = 'read'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

-- Legacy summary tables used by the custom order list did not retain the
-- manager identity. Persist it on every refresh so Directus can enforce the
-- same ownership rule as the source orders table.
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS manager_employee integer;
ALTER TABLE orders_overview ADD COLUMN IF NOT EXISTS access_manager_user uuid;
ALTER TABLE orders_overview_items ADD COLUMN IF NOT EXISTS access_manager_user uuid;

DO $$
DECLARE
  summary_table text;
BEGIN
  FOREACH summary_table IN ARRAY ARRAY[
    'orders_due_urgent', 'orders_due_today', 'orders_due_this_week',
    'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS manager_employee integer', summary_table);
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS access_manager_user uuid', summary_table);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_scope_order_summary()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT o.manager_employee, e.directus_user
    INTO NEW.manager_employee, NEW.access_manager_user
  FROM orders o
  LEFT JOIN employees e ON e.id = o.manager_employee
  WHERE o.id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION symbolika_scope_order_summary_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT e.directus_user
    INTO NEW.access_manager_user
  FROM orders o
  LEFT JOIN employees e ON e.id = o.manager_employee
  WHERE o.id = NEW.orders_overview;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_scope_orders_overview ON orders_overview;
CREATE TRIGGER symbolika_scope_orders_overview
BEFORE INSERT OR UPDATE OF id ON orders_overview
FOR EACH ROW EXECUTE FUNCTION symbolika_scope_order_summary();

DROP TRIGGER IF EXISTS symbolika_scope_orders_overview_items ON orders_overview_items;
CREATE TRIGGER symbolika_scope_orders_overview_items
BEFORE INSERT OR UPDATE OF orders_overview ON orders_overview_items
FOR EACH ROW EXECUTE FUNCTION symbolika_scope_order_summary_item();

DO $$
DECLARE
  summary_table text;
BEGIN
  FOREACH summary_table IN ARRAY ARRAY[
    'orders_due_urgent', 'orders_due_today', 'orders_due_this_week',
    'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS symbolika_scope_%I ON %I', summary_table, summary_table);
    EXECUTE format(
      'CREATE TRIGGER symbolika_scope_%I BEFORE INSERT OR UPDATE OF id ON %I FOR EACH ROW EXECUTE FUNCTION symbolika_scope_order_summary()',
      summary_table, summary_table
    );
  END LOOP;
END;
$$;

UPDATE orders_overview summary
SET manager_employee = o.manager_employee,
    access_manager_user = e.directus_user
FROM orders o
LEFT JOIN employees e ON e.id = o.manager_employee
WHERE o.id = summary.id;

UPDATE orders_overview_items summary
SET access_manager_user = e.directus_user
FROM orders o
LEFT JOIN employees e ON e.id = o.manager_employee
WHERE o.id = summary.orders_overview;

DO $$
DECLARE
  summary_table text;
BEGIN
  FOREACH summary_table IN ARRAY ARRAY[
    'orders_due_urgent', 'orders_due_today', 'orders_due_this_week',
    'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month'
  ]
  LOOP
    EXECUTE format(
      'UPDATE %I summary SET manager_employee = o.manager_employee, access_manager_user = e.directus_user FROM orders o LEFT JOIN employees e ON e.id = o.manager_employee WHERE o.id = summary.id',
      summary_table
    );
  END LOOP;
END;
$$;

DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000203'
  AND collection IN (
    'orders_overview', 'orders_overview_items', 'orders_due_urgent', 'orders_due_today',
    'orders_due_this_week', 'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month'
  );

UPDATE directus_permissions
SET permissions = '{"access_manager_user":{"_eq":"$CURRENT_USER"}}'::json
WHERE action = 'read'
  AND collection IN (
    'orders_overview', 'orders_overview_items', 'orders_due_urgent', 'orders_due_today',
    'orders_due_this_week', 'orders_due_next_week', 'orders_due_this_month', 'orders_due_next_month'
  )
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

-- Manager role consolidation.
-- "Офис-менеджер" remains an employee position, but is no longer a Directus role.
-- Existing office-manager accounts are moved to the regular manager role. Managers
-- receive the shared office policy so every manager can accept payments and issue
-- any order that is ready for pickup in the office.
DO $$
DECLARE
  manager_role_id uuid;
  office_manager_role_id uuid;
  office_policy_id uuid := '00000000-0000-4000-8000-000000000203'::uuid;
BEGIN
  SELECT id INTO manager_role_id
  FROM directus_roles
  WHERE name = 'Менеджер'
  ORDER BY id
  LIMIT 1;

  SELECT id INTO office_manager_role_id
  FROM directus_roles
  WHERE name = 'Офис-менеджер'
  ORDER BY id
  LIMIT 1;

  IF manager_role_id IS NULL THEN
    RAISE EXCEPTION 'Cannot consolidate roles: Directus role "Менеджер" was not found';
  END IF;

  IF office_manager_role_id IS NOT NULL THEN
    UPDATE directus_users
    SET role = manager_role_id
    WHERE role = office_manager_role_id;

    UPDATE directus_roles
    SET parent = manager_role_id
    WHERE parent = office_manager_role_id;

    UPDATE directus_settings
    SET public_registration_role = manager_role_id
    WHERE public_registration_role = office_manager_role_id;

    DELETE FROM directus_roles
    WHERE id = office_manager_role_id;
  END IF;

  IF EXISTS (SELECT 1 FROM directus_policies WHERE id = office_policy_id)
     AND NOT EXISTS (
       SELECT 1
       FROM directus_access
       WHERE role = manager_role_id
         AND policy = office_policy_id
         AND "user" IS NULL
     ) THEN
    INSERT INTO directus_access (id, role, "user", policy, sort)
    VALUES (gen_random_uuid(), manager_role_id, NULL, office_policy_id, 2);
  END IF;
END;
$$;

-- Manager ownership on order items is stored directly in manager_employee.
-- Use that direct relation for permission checks: traversing through
-- orders_items.order.manager_employee can be rejected by Directus when the
-- manager also has the shared office policy, even for the manager's own item.
UPDATE directus_permissions
SET permissions = '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json
WHERE collection = 'orders_items'
  AND action IN ('read', 'update')
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

-- The create hook copies the manager from the parent order before Directus
-- builds the response. Allow this server-controlled field in create payloads;
-- the database trigger overwrites it as well, so clients cannot spoof ownership.
UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'manager_employee')
WHERE collection = 'orders_items'
  AND action = 'create'
  AND fields IS NOT NULL
  AND fields <> '*'
  AND NOT ('manager_employee' = ANY(string_to_array(fields, ',')))
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

-- Coordinated cancellation: managers request it on the item, the workshop
-- confirms it with the final production status "Отменен".
UPDATE directus_fields
SET options = jsonb_set(
  COALESCE(options::jsonb, '{}'::jsonb),
  '{choices}',
  jsonb_build_array(
    jsonb_build_object('text', 'Новый', 'value', 'new'),
    jsonb_build_object('text', 'Согласование', 'value', 'approval'),
    jsonb_build_object('text', 'Доработка макета', 'value', 'layout_revision'),
    jsonb_build_object('text', 'Отправлен в работу', 'value', 'sent_to_work'),
    jsonb_build_object('text', 'В работе', 'value', 'in_work'),
    jsonb_build_object('text', 'Отмена запрошена', 'value', 'cancellation_requested'),
    jsonb_build_object('text', 'Готов', 'value', 'ready'),
    jsonb_build_object('text', 'Доставлен', 'value', 'delivered'),
    jsonb_build_object('text', 'Отменен', 'value', 'cancelled')
  ),
  true
)::json
WHERE collection IN ('orders_items', 'production_work', 'screen_printing_work')
  AND field = 'item_status';

-- Canonical permissions for employees who combine workshop work with their
-- own sales. Directus combines permission rows from the same policy, so old
-- overlapping rows could expose a foreign order through orders/orders_items.
-- Own orders use the regular manager boundary. Foreign routed positions are
-- available only through the narrow work collections below.
DELETE FROM directus_permissions
WHERE policy IN (
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206'
  )
  AND collection IN (
    'orders', 'orders_items', 'production_work', 'screen_printing_work'
  );

WITH workshop_sales_policies(policy) AS (
  VALUES
    ('00000000-0000-4000-8000-000000000204'::uuid),
    ('00000000-0000-4000-8000-000000000206'::uuid)
), own_order_permissions(collection, action, permissions, validation, presets, fields) AS (
  VALUES
    ('orders', 'create', '{}'::json, NULL::json, NULL::json,
      'date,deadline,customer,customer_company,order_status,comment,shipping_method,shipping_comment,payment_type,order_items,payment_on_receipt,office_status,order_number,manager_employee'),
    ('orders', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL::json, NULL::json,
      'id,order_number,date,deadline,manager_employee,customer,customer_company,order_status,comment,shipping_method,shipping_comment,order_sum,paid_amount,payment_due,office_payment_due,payment_type,order_items,payments,payment_on_receipt,office_status'),
    ('orders', 'update', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL::json, NULL::json,
      'date,deadline,customer,customer_company,order_status,comment,shipping_method,shipping_comment,payment_type,order_items,payment_on_receipt,office_status'),
    ('orders_items', 'create', '{}'::json,
      '{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}}'::json,
      '{"production_status":7}'::json,
      'order,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url,manager_employee'),
    ('orders_items', 'read', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL::json, NULL::json,
      'id,order,order_link,product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,production_status,deadline,production_comment,technical_task_text,manager_employee,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url,layout_revision_url_snapshot,layout_disk_path,layout_disk_name,layout_disk_size,layout_disk_mime_type,layout_disk_uploaded_at,layout_preview_url,layout_preview_disk_path,layout_preview_disk_name,layout_preview_disk_size,layout_preview_disk_mime_type,layout_preview_uploaded_at'),
    ('orders_items', 'update', '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json,
      '{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}'::json, NULL::json,
      'product_name,quantity,price_per_unit,order_sum,blank_source,blank_ordered,product_category,product_subcategory,application_method,item_status,deadline,production_comment,technical_task_text,shipping_method,office_status,url,contractor_1,contractor_1_cost,needs_designer_help,designer_comment,designer_source_url'),
    ('orders_items', 'delete',
      '{"_and":[{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"item_status":{"_in":["new","approval"]}}]}'::json,
      NULL::json, NULL::json, '*')
)
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT permission.collection, permission.action, permission.permissions,
       permission.validation, permission.presets, permission.fields, policy.policy
FROM workshop_sales_policies policy
CROSS JOIN own_order_permissions permission;

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('production_work', 'read', '{}'::json, NULL, NULL,
    'id,order,order_number,order_link,customer_name,customer_company_name,manager_employee,product_name,quantity,date,deadline,item_status,office_status,technical_task_text,production_comment,url,production_status',
    '00000000-0000-4000-8000-000000000204'),
  ('production_work', 'update', '{}'::json, NULL, NULL,
    'production_status,production_comment',
    '00000000-0000-4000-8000-000000000204'),
  ('screen_printing_work', 'read', '{}'::json, NULL, NULL,
    'id,order,order_number,order_link,customer_name,customer_company_name,manager_employee,product_name,quantity,date,deadline,item_status,office_status,technical_task_text,production_comment,url,production_status',
    '00000000-0000-4000-8000-000000000206'),
  ('screen_printing_work', 'update', '{}'::json, NULL, NULL,
    'production_status,production_comment',
    '00000000-0000-4000-8000-000000000206');

-- Counterparty proposals. Operational users may submit a compact counterparty
-- card, but only an administrator can approve it for regular dictionaries,
-- routing and procurement supplier pickers.
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS approval_status varchar(32) NOT NULL DEFAULT 'approved';
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS proposed_by_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS proposed_by_user uuid REFERENCES directus_users(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS approved_by_employee integer REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS approval_comment text;

UPDATE contractors
SET approval_status = 'approved'
WHERE approval_status IS NULL
   OR approval_status NOT IN ('pending', 'approved', 'rejected');

UPDATE contractors
SET supplier_kind = 'contractor'
WHERE supplier_kind IS NULL
   OR supplier_kind NOT IN ('contractor', 'blank_supplier', 'consumables_supplier', 'both');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contractors_approval_status_valid'
  ) THEN
    ALTER TABLE contractors
      ADD CONSTRAINT contractors_approval_status_valid
      CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contractors_supplier_kind_valid'
  ) THEN
    ALTER TABLE contractors
      ADD CONSTRAINT contractors_supplier_kind_valid
      CHECK (supplier_kind IN ('contractor', 'blank_supplier', 'consumables_supplier', 'both'));
  END IF;
END $$;

DELETE FROM directus_fields
WHERE collection = 'contractors'
  AND field IN ('approval_status', 'proposed_by_employee', 'proposed_by_user', 'approved_by_employee', 'approved_at', 'approval_comment');

INSERT INTO directus_fields (
  collection, field, special, interface, display, readonly, hidden, width, translations
) VALUES
  ('contractors', 'approval_status', NULL, 'select-dropdown', 'labels', false, false, 'half',
    json_build_array(json_build_object('language','ru-RU','translation','Статус согласования'))::json),
  ('contractors', 'proposed_by_employee', 'm2o', 'select-dropdown-m2o', 'related-values', true, false, 'half',
    json_build_array(json_build_object('language','ru-RU','translation','Предложил сотрудник'))::json),
  ('contractors', 'proposed_by_user', 'm2o', 'select-dropdown-m2o', 'related-values', true, true, 'half',
    json_build_array(json_build_object('language','ru-RU','translation','Предложил пользователь'))::json),
  ('contractors', 'approved_by_employee', 'm2o', 'select-dropdown-m2o', 'related-values', true, false, 'half',
    json_build_array(json_build_object('language','ru-RU','translation','Согласовал сотрудник'))::json),
  ('contractors', 'approved_at', NULL, 'datetime', 'datetime', true, false, 'half',
    json_build_array(json_build_object('language','ru-RU','translation','Дата согласования'))::json),
  ('contractors', 'approval_comment', NULL, 'input-multiline', 'formatted-value', false, false, 'full',
    json_build_array(json_build_object('language','ru-RU','translation','Комментарий согласования'))::json);

UPDATE directus_fields
SET options = '{"choices":[{"text":"На согласовании","value":"pending"},{"text":"Одобрен","value":"approved"},{"text":"Отклонён","value":"rejected"}]}'::json
WHERE collection = 'contractors' AND field = 'approval_status';

DELETE FROM directus_relations
WHERE many_collection = 'contractors'
  AND many_field IN ('proposed_by_employee', 'proposed_by_user', 'approved_by_employee');

INSERT INTO directus_relations (many_collection, many_field, one_collection, one_deselect_action) VALUES
  ('contractors', 'proposed_by_employee', 'employees', 'nullify'),
  ('contractors', 'proposed_by_user', 'directus_users', 'nullify'),
  ('contractors', 'approved_by_employee', 'employees', 'nullify');

DELETE FROM directus_permissions
WHERE policy = '00000000-0000-4000-8000-000000000209'
  AND collection = 'contractors';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('contractors', 'read', '{}'::json, NULL, NULL,
    'id,name,contact_name,phone,email,website_url,city,supplier_kind,supplies_textile_blanks,supplies_merch_blanks,approval_status,proposed_by_employee,comment',
    '00000000-0000-4000-8000-000000000209'),
  ('contractors', 'create', '{}'::json,
    '{"_and":[{"approval_status":{"_eq":"pending"}},{"proposed_by_user":{"_eq":"$CURRENT_USER"}}]}'::json,
    '{"approval_status":"pending","proposed_by_user":"$CURRENT_USER"}'::json,
    'name,contact_name,phone,email,website_url,city,supplier_kind,supplies_textile_blanks,supplies_merch_blanks,comment,approval_status,proposed_by_employee,proposed_by_user',
    '00000000-0000-4000-8000-000000000209');

-- Existing narrow role grants must include the classification and approval
-- fields used by the shared procurement form.
UPDATE directus_permissions
SET fields = fields || ',supplier_kind,approval_status,proposed_by_employee'
WHERE collection = 'contractors'
  AND action = 'read'
  AND fields <> '*'
  AND position('supplier_kind' in fields) = 0;

UPDATE directus_fields
SET interface = 'select-dropdown',
    options = json_build_object('choices', json_build_array(
      json_build_object('text', 'Производство', 'value', 'production'),
      json_build_object('text', 'Шелкография', 'value', 'screen_printing'),
      json_build_object('text', 'Офис', 'value', 'office'),
      json_build_object('text', 'Общее', 'value', 'general')
    ))::json
WHERE collection = 'procurement_requests'
  AND field = 'section';

-- Multiple eligible contractors per product route. The selected supplier and
-- executor are still stored in orders_items.contractor_1/contractor_2 so the
-- existing costing, production and settlement layers remain compatible.
CREATE TABLE IF NOT EXISTS contractor_capabilities (
  id serial PRIMARY KEY,
  contractor integer NOT NULL REFERENCES contractors(id) ON DELETE CASCADE,
  capability_type varchar(32) NOT NULL,
  product_category integer NOT NULL REFERENCES product_categories(id) ON DELETE CASCADE,
  product_subcategory integer REFERENCES product_subcategories(id) ON DELETE CASCADE,
  application_method integer REFERENCES product_application_methods(id) ON DELETE CASCADE,
  priority integer NOT NULL DEFAULT 100,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT contractor_capabilities_type_valid
    CHECK (capability_type IN ('executor', 'blank_supplier'))
);

CREATE UNIQUE INDEX IF NOT EXISTS contractor_capabilities_unique_route
  ON contractor_capabilities (
    contractor,
    capability_type,
    product_category,
    COALESCE(product_subcategory, 0),
    COALESCE(application_method, 0)
  );

-- Migrate current routing without touching existing order items.
INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, product_subcategory,
  application_method, priority, is_active
)
SELECT DISTINCT
  COALESCE(rule.contractor_2, rule.contractor_1), 'executor',
  rule.product_category, rule.product_subcategory, rule.application_method,
  COALESCE(rule.priority, 100), COALESCE(rule.is_active, true)
FROM product_routing_rules rule
WHERE COALESCE(rule.contractor_2, rule.contractor_1) IS NOT NULL
  AND rule.product_category IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, priority, is_active
)
SELECT DISTINCT contractor.id, 'blank_supplier', category.id, 100, true
FROM contractors contractor
CROSS JOIN product_categories category
WHERE COALESCE(contractor.approval_status, 'approved') = 'approved'
  AND (
    (COALESCE(contractor.supplies_textile_blanks, false) AND category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%')
    OR
    (COALESCE(contractor.supplies_merch_blanks, false) AND category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%')
    OR
    (COALESCE(contractor.supplies_merch_blanks, false) AND category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%')
  )
ON CONFLICT DO NOTHING;

-- Internal screen-printing is an executor for every category-specific
-- screen-printing method, including packaging.
INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, application_method,
  priority, is_active
)
SELECT DISTINCT
  contractor.id, 'executor', method.category, method.id, 10, true
FROM contractors contractor
JOIN product_application_methods method ON method.category IS NOT NULL
WHERE COALESCE(contractor.approval_status, 'approved') = 'approved'
  AND contractor.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
  AND method.name ILIKE U&'%\0448\0435\043b\043a\043e\0433\0440\0430\0444%'
  AND COALESCE(method.is_active, true)
ON CONFLICT DO NOTHING;

-- Fixed internal routes by application method. These routes are intentionally
-- authoritative across product categories: the manager must not have to pick
-- an executor for work that is always performed by an internal department.
-- Keep this seed separate from the historical category routes above so newly
-- added categories/method records receive the same routing on every deploy.
WITH fixed_methods(method_name, contractor_name) AS (VALUES
  (U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c', U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  (U&'\0412\044b\0448\0438\0432\043a\0430', U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  (U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430', U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'),
  (U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'),
  (U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c', U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f')
)
INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, application_method,
  priority, is_active
)
SELECT DISTINCT
  contractor.id, 'executor', method.category, method.id, 1, true
FROM fixed_methods fixed
JOIN product_application_methods method
  ON lower(trim(method.name)) = lower(trim(fixed.method_name))
JOIN contractors contractor
  ON lower(trim(contractor.name)) = lower(trim(fixed.contractor_name))
WHERE method.category IS NOT NULL
  AND COALESCE(method.is_active, true)
  AND COALESCE(contractor.approval_status, 'approved') = 'approved'
ON CONFLICT (
  contractor, capability_type, product_category,
  (COALESCE(product_subcategory, 0)), (COALESCE(application_method, 0))
) DO UPDATE SET priority = 1, is_active = true;

-- Personal internal executor for plastic cards and plastic badges. Keep the
-- production executor in the contractor layer used by orders_items, but bind
-- it to the employee account when that employee already exists.
INSERT INTO contractors (
  name, contact_name, directus_user, approval_status, is_internal_production
)
SELECT
  U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c',
  U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c',
  employee.directus_user,
  'approved',
  true
FROM (SELECT 1) seed
LEFT JOIN LATERAL (
  SELECT employees.directus_user
  FROM employees
  WHERE lower(trim(employees.full_name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  ORDER BY employees.id
  LIMIT 1
) employee ON true
WHERE NOT EXISTS (
  SELECT 1
  FROM contractors
  WHERE lower(trim(contractors.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
);

UPDATE contractors contractor
SET contact_name = COALESCE(NULLIF(contractor.contact_name, ''), U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'),
    approval_status = 'approved',
    is_internal_production = true
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
;

UPDATE contractors contractor
SET directus_user = employee.directus_user
FROM employees employee
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  AND lower(trim(employee.full_name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
  AND contractor.directus_user IS NULL
  AND employee.directus_user IS NOT NULL;

INSERT INTO contractor_capabilities (
  contractor, capability_type, product_category, product_subcategory,
  application_method, priority, is_active
)
SELECT
  contractor.id, 'executor', category.id, subcategory.id,
  NULL, 1, true
FROM contractors contractor
JOIN product_categories category
  ON lower(trim(category.name)) = lower(trim(U&'\041f\043e\043b\0438\0433\0440\0430\0444\0438\044f'))
JOIN product_subcategories subcategory
  ON subcategory.category = category.id
 AND lower(trim(subcategory.name)) IN (
   lower(trim(U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \043a\0430\0440\0442\044b')),
   lower(trim(U&'\041f\043b\0430\0441\0442\0438\043a\043e\0432\044b\0435 \0431\0435\0439\0434\0436\0438'))
 )
WHERE lower(trim(contractor.name)) = lower(trim(U&'\041a\0430\043b\044c\0432\0438\043d \041c\0430\043a\0441\0438\043c'))
ON CONFLICT (
  contractor, capability_type, product_category,
  (COALESCE(product_subcategory, 0)), (COALESCE(application_method, 0))
) DO UPDATE SET priority = 1, is_active = true;

CREATE OR REPLACE FUNCTION apply_category_contractors_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  needs_blank boolean := false;
  executor_candidates integer[] := ARRAY[]::integer[];
  supplier_candidates integer[] := ARRAY[]::integer[];
  fixed_executor integer;
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.product_category IS DISTINCT FROM OLD.product_category
     OR NEW.product_subcategory IS DISTINCT FROM OLD.product_subcategory
     OR NEW.application_method IS DISTINCT FROM OLD.application_method
     OR NEW.blank_source IS DISTINCT FROM OLD.blank_source THEN

    SELECT COALESCE(
      pc.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR pc.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR pc.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%', false
    ) INTO needs_blank
    FROM product_categories pc
    WHERE pc.id = NEW.product_category;
    needs_blank := COALESCE(needs_blank, false);

    IF NEW.product_subcategory IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM product_subcategories subcategory
      WHERE subcategory.id = NEW.product_subcategory
        AND subcategory.category = NEW.product_category
        AND COALESCE(subcategory.is_active, true)
    ) THEN
      NEW.product_subcategory := NULL;
    END IF;

    IF NEW.application_method IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM product_application_methods method
      WHERE method.id = NEW.application_method
        AND COALESCE(method.is_active, true)
        AND (method.category = NEW.product_category OR method.category IS NULL)
    ) THEN
      NEW.application_method := NULL;
    END IF;

    SELECT contractor.id
      INTO fixed_executor
    FROM product_application_methods method
    JOIN contractors contractor ON lower(trim(contractor.name)) = lower(trim(
      CASE
        WHEN lower(trim(method.name)) IN (
          lower(U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c'),
          lower(U&'\0412\044b\0448\0438\0432\043a\0430'),
          lower(U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430')
        ) THEN U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'
        WHEN lower(trim(method.name)) IN (
          lower(U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'),
          lower(U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c')
        ) THEN U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'
        ELSE ''
      END
    ))
    WHERE method.id = NEW.application_method
      AND COALESCE(contractor.approval_status, 'approved') = 'approved'
    ORDER BY contractor.id
    LIMIT 1;

    WITH matching AS (
      SELECT capability.contractor,
        (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
         + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
      FROM contractor_capabilities capability
      JOIN contractors contractor ON contractor.id = capability.contractor
      WHERE capability.capability_type = 'executor'
        AND COALESCE(capability.is_active, true)
        AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        AND capability.product_category = NEW.product_category
        AND (capability.product_subcategory IS NULL OR capability.product_subcategory = NEW.product_subcategory)
        AND (capability.application_method IS NULL OR capability.application_method = NEW.application_method)
    ), best AS (SELECT MAX(specificity) AS specificity FROM matching)
    SELECT COALESCE(array_agg(DISTINCT matching.contractor), ARRAY[]::integer[])
      INTO executor_candidates
    FROM matching, best
    WHERE matching.specificity = best.specificity;

    IF fixed_executor IS NOT NULL THEN
      executor_candidates := ARRAY[fixed_executor];
    END IF;

    IF needs_blank THEN
      IF NEW.blank_source IS NULL OR NEW.blank_source NOT IN ('supplier', 'customer', 'warehouse', 'contractor') THEN
        NEW.blank_source := 'supplier';
      END IF;

      IF fixed_executor IS NOT NULL THEN
        NEW.contractor_2 := fixed_executor;
      ELSIF NEW.contractor_2 IS NULL AND cardinality(executor_candidates) = 1 THEN
        NEW.contractor_2 := executor_candidates[1];
      ELSIF NEW.contractor_2 IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contractors contractor
        WHERE contractor.id = NEW.contractor_2
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
      ) THEN
        NEW.contractor_2 := NULL;
      END IF;

      IF NEW.blank_source = 'supplier' THEN
        WITH matching AS (
          SELECT capability.contractor,
            (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
             + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
          FROM contractor_capabilities capability
          JOIN contractors contractor ON contractor.id = capability.contractor
          WHERE capability.capability_type = 'blank_supplier'
            AND COALESCE(capability.is_active, true)
            AND COALESCE(contractor.approval_status, 'approved') = 'approved'
            AND capability.product_category = NEW.product_category
            AND (capability.product_subcategory IS NULL OR capability.product_subcategory = NEW.product_subcategory)
            AND (capability.application_method IS NULL OR capability.application_method = NEW.application_method)
        ), best AS (SELECT MAX(specificity) AS specificity FROM matching)
        SELECT COALESCE(array_agg(DISTINCT matching.contractor), ARRAY[]::integer[])
          INTO supplier_candidates
        FROM matching, best
        WHERE matching.specificity = best.specificity;

        IF NEW.contractor_1 IS NULL AND cardinality(supplier_candidates) = 1 THEN
          NEW.contractor_1 := supplier_candidates[1];
        ELSIF NEW.contractor_1 IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM contractors contractor
          WHERE contractor.id = NEW.contractor_1
            AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        ) THEN
          NEW.contractor_1 := NULL;
          NEW.contractor_1_cost := 0;
        END IF;
      ELSE
        NEW.contractor_1 := NULL;
        NEW.contractor_1_cost := 0;
        NEW.blank_ordered := false;
      END IF;
    ELSE
      NEW.blank_source := 'none';
      NEW.blank_ordered := false;
      NEW.contractor_2 := NULL;
      IF fixed_executor IS NOT NULL THEN
        NEW.contractor_1 := fixed_executor;
      ELSIF NEW.contractor_1 IS NULL AND cardinality(executor_candidates) = 1 THEN
        NEW.contractor_1 := executor_candidates[1];
      ELSIF NEW.contractor_1 IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contractors contractor
        WHERE contractor.id = NEW.contractor_1
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
      ) THEN
        NEW.contractor_1 := NULL;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Existing packaging items created before packaging became a two-stage route
-- already contain supplier in contractor_1 and executor in contractor_2.
-- Preserve those choices and only normalize their blank source.
UPDATE orders_items item
SET blank_source = 'supplier'
FROM product_categories category
WHERE item.product_category = category.id
  AND category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
  AND COALESCE(item.blank_source, 'none') = 'none'
  AND item.contractor_1 IS NOT NULL
  AND item.contractor_2 IS NOT NULL;

CREATE OR REPLACE FUNCTION symbolika_validate_item_route_for_work()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  needs_blank boolean := false;
BEGIN
  IF symbolika_normalize_item_status(NEW.item_status) IN ('sent_to_work', 'in_work')
     AND symbolika_normalize_item_status(OLD.item_status) NOT IN ('sent_to_work', 'in_work') THEN
    IF NEW.product_category IS NULL THEN
      RAISE EXCEPTION 'Для запуска позиции укажите категорию';
    END IF;
    SELECT COALESCE(
      category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%', false
    ) INTO needs_blank
    FROM product_categories category WHERE category.id = NEW.product_category;

    IF needs_blank AND NEW.contractor_2 IS NULL THEN
      RAISE EXCEPTION 'Для запуска позиции выберите исполнителя работ';
    ELSIF NOT needs_blank AND NEW.contractor_1 IS NULL THEN
      RAISE EXCEPTION 'Для запуска позиции выберите исполнителя работ';
    END IF;
    IF needs_blank AND NEW.blank_source = 'supplier' AND NEW.contractor_1 IS NULL THEN
      RAISE EXCEPTION 'Для запуска позиции выберите поставщика заготовки';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_validate_item_route_for_work ON orders_items;
CREATE TRIGGER symbolika_validate_item_route_for_work
BEFORE UPDATE OF item_status ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_validate_item_route_for_work();

-- Final route guard. The earlier transition-only definition is kept above for
-- migration readability; this definition replaces it and also protects an
-- already running item from losing or changing to an invalid route.
CREATE OR REPLACE FUNCTION symbolika_validate_item_route_for_work()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  needs_blank boolean := false;
  selected_executor integer;
  executor_candidates_exist boolean := false;
  executor_allowed boolean := false;
  supplier_candidates_exist boolean := false;
  supplier_allowed boolean := false;
BEGIN
  IF symbolika_normalize_item_status(NEW.item_status) IN ('sent_to_work', 'in_work') THEN
    IF NEW.product_category IS NULL THEN
      RAISE EXCEPTION USING MESSAGE = U&'\0414\043b\044f \0437\0430\043f\0443\0441\043a\0430 \043f\043e\0437\0438\0446\0438\0438 \0443\043a\0430\0436\0438\0442\0435 \043a\0430\0442\0435\0433\043e\0440\0438\044e';
    END IF;

    SELECT COALESCE(
      category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%', false
    ) INTO needs_blank
    FROM product_categories category
    WHERE category.id = NEW.product_category;
    needs_blank := COALESCE(needs_blank, false);
    selected_executor := CASE
      WHEN needs_blank THEN NEW.contractor_2
      ELSE NEW.contractor_1
    END;

    WITH matching AS (
      SELECT capability.contractor,
        (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
         + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
      FROM contractor_capabilities capability
      JOIN contractors contractor ON contractor.id = capability.contractor
      WHERE capability.capability_type = 'executor'
        AND COALESCE(capability.is_active, true)
        AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        AND capability.product_category = NEW.product_category
        AND (capability.product_subcategory IS NULL OR capability.product_subcategory = NEW.product_subcategory)
        AND (capability.application_method IS NULL OR capability.application_method = NEW.application_method)
    ), best AS (
      SELECT MAX(specificity) AS specificity FROM matching
    )
    SELECT EXISTS (SELECT 1 FROM matching), EXISTS (
      SELECT 1 FROM matching, best
      WHERE matching.specificity = best.specificity
        AND matching.contractor = selected_executor
    ) INTO executor_candidates_exist, executor_allowed;

    -- Capabilities drive and restrict the ordinary manager UI. Administrator
    -- and managing may correct a route manually in costing, so the database
    -- guard must accept an explicitly selected approved contractor even when
    -- another capability exists for this category.
    IF selected_executor IS NOT NULL AND NOT executor_allowed THEN
      SELECT EXISTS (
        SELECT 1
        FROM contractors contractor
        WHERE contractor.id = selected_executor
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
      ) INTO executor_allowed;
    END IF;

    IF selected_executor IS NULL OR NOT executor_allowed THEN
      RAISE EXCEPTION USING MESSAGE = U&'\0414\043b\044f \0437\0430\043f\0443\0441\043a\0430 \043f\043e\0437\0438\0446\0438\0438 \0432\044b\0431\0435\0440\0438\0442\0435 \0434\043e\043f\0443\0441\0442\0438\043c\043e\0433\043e \0438\0441\043f\043e\043b\043d\0438\0442\0435\043b\044f \0440\0430\0431\043e\0442';
    END IF;

    IF needs_blank AND NEW.blank_source = 'supplier' THEN
      WITH matching AS (
        SELECT capability.contractor,
          (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
           + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
        FROM contractor_capabilities capability
        JOIN contractors contractor ON contractor.id = capability.contractor
        WHERE capability.capability_type = 'blank_supplier'
          AND COALESCE(capability.is_active, true)
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
          AND capability.product_category = NEW.product_category
          AND (capability.product_subcategory IS NULL OR capability.product_subcategory = NEW.product_subcategory)
          AND (capability.application_method IS NULL OR capability.application_method = NEW.application_method)
      ), best AS (
        SELECT MAX(specificity) AS specificity FROM matching
      )
      SELECT EXISTS (SELECT 1 FROM matching), EXISTS (
        SELECT 1 FROM matching, best
        WHERE matching.specificity = best.specificity
          AND matching.contractor = NEW.contractor_1
      ) INTO supplier_candidates_exist, supplier_allowed;

      IF NEW.contractor_1 IS NOT NULL AND NOT supplier_allowed THEN
        SELECT EXISTS (
          SELECT 1
          FROM contractors contractor
          WHERE contractor.id = NEW.contractor_1
            AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        ) INTO supplier_allowed;
      END IF;

      IF NEW.contractor_1 IS NULL OR NOT supplier_allowed THEN
        RAISE EXCEPTION USING MESSAGE = U&'\0414\043b\044f \0437\0430\043f\0443\0441\043a\0430 \043f\043e\0437\0438\0446\0438\0438 \0432\044b\0431\0435\0440\0438\0442\0435 \0434\043e\043f\0443\0441\0442\0438\043c\043e\0433\043e \043f\043e\0441\0442\0430\0432\0449\0438\043a\0430 \0437\0430\0433\043e\0442\043e\0432\043a\0438';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_validate_item_route_for_work ON orders_items;
CREATE TRIGGER symbolika_validate_item_route_for_work
BEFORE INSERT OR UPDATE OF item_status, product_category, product_subcategory,
  application_method, blank_source, contractor_1, contractor_2 ON orders_items
FOR EACH ROW EXECUTE FUNCTION symbolika_validate_item_route_for_work();

-- Repair existing positions which were created before the fixed internal
-- routes existed. Active work is normalized too, while completed, delivered
-- and cancelled positions keep their historical executor.
WITH fixed_routes AS (
  SELECT
    method.id AS application_method,
    contractor.id AS contractor,
    lower(trim(method.name)) AS method_name
  FROM product_application_methods method
  JOIN contractors contractor ON lower(trim(contractor.name)) = lower(trim(
    CASE
      WHEN lower(trim(method.name)) IN (
        lower(U&'\0426\0438\0444\0440\043e\0432\0430\044f \043f\0435\0447\0430\0442\044c'),
        lower(U&'\0412\044b\0448\0438\0432\043a\0430'),
        lower(U&'\0413\0440\0430\0432\0438\0440\043e\0432\043a\0430')
      ) THEN U&'\0421\043e\0431\0441\0442\0432\0435\043d\043d\043e\0435 \043f\0440\043e\0438\0437\0432\043e\0434\0441\0442\0432\043e'
      WHEN lower(trim(method.name)) IN (
        lower(U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'),
        lower(U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f \0441 \0442\0440\0430\043d\0441\0444\0435\0440\043e\043c')
      ) THEN U&'\0428\0435\043b\043a\043e\0433\0440\0430\0444\0438\044f'
      ELSE ''
    END
  ))
  WHERE COALESCE(contractor.approval_status, 'approved') = 'approved'
)
UPDATE orders_items item
SET contractor_1 = CASE
      WHEN category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
        OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
        OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
      THEN item.contractor_1 ELSE route.contractor END,
    contractor_2 = CASE
      WHEN category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
        OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
        OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
      THEN route.contractor ELSE NULL END,
    contractor_1_cost = CASE
      WHEN category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
        OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
        OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
      THEN item.contractor_1_cost ELSE 0 END,
    contractor_2_cost = CASE
      WHEN category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
        OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
        OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
      THEN 0 ELSE item.contractor_2_cost END
FROM fixed_routes route, product_categories category
WHERE category.id = item.product_category
  AND item.application_method = route.application_method
  AND COALESCE(symbolika_normalize_item_status(item.item_status), 'new')
      IN ('new', 'approval', 'layout_revision', 'sent_to_work', 'in_work');

CREATE OR REPLACE FUNCTION symbolika_order_work_completion(order_id integer)
RETURNS TABLE (
  work_completion_percent integer,
  work_completion_missing_count integer,
  work_completion_missing text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  item_row record;
  checks_total integer := 0;
  checks_filled integer := 0;
  missing_values text[] := ARRAY[]::text[];
  item_label text;
  needs_blank boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders_items item WHERE item."order" = order_id) THEN
    RETURN QUERY SELECT 0, 1, U&'\0417\0430\043a\0430\0437: \043d\0435\0442 \043f\043e\0437\0438\0446\0438\0439';
    RETURN;
  END IF;

  FOR item_row IN SELECT item.* FROM orders_items item WHERE item."order" = order_id ORDER BY item.id LOOP
    item_label := COALESCE(NULLIF(BTRIM(item_row.product_name), ''), U&'\041f\043e\0437\0438\0446\0438\044f #' || item_row.id::text);

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.product_name), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043d\0430\0437\0432\0430\043d\0438\0435'); END IF;

    checks_total := checks_total + 1;
    IF COALESCE(item_row.quantity, 0) > 0 THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\043e\043b\0438\0447\0435\0441\0442\0432\043e'); END IF;

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.technical_task_text), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0422\0417'); END IF;

    checks_total := checks_total + 1;
    IF NULLIF(BTRIM(item_row.url), '') IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \0441\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442'); END IF;

    checks_total := checks_total + 1;
    IF item_row.product_category IS NOT NULL THEN checks_filled := checks_filled + 1;
    ELSE missing_values := array_append(missing_values, item_label || U&': \043a\0430\0442\0435\0433\043e\0440\0438\044f'); END IF;

    SELECT COALESCE(
      category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%', false
    ) INTO needs_blank
    FROM product_categories category WHERE category.id = item_row.product_category;
    needs_blank := COALESCE(needs_blank, false);

    checks_total := checks_total + 1;
    IF (needs_blank AND item_row.contractor_2 IS NOT NULL)
       OR (NOT needs_blank AND item_row.contractor_1 IS NOT NULL) THEN
      checks_filled := checks_filled + 1;
    ELSE
      missing_values := array_append(missing_values, item_label || U&': \0438\0441\043f\043e\043b\043d\0438\0442\0435\043b\044c \0440\0430\0431\043e\0442');
    END IF;

    IF needs_blank AND item_row.blank_source = 'supplier' THEN
      checks_total := checks_total + 1;
      IF item_row.contractor_1 IS NOT NULL THEN checks_filled := checks_filled + 1;
      ELSE missing_values := array_append(missing_values, item_label || U&': \043f\043e\0441\0442\0430\0432\0449\0438\043a \0437\0430\0433\043e\0442\043e\0432\043a\0438'); END IF;
    END IF;
  END LOOP;

  RETURN QUERY SELECT
    CASE WHEN checks_total > 0 THEN ROUND(checks_filled * 100.0 / checks_total)::integer ELSE 0 END,
    COALESCE(array_length(missing_values, 1), 0),
    array_to_string(missing_values, '||');
END;
$$;

INSERT INTO directus_collections (collection, icon, hidden, singleton, sort, collapse, translations)
VALUES (
  'contractor_capabilities', 'route', true, false, 44, 'open',
  json_build_array(json_build_object('language','ru-RU','translation', U&'\0412\043e\0437\043c\043e\0436\043d\043e\0441\0442\0438 \043a\043e\043d\0442\0440\0430\0433\0435\043d\0442\043e\0432'))::json
)
ON CONFLICT (collection) DO UPDATE SET icon = EXCLUDED.icon, hidden = EXCLUDED.hidden;

DELETE FROM directus_fields WHERE collection = 'contractor_capabilities';
INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES
  ('contractor_capabilities','id',NULL,'numeric',NULL,NULL,NULL,true,true,1,'full',NULL,false,true),
  ('contractor_capabilities','contractor','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,2,'half',NULL,true,true),
  ('contractor_capabilities','capability_type',NULL,'select-dropdown',json_build_object(
    'choices', json_build_array(
      json_build_object('text', U&'\0418\0441\043f\043e\043b\043d\0438\0442\0435\043b\044c \0440\0430\0431\043e\0442', 'value', 'executor'),
      json_build_object('text', U&'\041f\043e\0441\0442\0430\0432\0449\0438\043a \0437\0430\0433\043e\0442\043e\0432\043a\0438', 'value', 'blank_supplier')
    )
  )::json,'labels',NULL,false,false,3,'half',NULL,true,true),
  ('contractor_capabilities','product_category','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,4,'half',NULL,true,true),
  ('contractor_capabilities','product_subcategory','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,5,'half',NULL,false,true),
  ('contractor_capabilities','application_method','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,6,'half',NULL,false,true),
  ('contractor_capabilities','priority',NULL,'input',NULL,NULL,NULL,false,false,7,'half',NULL,false,true),
  ('contractor_capabilities','is_active','cast-boolean','boolean',NULL,NULL,NULL,false,false,8,'half',NULL,false,true);

DELETE FROM directus_relations WHERE many_collection = 'contractor_capabilities';
INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, one_deselect_action) VALUES
  ('contractor_capabilities','contractor','contractors',NULL,'cascade'),
  ('contractor_capabilities','product_category','product_categories',NULL,'cascade'),
  ('contractor_capabilities','product_subcategory','product_subcategories',NULL,'cascade'),
  ('contractor_capabilities','application_method','product_application_methods',NULL,'cascade');

DELETE FROM directus_permissions WHERE collection = 'contractor_capabilities';
INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'contractor_capabilities', 'read', '{}'::json, NULL, NULL,
  'id,contractor,capability_type,product_category,product_subcategory,application_method,priority,is_active', policy
FROM (VALUES
  ('00000000-0000-4000-8000-000000000201'::uuid),
  ('00000000-0000-4000-8000-000000000202'::uuid),
  ('00000000-0000-4000-8000-000000000204'::uuid),
  ('00000000-0000-4000-8000-000000000205'::uuid),
  ('00000000-0000-4000-8000-000000000206'::uuid),
  ('00000000-0000-4000-8000-000000000208'::uuid)
) policies(policy);

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy) VALUES
  ('contractor_capabilities','create','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205'),
  ('contractor_capabilities','update','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205'),
  ('contractor_capabilities','delete','{}'::json,NULL,NULL,'*','00000000-0000-4000-8000-000000000205');

-- Employees who sell their own orders need to read and save the selected
-- executor. Contractor costs are granted separately to manager policies below.
UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'contractor_2')
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL AND fields <> '*'
  AND NOT ('contractor_2' = ANY(string_to_array(fields, ',')))
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

-- Every employee who creates an order acts as its manager and must be able to
-- enter the per-unit cost of both the blank and the contractor's work. This
-- includes the manager, office, production, screen-printing and designer
-- self-sales policies. Row-level policy filters still keep foreign orders
-- inaccessible. Administrators and managing staff already have full access
-- and use these values for verification and order economics.
UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'contractor_1_cost')
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL AND fields <> '*'
  AND NOT ('contractor_1_cost' = ANY(string_to_array(fields, ',')))
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

UPDATE directus_permissions
SET fields = concat_ws(',', NULLIF(fields, ''), 'contractor_2_cost')
WHERE collection = 'orders_items'
  AND action IN ('create', 'read', 'update')
  AND fields IS NOT NULL AND fields <> '*'
  AND NOT ('contractor_2_cost' = ANY(string_to_array(fields, ',')))
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000208'
  );

-- The order-level launch check must use the same contractor capability rules
-- as the position form and the position-level trigger. This final definition
-- replaces the legacy readiness function declared before the capability table.
CREATE OR REPLACE FUNCTION symbolika_order_work_readiness(order_id integer)
RETURNS TABLE (
  ready_for_work boolean,
  missing_count integer,
  missing_fields text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  order_row record;
  item_row record;
  missing_values text[] := ARRAY[]::text[];
  item_label text;
  needs_blank boolean;
  selected_executor integer;
  executor_candidates_exist boolean;
  executor_allowed boolean;
  supplier_candidates_exist boolean;
  supplier_allowed boolean;
BEGIN
  SELECT orders.* INTO order_row FROM orders WHERE orders.id = order_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 1, U&'\0417\0430\043a\0430\0437 \043d\0435 \043d\0430\0439\0434\0435\043d';
    RETURN;
  END IF;

  IF order_row.customer IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043a\043b\0438\0435\043d\0442');
  END IF;
  IF order_row.manager_employee IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043c\0435\043d\0435\0434\0436\0435\0440');
  END IF;
  IF order_row.date IS NULL THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \0434\0430\0442\0430');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM orders_items item WHERE item."order" = order_id) THEN
    missing_values := array_append(missing_values, U&'\0417\0430\043a\0430\0437: \043d\0435\0442 \043f\043e\0437\0438\0446\0438\0439');
  END IF;

  FOR item_row IN
    SELECT item.*
    FROM orders_items item
    WHERE item."order" = order_id
      AND symbolika_normalize_item_status(item.item_status) <> 'cancelled'
    ORDER BY item.id
  LOOP
    item_label := COALESCE(NULLIF(BTRIM(item_row.product_name), ''), U&'\041f\043e\0437\0438\0446\0438\044f #' || item_row.id::text);
    IF NULLIF(BTRIM(item_row.product_name), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \043d\0430\0437\0432\0430\043d\0438\0435');
    END IF;
    IF COALESCE(item_row.quantity, 0) <= 0 THEN
      missing_values := array_append(missing_values, item_label || U&': \043a\043e\043b\0438\0447\0435\0441\0442\0432\043e');
    END IF;
    IF NULLIF(BTRIM(item_row.technical_task_text), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \0422\0417');
    END IF;
    IF NULLIF(BTRIM(item_row.url), '') IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \0441\0441\044b\043b\043a\0430 \043d\0430 \043c\0430\043a\0435\0442');
    END IF;
    IF item_row.product_category IS NULL THEN
      missing_values := array_append(missing_values, item_label || U&': \043a\0430\0442\0435\0433\043e\0440\0438\044f');
      CONTINUE;
    END IF;

    SELECT COALESCE(
      category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%', false
    ) INTO needs_blank
    FROM product_categories category
    WHERE category.id = item_row.product_category;
    needs_blank := COALESCE(needs_blank, false);
    selected_executor := CASE
      WHEN needs_blank THEN item_row.contractor_2
      ELSE item_row.contractor_1
    END;

    WITH matching AS (
      SELECT capability.contractor,
        (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
         + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
      FROM contractor_capabilities capability
      JOIN contractors contractor ON contractor.id = capability.contractor
      WHERE capability.capability_type = 'executor'
        AND COALESCE(capability.is_active, true)
        AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        AND capability.product_category = item_row.product_category
        AND (capability.product_subcategory IS NULL OR capability.product_subcategory = item_row.product_subcategory)
        AND (capability.application_method IS NULL OR capability.application_method = item_row.application_method)
    ), best AS (SELECT MAX(specificity) AS specificity FROM matching)
    SELECT EXISTS (SELECT 1 FROM matching), EXISTS (
      SELECT 1 FROM matching, best
      WHERE matching.specificity = best.specificity
        AND matching.contractor = selected_executor
    ) INTO executor_candidates_exist, executor_allowed;
    IF selected_executor IS NOT NULL AND NOT COALESCE(executor_allowed, false) THEN
      SELECT EXISTS (
        SELECT 1
        FROM contractors contractor
        WHERE contractor.id = selected_executor
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
      ) INTO executor_allowed;
    END IF;
    IF selected_executor IS NULL OR NOT COALESCE(executor_allowed, false) THEN
      missing_values := array_append(missing_values, item_label || U&': \0438\0441\043f\043e\043b\043d\0438\0442\0435\043b\044c \0440\0430\0431\043e\0442');
    END IF;

    IF needs_blank AND item_row.blank_source = 'supplier' THEN
      WITH matching AS (
        SELECT capability.contractor,
          (CASE WHEN capability.product_subcategory IS NOT NULL THEN 2 ELSE 0 END
           + CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END) AS specificity
        FROM contractor_capabilities capability
        JOIN contractors contractor ON contractor.id = capability.contractor
        WHERE capability.capability_type = 'blank_supplier'
          AND COALESCE(capability.is_active, true)
          AND COALESCE(contractor.approval_status, 'approved') = 'approved'
          AND capability.product_category = item_row.product_category
          AND (capability.product_subcategory IS NULL OR capability.product_subcategory = item_row.product_subcategory)
          AND (capability.application_method IS NULL OR capability.application_method = item_row.application_method)
      ), best AS (SELECT MAX(specificity) AS specificity FROM matching)
      SELECT EXISTS (SELECT 1 FROM matching), EXISTS (
        SELECT 1 FROM matching, best
        WHERE matching.specificity = best.specificity
          AND matching.contractor = item_row.contractor_1
      ) INTO supplier_candidates_exist, supplier_allowed;
      IF item_row.contractor_1 IS NOT NULL AND NOT COALESCE(supplier_allowed, false) THEN
        SELECT EXISTS (
          SELECT 1
          FROM contractors contractor
          WHERE contractor.id = item_row.contractor_1
            AND COALESCE(contractor.approval_status, 'approved') = 'approved'
        ) INTO supplier_allowed;
      END IF;
      IF item_row.contractor_1 IS NULL OR NOT COALESCE(supplier_allowed, false) THEN
        missing_values := array_append(missing_values, item_label || U&': \043f\043e\0441\0442\0430\0432\0449\0438\043a \0437\0430\0433\043e\0442\043e\0432\043a\0438');
      END IF;
    END IF;

    IF symbolika_normalize_item_status(item_row.item_status) = 'layout_revision'
       AND (
         NULLIF(BTRIM(item_row.url), '') IS NULL
         OR item_row.url IS NOT DISTINCT FROM item_row.layout_revision_url_snapshot
       ) THEN
      missing_values := array_append(missing_values, item_label || U&': \043e\0431\043d\043e\0432\0438\0442\0435 \0441\0441\044b\043b\043a\0443 \043d\0430 \043c\0430\043a\0435\0442');
    END IF;
  END LOOP;

  RETURN QUERY SELECT
    COALESCE(array_length(missing_values, 1), 0) = 0,
    COALESCE(array_length(missing_values, 1), 0),
    array_to_string(missing_values, '||');
END;
$$;

SELECT refresh_orders_due_tables();

-- Managing supervises the manager workflow. Besides unrestricted business
-- collections defined above, keep the two auxiliary manager permissions in
-- sync as well: company/customer links and the current user's notifications.
DELETE FROM directus_permissions
 WHERE policy = '00000000-0000-4000-8000-000000000205'
   AND collection IN ('customer_company_links', 'directus_notifications');

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
VALUES
  ('customer_company_links', 'read', '{}'::json, NULL, NULL, '*', '00000000-0000-4000-8000-000000000205'),
  ('directus_notifications', 'read', '{"recipient":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL,
    'id,status,recipient,subject,message,collection,item,timestamp', '00000000-0000-4000-8000-000000000205'),
  ('directus_notifications', 'update', '{"recipient":{"_eq":"$CURRENT_USER"}}'::json, NULL, NULL,
    'status', '00000000-0000-4000-8000-000000000205');

COMMIT;


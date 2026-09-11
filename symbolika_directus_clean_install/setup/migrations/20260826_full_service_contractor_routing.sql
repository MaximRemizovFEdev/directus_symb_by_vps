-- Keep full-service contractor routing reproducible on existing installations.
-- The canonical definitions remain in create-work-views.sql; this migration
-- updates only the already installed functions and Directus field metadata.

DO $migration$
DECLARE
  source text;
BEGIN
  SELECT prosrc INTO source
  FROM pg_proc
  WHERE oid = 'public.apply_category_contractors_trigger()'::regprocedure;

  source := replace(source,
    'NEW.blank_source NOT IN (''supplier'', ''customer'', ''warehouse'')',
    'NEW.blank_source NOT IN (''supplier'', ''customer'', ''warehouse'', ''contractor'')');
  source := replace(source,
    'IF cardinality(executor_candidates) = 1 THEN
        NEW.contractor_2 := executor_candidates[1];
      ELSIF NOT (NEW.contractor_2 = ANY(executor_candidates)) THEN
        NEW.contractor_2 := NULL;',
    'IF NEW.contractor_2 IS NULL AND cardinality(executor_candidates) = 1 THEN
        NEW.contractor_2 := executor_candidates[1];
      ELSIF NEW.contractor_2 IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contractors contractor
        WHERE contractor.id = NEW.contractor_2
          AND COALESCE(contractor.approval_status, ''approved'') = ''approved''
      ) THEN
        NEW.contractor_2 := NULL;');
  source := replace(source,
    'IF cardinality(supplier_candidates) = 1 THEN
          NEW.contractor_1 := supplier_candidates[1];
        ELSIF NOT (NEW.contractor_1 = ANY(supplier_candidates)) THEN
          NEW.contractor_1 := NULL;',
    'IF NEW.contractor_1 IS NULL AND cardinality(supplier_candidates) = 1 THEN
          NEW.contractor_1 := supplier_candidates[1];
        ELSIF NEW.contractor_1 IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM contractors contractor
          WHERE contractor.id = NEW.contractor_1
            AND COALESCE(contractor.approval_status, ''approved'') = ''approved''
        ) THEN
          NEW.contractor_1 := NULL;');
  source := replace(source,
    'IF cardinality(executor_candidates) = 1 THEN
        NEW.contractor_1 := executor_candidates[1];
      ELSIF NOT (NEW.contractor_1 = ANY(executor_candidates)) THEN
        NEW.contractor_1 := NULL;',
    'IF NEW.contractor_1 IS NULL AND cardinality(executor_candidates) = 1 THEN
        NEW.contractor_1 := executor_candidates[1];
      ELSIF NEW.contractor_1 IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contractors contractor
        WHERE contractor.id = NEW.contractor_1
          AND COALESCE(contractor.approval_status, ''approved'') = ''approved''
      ) THEN
        NEW.contractor_1 := NULL;');

  IF position($needle$'warehouse', 'contractor'$needle$ IN source) = 0
     OR position('NEW.contractor_2 IS NULL AND cardinality(executor_candidates) = 1' IN source) = 0 THEN
    RAISE EXCEPTION 'Could not migrate apply_category_contractors_trigger safely';
  END IF;
  EXECUTE format(
    $ddl$CREATE OR REPLACE FUNCTION public.apply_category_contractors_trigger()
      RETURNS trigger LANGUAGE plpgsql AS %L$ddl$,
    source
  );

  SELECT prosrc INTO source
  FROM pg_proc
  WHERE oid = 'public.symbolika_validate_item_route_for_work()'::regprocedure;
  source := replace(source,
    'WHEN needs_blank AND NEW.blank_source = ''supplier'' THEN NEW.contractor_2
      WHEN needs_blank THEN COALESCE(NEW.contractor_2, NEW.contractor_1)',
    'WHEN needs_blank THEN NEW.contractor_2');
  source := replace(source,
    'IF NOT executor_candidates_exist AND selected_executor IS NOT NULL THEN',
    'IF selected_executor IS NOT NULL AND NOT executor_allowed THEN');
  source := replace(source,
    'IF NOT supplier_candidates_exist AND NEW.contractor_1 IS NOT NULL THEN',
    'IF NEW.contractor_1 IS NOT NULL AND NOT supplier_allowed THEN');
  IF position('WHEN needs_blank THEN NEW.contractor_2' IN source) = 0
     OR position('selected_executor IS NOT NULL AND NOT executor_allowed' IN source) = 0 THEN
    RAISE EXCEPTION 'Could not migrate symbolika_validate_item_route_for_work safely';
  END IF;
  EXECUTE format(
    $ddl$CREATE OR REPLACE FUNCTION public.symbolika_validate_item_route_for_work()
      RETURNS trigger LANGUAGE plpgsql AS %L$ddl$,
    source
  );

  SELECT prosrc INTO source
  FROM pg_proc
  WHERE oid = 'public.symbolika_order_work_readiness(integer)'::regprocedure;
  source := replace(source,
    'WHEN needs_blank AND item_row.blank_source = ''supplier'' THEN item_row.contractor_2
      WHEN needs_blank THEN COALESCE(item_row.contractor_2, item_row.contractor_1)',
    'WHEN needs_blank THEN item_row.contractor_2');
  source := replace(source,
    'IF NOT COALESCE(executor_candidates_exist, false) AND selected_executor IS NOT NULL THEN',
    'IF selected_executor IS NOT NULL AND NOT COALESCE(executor_allowed, false) THEN');
  source := replace(source,
    'IF NOT COALESCE(supplier_candidates_exist, false) AND item_row.contractor_1 IS NOT NULL THEN',
    'IF item_row.contractor_1 IS NOT NULL AND NOT COALESCE(supplier_allowed, false) THEN');
  IF position('WHEN needs_blank THEN item_row.contractor_2' IN source) = 0
     OR position('selected_executor IS NOT NULL AND NOT COALESCE(executor_allowed, false)' IN source) = 0 THEN
    RAISE EXCEPTION 'Could not migrate symbolika_order_work_readiness safely';
  END IF;
  EXECUTE format(
    $ddl$CREATE OR REPLACE FUNCTION public.symbolika_order_work_readiness(order_id integer)
      RETURNS TABLE(ready_for_work boolean, missing_count integer, missing_fields text)
      LANGUAGE plpgsql STABLE AS %L$ddl$,
    source
  );
END;
$migration$;

UPDATE directus_fields
SET options = '{"choices":[{"text":"Не требуется","value":"none"},{"text":"Закупить у поставщика","value":"supplier"},{"text":"Заготовка заказчика","value":"customer"},{"text":"Со склада","value":"warehouse"},{"text":"Подрядчик под ключ","value":"contractor"}]}'::json,
    display_options = '{"choices":[{"text":"Не требуется","value":"none","foreground":"#C9D1D9","background":"#30363D"},{"text":"Закупить у поставщика","value":"supplier","foreground":"#FFD7A8","background":"#4A3423"},{"text":"Заготовка заказчика","value":"customer","foreground":"#B7F7D2","background":"#173C2B"},{"text":"Со склада","value":"warehouse","foreground":"#BFDBFE","background":"#1E3A5F"},{"text":"Подрядчик под ключ","value":"contractor","foreground":"#FFE0B2","background":"#5A3218"}]}'::json
WHERE collection IN ('orders_items', 'contractor_costing')
  AND field = 'blank_source';

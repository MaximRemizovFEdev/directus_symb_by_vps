-- Make internal routes authoritative for the application methods which are
-- always handled by a specific workshop. Keep the migration incremental: the
-- canonical definitions remain in create-work-views.sql.

BEGIN;

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

DO $migration$
DECLARE
  source text;
BEGIN
  SELECT prosrc INTO source
  FROM pg_proc
  WHERE oid = 'public.apply_category_contractors_trigger()'::regprocedure;

  source := replace(
    source,
    'CASE WHEN capability.application_method IS NOT NULL THEN 2 ELSE 0 END',
    'CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END'
  );

  IF position('fixed_executor integer' IN source) = 0 THEN
    source := replace(
      source,
      'supplier_candidates integer[] := ARRAY[]::integer[];',
      'supplier_candidates integer[] := ARRAY[]::integer[];
  fixed_executor integer;'
    );

    source := replace(
      source,
      $needle$
    WITH matching AS ($needle$,
      $replacement$
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

    WITH matching AS ($replacement$
    );

    source := replace(
      source,
      'IF NEW.contractor_2 IS NULL AND cardinality(executor_candidates) = 1 THEN',
      'IF fixed_executor IS NOT NULL THEN
        NEW.contractor_2 := fixed_executor;
      ELSIF NEW.contractor_2 IS NULL AND cardinality(executor_candidates) = 1 THEN'
    );
    source := replace(
      source,
      'IF NEW.contractor_1 IS NULL AND cardinality(executor_candidates) = 1 THEN',
      'IF fixed_executor IS NOT NULL THEN
        NEW.contractor_1 := fixed_executor;
      ELSIF NEW.contractor_1 IS NULL AND cardinality(executor_candidates) = 1 THEN'
    );
  END IF;

  IF position('fixed_executor integer' IN source) = 0
     OR position('NEW.contractor_2 := fixed_executor' IN source) = 0
     OR position('NEW.contractor_1 := fixed_executor' IN source) = 0
     OR position('CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END' IN source) = 0 THEN
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
  source := replace(
    source,
    'CASE WHEN capability.application_method IS NOT NULL THEN 2 ELSE 0 END',
    'CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END'
  );
  IF position('CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END' IN source) = 0 THEN
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
  source := replace(
    source,
    'CASE WHEN capability.application_method IS NOT NULL THEN 2 ELSE 0 END',
    'CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END'
  );
  IF position('CASE WHEN capability.application_method IS NOT NULL THEN 4 ELSE 0 END' IN source) = 0 THEN
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

-- Normalize current work while preserving completed, delivered and cancelled
-- history. For products with a blank, contractor_2 is the work executor;
-- otherwise contractor_1 is the executor.
WITH fixed_routes AS (
  SELECT
    method.id AS application_method,
    contractor.id AS contractor
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

COMMIT;

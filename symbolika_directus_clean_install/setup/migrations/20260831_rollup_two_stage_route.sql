-- Rollups have exactly two contractor slots:
-- contractor_1 = construction/blank supplier;
-- contractor_2 = printing/application executor.

CREATE OR REPLACE FUNCTION public.symbolika_item_needs_blank(
  p_category_id integer,
  p_subcategory_id integer,
  p_product_name text
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT
      category.name ILIKE U&'%\0442\0435\043a\0441\0442\0438\043b%'
      OR category.name ILIKE U&'%\0441\0443\0432\0435\043d\0438\0440%'
      OR category.name ILIKE U&'%\0443\043f\0430\043a\043e\0432%'
      OR (
        category.name ILIKE U&'%\043a\043e\043d\0441\0442\0440\0443\043a\0446%'
        AND (
          COALESCE(p_product_name, '') ILIKE U&'%\0440\043e\043b\0430\043f%'
          OR COALESCE(p_product_name, '') ILIKE U&'%\0440\043e\043b\043b\0430\043f%'
          OR EXISTS (
            SELECT 1
            FROM public.product_subcategories subcategory
            WHERE subcategory.id = p_subcategory_id
              AND (
                subcategory.name ILIKE U&'%\0440\043e\043b\0430\043f%'
                OR subcategory.name ILIKE U&'%\0440\043e\043b\043b\0430\043f%'
              )
          )
        )
      )
    FROM public.product_categories category
    WHERE category.id = p_category_id
  ), false);
$$;

CREATE OR REPLACE FUNCTION public.apply_category_contractors_trigger()
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

    needs_blank := public.symbolika_item_needs_blank(
      NEW.product_category,
      NEW.product_subcategory,
      NEW.product_name
    );

    IF NEW.product_subcategory IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.product_subcategories subcategory
      WHERE subcategory.id = NEW.product_subcategory
        AND subcategory.category = NEW.product_category
        AND COALESCE(subcategory.is_active, true)
    ) THEN
      NEW.product_subcategory := NULL;
    END IF;

    IF NEW.application_method IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.product_application_methods method
      WHERE method.id = NEW.application_method
        AND COALESCE(method.is_active, true)
        AND (method.category = NEW.product_category OR method.category IS NULL)
    ) THEN
      NEW.application_method := NULL;
    END IF;

    SELECT contractor.id
      INTO fixed_executor
    FROM public.product_application_methods method
    JOIN public.contractors contractor ON lower(trim(contractor.name)) = lower(trim(
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
      FROM public.contractor_capabilities capability
      JOIN public.contractors contractor ON contractor.id = capability.contractor
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
        SELECT 1 FROM public.contractors contractor
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
          FROM public.contractor_capabilities capability
          JOIN public.contractors contractor ON contractor.id = capability.contractor
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
          SELECT 1 FROM public.contractors contractor
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
        SELECT 1 FROM public.contractors contractor
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

-- The existing general route guard remains in place. This additional guard
-- makes the second Rollup stage mandatory even on installations where the
-- older guard was created before Rollups became a two-stage product.
CREATE OR REPLACE FUNCTION public.symbolika_validate_rollup_two_stage_route()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF public.symbolika_item_needs_blank(
       NEW.product_category,
       NEW.product_subcategory,
       NEW.product_name
     )
     AND public.symbolika_normalize_item_status(NEW.item_status) IN ('sent_to_work', 'in_work') THEN
    IF NEW.contractor_2 IS NULL THEN
      RAISE EXCEPTION USING MESSAGE = U&'\0414\043b\044f \0437\0430\043f\0443\0441\043a\0430 \043f\043e\0437\0438\0446\0438\0438 \0432\044b\0431\0435\0440\0438\0442\0435 \0438\0441\043f\043e\043b\043d\0438\0442\0435\043b\044f \0440\0430\0431\043e\0442';
    END IF;
    IF NEW.blank_source = 'supplier' AND NEW.contractor_1 IS NULL THEN
      RAISE EXCEPTION USING MESSAGE = U&'\0414\043b\044f \0437\0430\043f\0443\0441\043a\0430 \043f\043e\0437\0438\0446\0438\0438 \0432\044b\0431\0435\0440\0438\0442\0435 \043f\043e\0441\0442\0430\0432\0449\0438\043a\0430 \0437\0430\0433\043e\0442\043e\0432\043a\0438';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zz_symbolika_validate_rollup_two_stage_route ON public.orders_items;
CREATE TRIGGER zz_symbolika_validate_rollup_two_stage_route
BEFORE INSERT OR UPDATE OF item_status, product_category, product_subcategory, blank_source, contractor_1, contractor_2
ON public.orders_items
FOR EACH ROW EXECUTE FUNCTION public.symbolika_validate_rollup_two_stage_route();

-- Existing rows are deliberately not rewritten by this migration. They are
-- normalized by the routing trigger on their next explicit edit, which keeps
-- deployment safe for the live order database.

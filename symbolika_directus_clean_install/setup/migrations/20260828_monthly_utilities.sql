BEGIN;

ALTER TABLE finance_settings
  ADD COLUMN IF NOT EXISTS monthly_utilities numeric(14,2) NOT NULL DEFAULT 0;

DELETE FROM directus_fields
WHERE collection = 'finance_settings'
  AND field = 'monthly_utilities';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, required, searchable
) VALUES (
  'finance_settings', 'monthly_utilities', NULL, 'input', NULL, NULL, NULL,
  false, false, 3, 'half',
  json_build_array(json_build_object('language', 'ru-RU', 'translation', 'Коммунальные услуги'))::json,
  true, true
);

UPDATE directus_fields
SET sort = CASE field
  WHEN 'rent_due_day_from' THEN 4
  WHEN 'rent_due_day_to' THEN 5
  WHEN 'advance_day' THEN 6
  WHEN 'salary_day' THEN 7
  WHEN 'updated_at' THEN 8
  ELSE sort
END
WHERE collection = 'finance_settings'
  AND field IN ('rent_due_day_from', 'rent_due_day_to', 'advance_day', 'salary_day', 'updated_at');

UPDATE directus_fields
SET options = '{"choices":[{"text":"Аренда","value":"rent"},{"text":"Коммунальные услуги","value":"utilities"},{"text":"Материалы (бумага, тонер)","value":"production_materials"},{"text":"Производственная расходка","value":"production_consumables"},{"text":"Обслуживание и ремонт техники","value":"equipment_maintenance"},{"text":"Закупка прочих запасов","value":"inventory_purchase"},{"text":"Выплата зарплаты","value":"salary_payment"},{"text":"Назначенная премия","value":"employee_bonus"},{"text":"Оплата контрагенту","value":"contractor_payment"},{"text":"Оплата за доставку","value":"delivery"},{"text":"Прочие расходы","value":"other"},{"text":"Аванс сотруднику","value":"employee_advance"}]}'::json
WHERE collection = 'business_expenses'
  AND field = 'expense_type';

COMMIT;

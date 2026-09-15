BEGIN;

-- A manager may accept payment for an office-pickup order while helping at
-- the office, including an order owned by another manager.
UPDATE directus_permissions
SET validation = '{"_or":[{"order":{"manager_employee":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"order":{"shipping_method":{"_eq":"office_pickup"}}},{"customer":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}},{"customer_company":{"_or":[{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}},{"customers":{"manager":{"directus_user":{"_eq":"$CURRENT_USER"}}}}]}}]}'::json
WHERE collection = 'order_payments'
  AND action = 'create'
  AND policy IN (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000202'
  );

COMMIT;

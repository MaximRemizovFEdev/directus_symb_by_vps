-- Run inside the PostgreSQL container, for example:
-- pgbench -U directus -d directus -n -c 6 -j 3 -t 4 \
--   -f /tmp/derived-refresh-concurrency.sql
--
-- Both functions rebuild derived/admin-only tables. Concurrent runs must
-- finish without deadlocks or duplicate primary keys.
SELECT refresh_orders_due_tables();
SELECT refresh_symbolika_automation_issues();

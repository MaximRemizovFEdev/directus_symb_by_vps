BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS employee_compensation_rates (
  id bigserial PRIMARY KEY,
  employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  effective_month date NOT NULL,
  salary_fixed numeric(14,2) NOT NULL DEFAULT 0,
  order_percent numeric(14,2) NOT NULL DEFAULT 0,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee, effective_month),
  CHECK (effective_month = date_trunc('month', effective_month)::date)
);

CREATE INDEX IF NOT EXISTS employee_compensation_rates_lookup_idx
  ON employee_compensation_rates(employee, effective_month DESC);

-- Preserve exactly the salary and percentage currently shown for every past
-- month before switching the calculation to effective-dated rates.
INSERT INTO employee_compensation_rates (employee, effective_month, salary_fixed, order_percent)
SELECT employee, month_start, COALESCE(salary_fixed, 0), COALESCE(order_percent, 0)
FROM employee_salary_monthly
WHERE employee IS NOT NULL AND month_start IS NOT NULL
ON CONFLICT (employee, effective_month) DO NOTHING;

-- The employee row remains the convenient current-value cache. Its value is
-- authoritative for the current month when this migration is installed.
INSERT INTO employee_compensation_rates (employee, effective_month, salary_fixed, order_percent)
SELECT id, date_trunc('month', current_date)::date, COALESCE(salary_fixed, 0), COALESCE(order_percent, 0)
FROM employees
ON CONFLICT (employee, effective_month) DO UPDATE SET
  salary_fixed = EXCLUDED.salary_fixed,
  order_percent = EXCLUDED.order_percent,
  date_updated = now();

CREATE OR REPLACE FUNCTION capture_employee_compensation_rate()
RETURNS trigger AS $$
BEGIN
  INSERT INTO employee_compensation_rates (employee, effective_month, salary_fixed, order_percent)
  VALUES (
    NEW.id,
    date_trunc('month', current_date)::date,
    COALESCE(NEW.salary_fixed, 0),
    COALESCE(NEW.order_percent, 0)
  )
  ON CONFLICT (employee, effective_month) DO UPDATE SET
    salary_fixed = EXCLUDED.salary_fixed,
    order_percent = EXCLUDED.order_percent,
    date_updated = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employees_00_capture_compensation ON employees;
CREATE TRIGGER employees_00_capture_compensation
AFTER INSERT OR UPDATE OF salary_fixed, order_percent ON employees
FOR EACH ROW EXECUTE FUNCTION capture_employee_compensation_rate();

CREATE OR REPLACE FUNCTION apply_employee_compensation_history()
RETURNS void AS $$
BEGIN
  UPDATE employee_salary_monthly monthly
  SET salary_fixed = COALESCE(rate.salary_fixed, monthly.salary_fixed, 0),
      order_percent = COALESCE(rate.order_percent, monthly.order_percent, 0),
      commission_accrued = ROUND(monthly.paid_orders_sum * COALESCE(rate.order_percent, monthly.order_percent, 0) / 100, 2),
      salary_accrued = ROUND(
        COALESCE(rate.salary_fixed, monthly.salary_fixed, 0)
        + monthly.paid_orders_sum * COALESCE(rate.order_percent, monthly.order_percent, 0) / 100
        + COALESCE(monthly.bonus_paid, 0),
        2
      ),
      salary_debt = ROUND(
        COALESCE(rate.salary_fixed, monthly.salary_fixed, 0)
        + monthly.paid_orders_sum * COALESCE(rate.order_percent, monthly.order_percent, 0) / 100
        + COALESCE(monthly.bonus_paid, 0)
        - COALESCE(monthly.salary_paid, 0)
        - COALESCE(monthly.advances_paid, 0),
        2
      )
  FROM employee_compensation_rates rate
  WHERE rate.employee = monthly.employee
    AND rate.effective_month = (
      SELECT MAX(history.effective_month)
      FROM employee_compensation_rates history
      WHERE history.employee = monthly.employee
        AND history.effective_month <= monthly.month_start
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_salary_and_finance_trigger()
RETURNS trigger AS $$
BEGIN
  PERFORM refresh_employee_salary_tables();
  PERFORM apply_employee_compensation_history();
  PERFORM refresh_finance_dashboard_metrics();
  PERFORM apply_employee_compensation_history();
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

SELECT refresh_employee_salary_tables();
SELECT apply_employee_compensation_history();
SELECT refresh_finance_dashboard_metrics();
SELECT apply_employee_compensation_history();

COMMIT;

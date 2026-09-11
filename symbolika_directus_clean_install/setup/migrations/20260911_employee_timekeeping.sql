BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE IF NOT EXISTS employee_work_schedules (
  id bigserial PRIMARY KEY,
  employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  effective_month date NOT NULL,
  schedule_type varchar(32) NOT NULL DEFAULT 'five_two',
  calculation_unit varchar(16) NOT NULL DEFAULT 'hours',
  hours_per_day numeric(6,2) NOT NULL DEFAULT 8,
  workdays jsonb NOT NULL DEFAULT '[1,2,3,4,5]'::jsonb,
  cycle_anchor date,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee, effective_month),
  CHECK (effective_month = date_trunc('month', effective_month)::date),
  CHECK (schedule_type IN ('five_two', 'two_two', 'individual')),
  CHECK (calculation_unit IN ('hours', 'days')),
  CHECK (hours_per_day > 0 AND hours_per_day <= 24)
);

CREATE INDEX IF NOT EXISTS employee_work_schedules_lookup_idx
  ON employee_work_schedules(employee, effective_month DESC);

CREATE TABLE IF NOT EXISTS employee_timesheet_periods (
  id bigserial PRIMARY KEY,
  employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  month_start date NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'draft',
  norm_days numeric(6,2) NOT NULL DEFAULT 0,
  credited_days numeric(6,2) NOT NULL DEFAULT 0,
  norm_hours numeric(8,2) NOT NULL DEFAULT 0,
  credited_hours numeric(8,2) NOT NULL DEFAULT 0,
  worked_hours numeric(8,2) NOT NULL DEFAULT 0,
  overtime_hours numeric(8,2) NOT NULL DEFAULT 0,
  approved_by uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  closed_by uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  closed_at timestamptz,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee, month_start),
  CHECK (month_start = date_trunc('month', month_start)::date),
  CHECK (status IN ('draft', 'approved', 'closed'))
);

CREATE TABLE IF NOT EXISTS employee_timesheet_entries (
  id bigserial PRIMARY KEY,
  period bigint NOT NULL REFERENCES employee_timesheet_periods(id) ON DELETE CASCADE,
  employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  work_date date NOT NULL,
  day_status varchar(24) NOT NULL DEFAULT 'worked',
  planned_hours numeric(6,2) NOT NULL DEFAULT 0,
  started_at time,
  ended_at time,
  break_minutes integer NOT NULL DEFAULT 0,
  worked_hours numeric(6,2) NOT NULL DEFAULT 0,
  credited_hours numeric(6,2) NOT NULL DEFAULT 0,
  overtime_hours numeric(6,2) NOT NULL DEFAULT 0,
  comment text,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee, work_date),
  CHECK (day_status IN ('worked', 'weekend', 'paid_leave', 'sick_leave', 'business_trip', 'unpaid_leave', 'day_off', 'absence')),
  CHECK (planned_hours >= 0 AND planned_hours <= 24),
  CHECK (break_minutes >= 0 AND break_minutes <= 1440)
);

CREATE INDEX IF NOT EXISTS employee_timesheet_entries_period_idx
  ON employee_timesheet_entries(period, work_date);

CREATE OR REPLACE FUNCTION calculate_employee_timesheet_entry()
RETURNS trigger AS $$
DECLARE
  calculated numeric(6,2);
BEGIN
  IF EXISTS (SELECT 1 FROM employee_timesheet_periods p WHERE p.id = NEW.period AND p.status = 'closed') THEN
    RAISE EXCEPTION 'Закрытый табель нельзя изменять';
  END IF;

  IF NEW.started_at IS NOT NULL AND NEW.ended_at IS NOT NULL THEN
    calculated := ROUND((EXTRACT(epoch FROM (NEW.ended_at - NEW.started_at)) / 3600.0 - NEW.break_minutes / 60.0)::numeric, 2);
    IF calculated < 0 THEN calculated := calculated + 24; END IF;
    NEW.worked_hours := GREATEST(calculated, 0);
  ELSIF NEW.day_status = 'worked' AND COALESCE(NEW.worked_hours, 0) = 0 THEN
    NEW.worked_hours := NEW.planned_hours;
  ELSIF NEW.day_status <> 'worked' THEN
    NEW.worked_hours := 0;
  END IF;

  IF NEW.day_status IN ('paid_leave', 'sick_leave', 'business_trip') THEN
    NEW.credited_hours := NEW.planned_hours;
    NEW.overtime_hours := 0;
  ELSIF NEW.day_status = 'worked' THEN
    NEW.credited_hours := LEAST(NEW.worked_hours, NEW.planned_hours);
    NEW.overtime_hours := GREATEST(NEW.worked_hours - NEW.planned_hours, 0);
  ELSE
    NEW.credited_hours := 0;
    NEW.overtime_hours := 0;
  END IF;
  NEW.date_updated := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employee_timesheet_entries_10_calculate ON employee_timesheet_entries;
CREATE TRIGGER employee_timesheet_entries_10_calculate
BEFORE INSERT OR UPDATE ON employee_timesheet_entries
FOR EACH ROW EXECUTE FUNCTION calculate_employee_timesheet_entry();

CREATE OR REPLACE FUNCTION protect_closed_employee_timesheet_entry()
RETURNS trigger AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM employee_timesheet_periods p WHERE p.id = OLD.period AND p.status = 'closed') THEN
    RAISE EXCEPTION 'Закрытый табель нельзя изменять';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employee_timesheet_entries_05_protect_delete ON employee_timesheet_entries;
CREATE TRIGGER employee_timesheet_entries_05_protect_delete
BEFORE DELETE ON employee_timesheet_entries
FOR EACH ROW EXECUTE FUNCTION protect_closed_employee_timesheet_entry();

CREATE OR REPLACE FUNCTION refresh_employee_timesheet_period(period_id bigint)
RETURNS void AS $$
BEGIN
  UPDATE employee_timesheet_periods p
  SET norm_days = stats.norm_days,
      credited_days = stats.credited_days,
      norm_hours = stats.norm_hours,
      credited_hours = stats.credited_hours,
      worked_hours = stats.worked_hours,
      overtime_hours = stats.overtime_hours,
      date_updated = now()
  FROM (
    SELECT
      e.period,
      COUNT(*) FILTER (WHERE e.planned_hours > 0)::numeric AS norm_days,
      COUNT(*) FILTER (WHERE e.planned_hours > 0 AND e.credited_hours > 0)::numeric AS credited_days,
      ROUND(COALESCE(SUM(e.planned_hours), 0), 2) AS norm_hours,
      ROUND(COALESCE(SUM(e.credited_hours), 0), 2) AS credited_hours,
      ROUND(COALESCE(SUM(e.worked_hours), 0), 2) AS worked_hours,
      ROUND(COALESCE(SUM(e.overtime_hours), 0), 2) AS overtime_hours
    FROM employee_timesheet_entries e
    WHERE e.period = period_id
    GROUP BY e.period
  ) stats
  WHERE p.id = stats.period;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_employee_timesheet_after_entry()
RETURNS trigger AS $$
BEGIN
  PERFORM refresh_employee_timesheet_period(COALESCE(NEW.period, OLD.period));
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employee_timesheet_entries_90_refresh ON employee_timesheet_entries;
CREATE TRIGGER employee_timesheet_entries_90_refresh
AFTER INSERT OR UPDATE OR DELETE ON employee_timesheet_entries
FOR EACH ROW EXECUTE FUNCTION refresh_employee_timesheet_after_entry();

ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS salary_fixed_earned numeric(14,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS norm_days numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS credited_days numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS norm_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS credited_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS worked_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS overtime_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_summary ADD COLUMN IF NOT EXISTS timesheet_status varchar(16);

ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS salary_fixed_earned numeric(14,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS norm_days numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS credited_days numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS norm_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS credited_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS worked_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS overtime_hours numeric(8,2) DEFAULT 0;
ALTER TABLE employee_salary_monthly ADD COLUMN IF NOT EXISTS timesheet_status varchar(16);

CREATE OR REPLACE FUNCTION apply_employee_compensation_history()
RETURNS void AS $$
BEGIN
  WITH calculated AS (
    SELECT
      monthly.id AS monthly_id,
      COALESCE(rate.salary_fixed, monthly.salary_fixed, 0) AS salary_fixed,
      COALESCE(rate.order_percent, monthly.order_percent, 0) AS order_percent,
      period.id AS period_id,
      COALESCE(period.norm_days, 0) AS norm_days,
      COALESCE(period.credited_days, 0) AS credited_days,
      COALESCE(period.norm_hours, 0) AS norm_hours,
      COALESCE(period.credited_hours, 0) AS credited_hours,
      COALESCE(period.worked_hours, 0) AS worked_hours,
      COALESCE(period.overtime_hours, 0) AS overtime_hours,
      period.status AS timesheet_status,
      ROUND(CASE
        WHEN period.id IS NULL THEN COALESCE(rate.salary_fixed, monthly.salary_fixed, 0)
        WHEN COALESCE(schedule.calculation_unit, 'hours') = 'days' AND period.norm_days > 0
          THEN COALESCE(rate.salary_fixed, monthly.salary_fixed, 0) * LEAST(period.credited_days / period.norm_days, 1)
        WHEN period.norm_hours > 0
          THEN COALESCE(rate.salary_fixed, monthly.salary_fixed, 0) * LEAST(period.credited_hours / period.norm_hours, 1)
        ELSE 0 END, 2) AS salary_fixed_earned
    FROM employee_salary_monthly monthly
    LEFT JOIN LATERAL (
      SELECT history.salary_fixed, history.order_percent
      FROM employee_compensation_rates history
      WHERE history.employee = monthly.employee AND history.effective_month <= monthly.month_start
      ORDER BY history.effective_month DESC LIMIT 1
    ) rate ON true
    LEFT JOIN employee_timesheet_periods period
      ON period.employee = monthly.employee AND period.month_start = monthly.month_start
    LEFT JOIN LATERAL (
      SELECT s.calculation_unit
      FROM employee_work_schedules s
      WHERE s.employee = monthly.employee AND s.effective_month <= monthly.month_start
      ORDER BY s.effective_month DESC LIMIT 1
    ) schedule ON true
  )
  UPDATE employee_salary_monthly monthly
  SET salary_fixed = calculated.salary_fixed,
      order_percent = calculated.order_percent,
      norm_days = calculated.norm_days,
      credited_days = calculated.credited_days,
      norm_hours = calculated.norm_hours,
      credited_hours = calculated.credited_hours,
      worked_hours = calculated.worked_hours,
      overtime_hours = calculated.overtime_hours,
      timesheet_status = calculated.timesheet_status,
      salary_fixed_earned = calculated.salary_fixed_earned,
      commission_accrued = ROUND(monthly.paid_orders_sum * calculated.order_percent / 100, 2),
      salary_accrued = ROUND(
        calculated.salary_fixed_earned
        + monthly.paid_orders_sum * calculated.order_percent / 100
        + COALESCE(monthly.bonus_paid, 0), 2),
      salary_debt = ROUND(
        calculated.salary_fixed_earned
        + monthly.paid_orders_sum * calculated.order_percent / 100
        + COALESCE(monthly.bonus_paid, 0)
        - COALESCE(monthly.salary_paid, 0) - COALESCE(monthly.advances_paid, 0), 2)
  FROM calculated
  WHERE calculated.monthly_id = monthly.id;

  UPDATE employee_salary_summary summary
  SET salary_fixed_earned = monthly.salary_fixed_earned,
      norm_days = monthly.norm_days,
      credited_days = monthly.credited_days,
      norm_hours = monthly.norm_hours,
      credited_hours = monthly.credited_hours,
      worked_hours = monthly.worked_hours,
      overtime_hours = monthly.overtime_hours,
      timesheet_status = monthly.timesheet_status,
      salary_accrued = monthly.salary_accrued,
      salary_debt = monthly.salary_debt
  FROM employee_salary_monthly monthly
  WHERE summary.employee = monthly.employee
    AND summary.month_start = monthly.month_start;
END;
$$ LANGUAGE plpgsql;

SELECT refresh_employee_salary_tables();
SELECT apply_employee_compensation_history();
SELECT refresh_finance_dashboard_metrics();
SELECT apply_employee_compensation_history();

COMMIT;

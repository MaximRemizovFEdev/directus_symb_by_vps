const ALLOWED_ROLES = new Set(['Administrator', 'Управляющий']);
const SCHEDULE_TYPES = new Set(['five_two', 'two_two', 'individual']);
const CALCULATION_UNITS = new Set(['hours', 'days']);
const DAY_STATUSES = new Set(['worked', 'weekend', 'paid_leave', 'sick_leave', 'business_trip', 'unpaid_leave', 'day_off', 'absence']);
const PERIOD_STATUSES = new Set(['draft', 'approved', 'closed']);

function monthStart(value) {
  const match = String(value || '').match(/^(\d{4})-(0[1-9]|1[0-2])/);
  if (!match) return null;
  return `${match[1]}-${match[2]}-01`;
}

function dateOnly(value) {
  const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/);
  return match?.[1] || null;
}

function number(value, fallback = 0) {
  const parsed = Number(String(value ?? '').replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : fallback;
}

function timeOnly(value) {
  const match = String(value || '').match(/^(\d{2}:\d{2})/);
  return match?.[1] || null;
}

function isoWeekday(date) {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

function datesInMonth(month) {
  const [year, monthNumber] = month.split('-').map(Number);
  const last = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  return Array.from({ length: last }, (_, index) => `${month}-${String(index + 1).padStart(2, '0')}`);
}

export default {
  id: 'symbolika-timekeeping',
  handler: (router, { database }) => {
    const requireAccess = async (req, res) => {
      const userId = req.accountability?.user;
      if (!userId) {
        res.status(401).json({ errors: [{ message: 'Требуется авторизация.' }] });
        return null;
      }
      const row = await database('directus_users as u')
        .leftJoin('directus_roles as r', 'r.id', 'u.role')
        .where('u.id', userId)
        .first('u.id', 'r.name as role_name');
      if (!row || !ALLOWED_ROLES.has(row.role_name)) {
        res.status(403).json({ errors: [{ message: 'Табель доступен администратору и управляющему.' }] });
        return null;
      }
      return row;
    };

    const refreshFinance = async (trx) => {
      await trx.raw('SELECT refresh_employee_salary_tables()');
      await trx.raw('SELECT apply_employee_compensation_history()');
      await trx.raw('SELECT refresh_finance_dashboard_metrics()');
      await trx.raw('SELECT apply_employee_compensation_history()');
    };

    const scheduleFor = async (trx, employee, month) => {
      const row = await trx('employee_work_schedules')
        .where('employee', employee)
        .where('effective_month', '<=', month)
        .orderBy('effective_month', 'desc')
        .first();
      return row || {
        employee,
        effective_month: month,
        schedule_type: 'five_two',
        calculation_unit: 'hours',
        hours_per_day: 8,
        workdays: [1, 2, 3, 4, 5],
        cycle_anchor: month,
      };
    };

    router.get('/month', async (req, res, next) => {
      try {
        if (!await requireAccess(req, res)) return;
        const employee = Number(req.query.employee);
        const month = monthStart(req.query.month);
        if (!employee || !month) return res.status(400).json({ errors: [{ message: 'Укажите сотрудника и месяц.' }] });
        const period = await database('employee_timesheet_periods').where({ employee, month_start: month }).first();
        const schedule = await scheduleFor(database, employee, month);
        const entries = period
          ? await database('employee_timesheet_entries').where('period', period.id).orderBy('work_date')
          : [];
        res.json({ data: { period: period || null, schedule, entries } });
      } catch (error) { next(error); }
    });

    router.put('/schedule', async (req, res, next) => {
      try {
        if (!await requireAccess(req, res)) return;
        const employee = Number(req.body?.employee);
        const effectiveMonth = monthStart(req.body?.effective_month);
        const scheduleType = SCHEDULE_TYPES.has(req.body?.schedule_type) ? req.body.schedule_type : 'five_two';
        const calculationUnit = CALCULATION_UNITS.has(req.body?.calculation_unit) ? req.body.calculation_unit : 'hours';
        const hoursPerDay = Math.min(Math.max(number(req.body?.hours_per_day, 8), 0.25), 24);
        const requestedWorkdays = Array.isArray(req.body?.workdays)
          ? [...new Set(req.body.workdays.map(Number).filter((day) => day >= 1 && day <= 7))]
          : [1, 2, 3, 4, 5];
        const workdays = scheduleType === 'five_two' ? [1, 2, 3, 4, 5] : requestedWorkdays;
        if (!employee || !effectiveMonth) return res.status(400).json({ errors: [{ message: 'Укажите сотрудника и месяц действия графика.' }] });
        const payload = {
          employee,
          effective_month: effectiveMonth,
          schedule_type: scheduleType,
          calculation_unit: calculationUnit,
          hours_per_day: hoursPerDay,
          workdays: JSON.stringify(workdays),
          cycle_anchor: dateOnly(req.body?.cycle_anchor) || effectiveMonth,
          date_updated: database.fn.now(),
        };
        const rows = await database('employee_work_schedules')
          .insert(payload)
          .onConflict(['employee', 'effective_month'])
          .merge(payload)
          .returning('*');
        res.json({ data: rows[0] });
      } catch (error) { next(error); }
    });

    router.post('/generate', async (req, res, next) => {
      try {
        const actor = await requireAccess(req, res);
        if (!actor) return;
        const employee = Number(req.body?.employee);
        const month = monthStart(req.body?.month);
        if (!employee || !month) return res.status(400).json({ errors: [{ message: 'Укажите сотрудника и месяц.' }] });
        await database.transaction(async (trx) => {
          const existing = await trx('employee_timesheet_periods').where({ employee, month_start: month }).first();
          if (existing) return;
          const schedule = await scheduleFor(trx, employee, month);
          const [period] = await trx('employee_timesheet_periods').insert({ employee, month_start: month }).returning('*');
          const workdays = Array.isArray(schedule.workdays) ? schedule.workdays.map(Number) : [1, 2, 3, 4, 5];
          const anchor = new Date(`${dateOnly(schedule.cycle_anchor) || month}T12:00:00Z`);
          const entries = datesInMonth(month.slice(0, 7)).map((workDate) => {
            let scheduled = workdays.includes(isoWeekday(workDate));
            if (schedule.schedule_type === 'two_two') {
              const current = new Date(`${workDate}T12:00:00Z`);
              const distance = Math.floor((current - anchor) / 86400000);
              scheduled = ((distance % 4) + 4) % 4 < 2;
            }
            return {
              period: period.id,
              employee,
              work_date: workDate,
              day_status: scheduled ? 'worked' : 'weekend',
              planned_hours: scheduled ? number(schedule.hours_per_day, 8) : 0,
              worked_hours: scheduled ? number(schedule.hours_per_day, 8) : 0,
            };
          });
          await trx('employee_timesheet_entries').insert(entries);
          await trx.raw('SELECT refresh_employee_timesheet_period(?)', [period.id]);
          await refreshFinance(trx);
        });
        const period = await database('employee_timesheet_periods').where({ employee, month_start: month }).first();
        const entries = await database('employee_timesheet_entries').where('period', period.id).orderBy('work_date');
        res.json({ data: { period, entries } });
      } catch (error) { next(error); }
    });

    router.patch('/day/:id', async (req, res, next) => {
      try {
        if (!await requireAccess(req, res)) return;
        const id = Number(req.params.id);
        if (!id) return res.status(400).json({ errors: [{ message: 'Некорректный день табеля.' }] });
        const dayStatus = DAY_STATUSES.has(req.body?.day_status) ? req.body.day_status : 'worked';
        let saved;
        await database.transaction(async (trx) => {
          const current = await trx('employee_timesheet_entries as e')
            .join('employee_timesheet_periods as p', 'p.id', 'e.period')
            .where('e.id', id).first('e.*', 'p.status as period_status');
          if (!current) throw Object.assign(new Error('День табеля не найден.'), { status: 404 });
          if (current.period_status === 'closed') throw Object.assign(new Error('Закрытый табель нельзя изменять.'), { status: 409 });
          const payload = {
            day_status: dayStatus,
            started_at: timeOnly(req.body?.started_at),
            ended_at: timeOnly(req.body?.ended_at),
            break_minutes: Math.max(0, Math.round(number(req.body?.break_minutes, 0))),
            worked_hours: Math.max(0, number(req.body?.worked_hours, 0)),
            comment: String(req.body?.comment || '').trim() || null,
            date_updated: trx.fn.now(),
          };
          [saved] = await trx('employee_timesheet_entries').where('id', id).update(payload).returning('*');
          await trx.raw('SELECT refresh_employee_timesheet_period(?)', [current.period]);
          await refreshFinance(trx);
        });
        res.json({ data: saved });
      } catch (error) { next(error); }
    });

    router.patch('/period/:id', async (req, res, next) => {
      try {
        const actor = await requireAccess(req, res);
        if (!actor) return;
        const id = Number(req.params.id);
        const status = PERIOD_STATUSES.has(req.body?.status) ? req.body.status : null;
        if (!id || !status) return res.status(400).json({ errors: [{ message: 'Некорректный статус табеля.' }] });
        let saved;
        await database.transaction(async (trx) => {
          const current = await trx('employee_timesheet_periods').where('id', id).first();
          if (!current) throw Object.assign(new Error('Табель не найден.'), { status: 404 });
          const payload = { status, date_updated: trx.fn.now() };
          if (status === 'approved') Object.assign(payload, { approved_by: actor.id, approved_at: trx.fn.now(), closed_by: null, closed_at: null });
          if (status === 'closed') Object.assign(payload, { closed_by: actor.id, closed_at: trx.fn.now() });
          if (status === 'draft') Object.assign(payload, { approved_by: null, approved_at: null, closed_by: null, closed_at: null });
          [saved] = await trx('employee_timesheet_periods').where('id', id).update(payload).returning('*');
          await refreshFinance(trx);
        });
        res.json({ data: saved });
      } catch (error) { next(error); }
    });
  },
};

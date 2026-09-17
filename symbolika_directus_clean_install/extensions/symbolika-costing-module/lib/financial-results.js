const numberValue = (value) => {
  const normalized = typeof value === 'string' ? value.replace(',', '.') : value;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
};

const normalizedItemStatus = (value) => String(value || '').trim().toLowerCase();

export const orderMarginBeforePayroll = (row) => (
  numberValue(row?.profit_sum) + numberValue(row?.manager_commission_sum)
);

export const orderMarginPercentBeforePayroll = (row) => {
  const revenue = numberValue(row?.order_sum);
  return revenue > 0 ? orderMarginBeforePayroll(row) / revenue * 100 : 0;
};

export function buildMonthlyFinancialRows({
  costingRows = [],
  expenseRows = [],
  salaryRows = [],
  monthKey,
  monthLabel,
  orderKey,
} = {}) {
  const months = new Map();
  const ensure = (dateValue) => {
    const key = monthKey(dateValue);
    if (!key) return null;
    if (!months.has(key)) {
      months.set(key, {
        key,
        label: monthLabel(key),
        order_margin: 0,
        completed_order_margin: 0,
        other_expenses: 0,
        salary_expenses: 0,
        salary_fixed: 0,
        salary_commission: 0,
        salary_bonus: 0,
        result: 0,
        actual_result: 0,
        orders_count: new Set(),
        completed_orders_count: new Set(),
        items_count: 0,
        completed_items_count: 0,
      });
    }
    return months.get(key);
  };

  const orders = new Map();
  costingRows.forEach((row, index) => {
    if (normalizedItemStatus(row?.item_status) === 'cancelled') return;
    const key = orderKey(row) || `item:${row?.id ?? index}`;
    if (!orders.has(key)) orders.set(key, { key, date: row?.date, rows: [] });
    orders.get(key).rows.push(row);
  });

  orders.forEach((order) => {
    const month = ensure(order.date);
    if (!month) return;
    const margin = order.rows.reduce((sum, row) => sum + orderMarginBeforePayroll(row), 0);
    const completed = order.rows.length > 0
      && order.rows.every((row) => normalizedItemStatus(row?.item_status) === 'delivered');

    month.order_margin += margin;
    month.orders_count.add(order.key);
    month.items_count += order.rows.length;
    if (completed) {
      month.completed_order_margin += margin;
      month.completed_orders_count.add(order.key);
      month.completed_items_count += order.rows.length;
    }
  });

  expenseRows.forEach((row) => {
    if (['contractor_payment', 'salary_payment', 'employee_advance', 'employee_bonus'].includes(row?.expense_type)) return;
    const month = ensure(row?.accounting_month || row?.expense_date);
    if (month) month.other_expenses += numberValue(row?.amount);
  });

  // Salary history is generated for a rolling period. Only attach it to
  // months that contain order or operating-expense activity so an employee's
  // current rate does not create synthetic results before accounting began.
  salaryRows.forEach((row) => {
    const key = monthKey(row?.month_start);
    const month = key ? months.get(key) : null;
    if (!month) return;
    month.salary_expenses += numberValue(row?.salary_accrued);
    month.salary_fixed += numberValue(row?.salary_fixed);
    month.salary_commission += numberValue(row?.commission_accrued);
    month.salary_bonus += numberValue(row?.bonus_paid);
  });

  return Array.from(months.values())
    .map((month) => ({
      ...month,
      orders_count_value: month.orders_count.size,
      completed_orders_count_value: month.completed_orders_count.size,
      operational_expenses: month.other_expenses + month.salary_expenses,
      clean_profit: month.order_margin,
      result: month.order_margin - month.other_expenses - month.salary_expenses,
      // Compare like with like: monthly payroll and operating expenses belong
      // to the complete monthly order margin. The completed-order margin stays
      // available as a separate progress indicator, not as the income side of
      // a result that subtracts the whole month's expenses.
      actual_result: month.order_margin - month.other_expenses - month.salary_expenses,
    }))
    .sort((left, right) => right.key.localeCompare(left.key));
}

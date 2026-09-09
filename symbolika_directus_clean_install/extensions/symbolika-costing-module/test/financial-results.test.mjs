import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  buildMonthlyFinancialRows,
  orderMarginBeforePayroll,
  orderMarginPercentBeforePayroll,
} from '../lib/financial-results.js';

const monthKey = (value) => String(value || '').slice(0, 7);
const monthLabel = (value) => value;
const orderKey = (row) => row.order;
const moduleSource = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

test('separates order margin, accrued payroll and other expenses without double counting', () => {
  const [row] = buildMonthlyFinancialRows({
    costingRows: [
      { id: 1, order: 10, date: '2026-08-02', item_status: 'delivered', profit_sum: 90, manager_commission_sum: 10 },
      { id: 2, order: 20, date: '2026-08-03', item_status: 'in_work', profit_sum: 180, manager_commission_sum: 20 },
      { id: 3, order: 30, date: '2026-08-04', item_status: 'cancelled', profit_sum: 999, manager_commission_sum: 1 },
    ],
    expenseRows: [
      { expense_type: 'rent', amount: 50, expense_date: '2026-09-01', accounting_month: '2026-08-01' },
      { expense_type: 'salary_payment', amount: 40, expense_date: '2026-09-08', accounting_month: '2026-08-01' },
      { expense_type: 'employee_advance', amount: 15, expense_date: '2026-08-28', accounting_month: '2026-08-01' },
      { expense_type: 'employee_bonus', amount: 5, expense_date: '2026-08-01', accounting_month: '2026-08-01' },
      { expense_type: 'contractor_payment', amount: 70, expense_date: '2026-08-20', accounting_month: '2026-08-01' },
    ],
    salaryRows: [
      { month_start: '2026-08-01', salary_fixed: 40, commission_accrued: 10, bonus_paid: 5, salary_accrued: 55 },
    ],
    monthKey,
    monthLabel,
    orderKey,
  });

  assert.equal(row.order_margin, 300);
  assert.equal(row.completed_order_margin, 100);
  assert.equal(row.other_expenses, 50);
  assert.equal(row.salary_expenses, 55);
  assert.equal(row.operational_expenses, 105);
  assert.equal(row.result, 195);
  assert.equal(row.actual_result, 195);
  assert.equal(row.orders_count_value, 2);
  assert.equal(row.completed_orders_count_value, 1);
  assert.equal(row.items_count, 2);
  assert.equal(row.completed_items_count, 1);
});

test('recognizes an order only after every active position is delivered', () => {
  const [row] = buildMonthlyFinancialRows({
    costingRows: [
      { id: 1, order: 10, date: '2026-09-02', item_status: 'delivered', profit_sum: 90, manager_commission_sum: 10 },
      { id: 2, order: 10, date: '2026-09-02', item_status: 'ready', profit_sum: 45, manager_commission_sum: 5 },
    ],
    monthKey,
    monthLabel,
    orderKey,
  });

  assert.equal(row.order_margin, 150);
  assert.equal(row.completed_order_margin, 0);
  assert.equal(row.completed_orders_count_value, 0);
  assert.equal(row.completed_items_count, 0);
  assert.equal(row.actual_result, 150);
});

test('uses the same margin before payroll in order economics and monthly results', () => {
  const item = {
    order_sum: 1000,
    profit_sum: 820,
    manager_commission_sum: 30,
  };

  assert.equal(orderMarginBeforePayroll(item), 850);
  assert.equal(orderMarginPercentBeforePayroll(item), 85);

  const [month] = buildMonthlyFinancialRows({
    costingRows: [{ ...item, id: 1, order: 10, date: '2026-09-02', item_status: 'delivered' }],
    monthKey,
    monthLabel,
    orderKey,
  });
  assert.equal(month.order_margin, orderMarginBeforePayroll(item));
});

test('separates external contractor debt from internal payroll debt on the dashboard', () => {
  const dashboard = moduleSource.match(
    /<section class="symbolika-finance-balance-grid">(?<body>[\s\S]*?)<\/section>/,
  )?.groups?.body || '';
  const exportRows = moduleSource.match(
    /if \(this\.activeTab === 'admin_finance_dashboard'\) \{(?<body>[\s\S]*?)\n      \}/,
  )?.groups?.body || '';

  assert.match(dashboard, /Долг контрагентам[\s\S]*financeDashboardMetrics\.contractorDebt/);
  assert.match(dashboard, /Долг сотрудникам[\s\S]*financeDashboardMetrics\.salaryDebt/);
  assert.match(dashboard, /Переплаты клиентов[\s\S]*financeDashboardMetrics\.customerOverpay/);
  assert.doesNotMatch(dashboard, /financeDashboardMetrics\.ourDebt|Контрагенты, зарплата и переплаты/);
  assert.match(exportRows, /metrics\.contractorDebt/);
  assert.match(exportRows, /metrics\.salaryDebt/);
  assert.match(exportRows, /metrics\.customerOverpay/);
});

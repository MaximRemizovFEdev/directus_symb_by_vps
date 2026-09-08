const numberValue = (value) => {
  const parsed = Number(typeof value === 'string' ? value.replace(',', '.') : value);
  return Number.isFinite(parsed) ? parsed : 0;
};

const entityId = (value) => String(value && typeof value === 'object' ? (value.id ?? '') : (value ?? ''));

export function clientPaymentTargets(rows = [], { customerId = '', companyId = '' } = {}) {
  const customer = String(customerId || '');
  const company = String(companyId || '');

  return rows
    .filter((row) => {
      if (company) return entityId(row?.customer_company) === company;
      return customer
        && entityId(row?.customer) === customer
        && !entityId(row?.customer_company);
    })
    .filter((row) => numberValue(row?.payment_due) > 0)
    .filter((row) => row?.entry_type !== 'operation' || row?.direction === 'customer_owes_us')
    .map((row) => ({
      key: row.entry_type === 'operation' ? `operation:${row.client_operation}` : `order:${row.order_link}`,
      targetType: row.entry_type === 'operation' ? 'operation' : 'order',
      targetId: Number(row.entry_type === 'operation' ? row.client_operation : row.order_link),
      title: row.entry_type === 'operation'
        ? (row.description || row.order_number || 'Клиентская операция')
        : (row.order_number || 'Заказ'),
      date: row.date || '',
      due: numberValue(row.payment_due),
      allocation: '',
    }))
    .filter((row) => row.targetId)
    .sort((left, right) => String(left.date).localeCompare(String(right.date)) || left.targetId - right.targetId);
}

export function autoAllocateClientPayment(targets = [], amount = 0) {
  let remaining = Math.max(numberValue(amount), 0);
  return targets.map((target) => {
    const allocation = Math.min(Math.max(numberValue(target.due), 0), remaining);
    remaining = Math.max(remaining - allocation, 0);
    return { ...target, allocation: allocation > 0 ? String(allocation) : '' };
  });
}

export function clientPaymentAllocationSummary(targets = [], amount = 0) {
  const paymentAmount = Math.max(numberValue(amount), 0);
  const allocated = targets.reduce((sum, target) => sum + Math.max(numberValue(target.allocation), 0), 0);
  return {
    amount: paymentAmount,
    allocated,
    unallocated: Math.max(paymentAmount - allocated, 0),
    exceedsPayment: allocated > paymentAmount + 0.005,
    exceedsTarget: targets.some((target) => numberValue(target.allocation) > numberValue(target.due) + 0.005),
  };
}

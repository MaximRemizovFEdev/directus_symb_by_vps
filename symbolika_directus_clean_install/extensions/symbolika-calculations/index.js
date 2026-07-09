export default ({ filter, action }, { database, logger }) => {
  const num = (v) => Number.isFinite(Number(v)) ? Number(v) : 0;
  const round = (v) => Math.round(num(v) * 100) / 100;
  const isEmpty = (v) => v === null || v === undefined || v === '';

  const OFFICE_PICKUP = 'office_pickup';
  const NOT_IN_OFFICE = 'not_in_office';
  const IN_OFFICE = 'in_office';
  const ISSUED = 'issued';

  const prevOrders = new Map();
  const prevItems = new Map();
  const prevPayments = new Map();
  const prevContractorPayments = new Map();

  async function generateOrderNumber() {
    const last = await database('orders')
      .whereNotNull('order_number')
      .orderBy('id', 'desc')
      .first();

    let next = 1;

    if (last?.order_number) {
      const match = String(last.order_number).match(/(\d+)$/);
      if (match) next = Number(match[1]) + 1;
    }

    return `SO-${String(next).padStart(5, '0')}`;
  }

  async function getEmployeeByUser(userId) {
    if (!userId) return null;

    return await database('employees')
      .where({ directus_user: userId })
      .first();
  }

  async function getDeliveredStatusId() {
    const status = await database('order_statuses')
      .whereILike('name', 'Доставлен')
      .first();

    return status?.id || null;
  }

  async function getManagerPercent(orderId) {
    if (!orderId) return 0;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order?.manager_employee) return 0;

    const emp = await database('employees').where({ id: order.manager_employee }).first();
    return num(emp?.order_percent);
  }

  async function getTaxPercent(orderId) {
    if (!orderId) return 0;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order?.payment_type) return 0;

    const pt = await database('payment_types').where({ id: order.payment_type }).first();
    return num(pt?.tax_percent);
  }

  async function assignManagerToCustomerAndCompany(order) {
    if (!order?.manager_employee) return;

    if (order.customer) {
      const customer = await database('customers').where({ id: order.customer }).first();

      if (customer && !customer.manager) {
        await database('customers').where({ id: order.customer }).update({
          manager: order.manager_employee,
        });
      }
    }

    if (order.customer_company) {
      const company = await database('customer_companies').where({ id: order.customer_company }).first();

      if (company && !company.manager) {
        await database('customer_companies').where({ id: order.customer_company }).update({
          manager: order.manager_employee,
        });
      }
    }
  }

  async function ensureCustomerCompanyLink(order) {
    if (!order?.customer || !order?.customer_company) return;

    const exists = await database('customer_company_links')
      .where({
        customer: order.customer,
        customer_companies: order.customer_company,
      })
      .first();

    if (exists) return;

    const defaultLink = await database('customer_company_links')
      .where({
        customer: order.customer,
        is_default: true,
      })
      .first();

    await database('customer_company_links').insert({
      customer: order.customer,
      customer_companies: order.customer_company,
      is_default: defaultLink ? false : true,
    });
  }

  async function recalcCustomerBalance(customerId) {
    if (!customerId) return;

    const orders = await database('orders')
      .where({ customer: customerId })
      .whereNull('customer_company');

    const payments = await database('order_payments')
      .where({ customer: customerId })
      .whereNull('customer_company');

    const orders_total_sum = round(orders.reduce((s, x) => s + num(x.order_sum), 0));

    const payments_total_in = round(
      payments
        .filter((x) => x.payment_direction !== 'outgoing_refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const refunds_total_out = round(
      payments
        .filter((x) => x.payment_direction === 'outgoing_refund' || x.allocation_mode === 'refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_in - refunds_total_out - orders_total_sum);

    await database('customers').where({ id: customerId }).update({
      orders_total_sum,
      payments_total_in,
      refunds_total_out,
      balance,
      debt_to_us: balance < 0 ? Math.abs(balance) : 0,
      our_debt_to_customer: balance > 0 ? balance : 0,
    });
  }

  async function recalcCompanyBalance(companyId) {
    if (!companyId) return;

    const orders = await database('orders')
      .where({ customer_company: companyId });

    const payments = await database('order_payments')
      .where({ customer_company: companyId });

    const orders_total_sum = round(orders.reduce((s, x) => s + num(x.order_sum), 0));

    const payments_total_in = round(
      payments
        .filter((x) => x.payment_direction !== 'outgoing_refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const refunds_total_out = round(
      payments
        .filter((x) => x.payment_direction === 'outgoing_refund' || x.allocation_mode === 'refund')
        .reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_in - refunds_total_out - orders_total_sum);

    await database('customer_companies').where({ id: companyId }).update({
      orders_total_sum,
      payments_total_in,
      refunds_total_out,
      balance,
      debt_to_us: balance < 0 ? Math.abs(balance) : 0,
      our_debt_to_customer: balance > 0 ? balance : 0,
    });
  }

  async function recalcOrderParties(order, prevOrder = null) {
    if (prevOrder) {
      await recalcCustomerBalance(prevOrder.customer);
      await recalcCompanyBalance(prevOrder.customer_company);
    }

    if (order) {
      await recalcCustomerBalance(order.customer);
      await recalcCompanyBalance(order.customer_company);
    }
  }

  async function syncPaymentsFromOrder(orderId) {
    if (!orderId) return;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order) return;

    await database('order_payments')
      .where({ order: orderId })
      .update({
        customer: order.customer || null,
        customer_company: order.customer_company || null,
      });
  }

  async function recalcContractorBalance(contractorId) {
    if (!contractorId) return;

    const itemsAsFirst = await database('orders_items')
      .where({ contractor_1: contractorId });

    const itemsAsSecond = await database('orders_items')
      .where({ contractor_2: contractorId });

    const contractor1Cost = itemsAsFirst.reduce((s, x) => {
      return s + num(x.contractor_1_cost) * num(x.quantity);
    }, 0);

    const contractor2Cost = itemsAsSecond.reduce((s, x) => {
      return s + num(x.contractor_2_cost) * num(x.quantity);
    }, 0);

    const items_total_cost = round(contractor1Cost + contractor2Cost);

    const payments = await database('contractor_payments')
      .where({ contractor: contractorId });

    const payments_total_out = round(
      payments.reduce((s, x) => s + num(x.amount), 0)
    );

    const balance = round(payments_total_out - items_total_cost);

    await database('contractors').where({ id: contractorId }).update({
      items_total_cost,
      payments_total_out,
      balance,
      debt_to_contractor: balance < 0 ? Math.abs(balance) : 0,
      contractor_debt_to_us: balance > 0 ? balance : 0,
    });
  }

  async function recalcContractorsFromItem(item, prevItem = null) {
    const ids = new Set();

    if (item?.contractor_1) ids.add(item.contractor_1);
    if (item?.contractor_2) ids.add(item.contractor_2);
    if (prevItem?.contractor_1) ids.add(prevItem.contractor_1);
    if (prevItem?.contractor_2) ids.add(prevItem.contractor_2);

    for (const id of ids) {
      await recalcContractorBalance(id);
    }
  }

  async function syncItemsShippingFromOrder(orderId) {
    if (!orderId) return;

    const order = await database('orders').where({ id: orderId }).first();
    if (!order) return;

    await database('orders_items')
      .where({ order: orderId })
      .update({
        shipping_method: order.shipping_method || null,
        office_status: NOT_IN_OFFICE,
      });
  }

  async function setAllItemsOfficeStatus(orderId, officeStatus) {
    if (!orderId || !officeStatus) return;

    await database('orders_items')
      .where({ order: orderId })
      .update({
        office_status: officeStatus,
        shipping_method: officeStatus === NOT_IN_OFFICE ? null : OFFICE_PICKUP,
      });
  }

  async function recalcOfficeStatus(orderId) {
    if (!orderId) return;

    const items = await database('orders_items').where({ order: orderId });
    if (!items.length) return;

    const allIssued = items.every((item) => item.office_status === ISSUED);
    const allInOffice = items.every((item) => item.office_status === IN_OFFICE || item.office_status === ISSUED);

    const update = {};

    if (allIssued) {
      update.office_status = ISSUED;

      const deliveredId = await getDeliveredStatusId();
      if (deliveredId) update.order_status = deliveredId;
    } else if (allInOffice) {
      update.office_status = IN_OFFICE;
    } else {
      update.office_status = NOT_IN_OFFICE;
    }

    await database('orders').where({ id: orderId }).update(update);
  }

  async function recalcItem(id, prevItem = null) {
    const item = await database('orders_items').where({ id }).first();
    if (!item) return null;

    const order = item.order
      ? await database('orders').where({ id: item.order }).first()
      : null;

    const manager_employee = order?.manager_employee || null;

    let manager_percent = item.manager_percent;
    let tax_percent = item.tax_percent;

    if (isEmpty(manager_percent) || num(manager_percent) === 0) {
      manager_percent = await getManagerPercent(item.order);
    }

    if (isEmpty(tax_percent) || num(tax_percent) === 0) {
      tax_percent = await getTaxPercent(item.order);
    }

    let shipping_method = item.shipping_method;
    let office_status = item.office_status;

    if (!shipping_method && order?.shipping_method) {
      shipping_method = order.shipping_method;
    }

    if (!office_status) {
      office_status = NOT_IN_OFFICE;
    }

    const quantity = num(item.quantity);
    const price = num(item.price_per_unit);

    const contractor_1_cost = num(item.contractor_1_cost);
    const contractor_2_cost = num(item.contractor_2_cost);

    const unit_cost = round(contractor_1_cost + contractor_2_cost);
    const total_cost = round(unit_cost * quantity);

    const order_sum = round(quantity * price);
    const manager_commission_sum = round(order_sum * num(manager_percent) / 100);
    const tax_sum = round(order_sum * num(tax_percent) / 100);

    const profit_sum = round(order_sum - total_cost - manager_commission_sum - tax_sum);
    const margin_percent = order_sum > 0 ? round(profit_sum / order_sum * 100) : 0;

    await database('orders_items').where({ id }).update({
      manager_employee,
      manager_percent,
      tax_percent,
      shipping_method,
      office_status,
      unit_cost,
      order_sum,
      total_cost,
      manager_commission_sum,
      tax_sum,
      profit_sum,
      margin_percent,
    });

    const updatedItem = await database('orders_items').where({ id }).first();
    await recalcContractorsFromItem(updatedItem, prevItem);

    return item.order;
  }

  async function recalcOrder(orderId, prevOrder = null) {
    if (!orderId) return;

    const items = await database('orders_items').where({ order: orderId });

    const order_sum = round(items.reduce((s, x) => s + num(x.order_sum), 0));
    const items_total_cost = round(items.reduce((s, x) => s + num(x.total_cost), 0));
    const items_manager_commission_sum = round(items.reduce((s, x) => s + num(x.manager_commission_sum), 0));
    const items_tax_sum = round(items.reduce((s, x) => s + num(x.tax_sum), 0));

    const profit_sum = round(order_sum - items_total_cost - items_manager_commission_sum - items_tax_sum);
    const margin_percent = order_sum > 0 ? round(profit_sum / order_sum * 100) : 0;

    const allocations = await database('payment_allocations').where({ order: orderId });
    const paid_amount = round(allocations.reduce((s, x) => s + num(x.amount), 0));
    const payment_due = round(order_sum - paid_amount);

    const order = await database('orders').where({ id: orderId }).first();

    await database('orders').where({ id: orderId }).update({
      order_sum,
      items_total_cost,
      items_manager_commission_sum,
      items_tax_sum,
      profit_sum,
      margin_percent,
      paid_amount,
      payment_due,
      office_payment_due: order?.payment_on_receipt ? payment_due : 0,
    });

    const updatedOrder = await database('orders').where({ id: orderId }).first();

    await recalcOfficeStatus(orderId);
    await syncPaymentsFromOrder(orderId);
    await recalcOrderParties(updatedOrder, prevOrder);
  }

  async function recalcPayment(paymentId, prevPayment = null) {
    if (!paymentId) return;

    const payment = await database('order_payments').where({ id: paymentId }).first();
    if (!payment) return;

    const rows = await database('payment_allocations').where({ payment: paymentId });
    const allocated_amount = round(rows.reduce((s, x) => s + num(x.amount), 0));

    await database('order_payments').where({ id: paymentId }).update({
      allocated_amount,
      unallocated_amount: round(num(payment.amount) - allocated_amount),
    });

    const updatedPayment = await database('order_payments').where({ id: paymentId }).first();

    if (prevPayment) {
      await recalcCustomerBalance(prevPayment.customer);
      await recalcCompanyBalance(prevPayment.customer_company);
    }

    await recalcCustomerBalance(updatedPayment.customer);
    await recalcCompanyBalance(updatedPayment.customer_company);
  }

  // BEFORE CREATE ORDER
  filter('items.create', async (payload, meta, context) => {
    if (meta.collection !== 'orders') return payload;

    const next = { ...payload };
    const userId = context?.accountability?.user || meta?.accountability?.user;

    if (!next.order_number) {
      next.order_number = await generateOrderNumber();
    }

    if (!next.manager_employee && userId) {
      const emp = await getEmployeeByUser(userId);
      if (emp?.id) next.manager_employee = emp.id;
    }

    if (!next.office_status) {
      next.office_status = NOT_IN_OFFICE;
    }

    return next;
  });

  // CAPTURE OLD VALUES BEFORE UPDATE
  filter('items.update', async (payload, meta) => {
    const keys = meta?.keys || [];

    if (meta.collection === 'orders') {
      for (const id of keys) {
        const row = await database('orders').where({ id }).first();
        if (row) prevOrders.set(String(id), row);
      }
    }

    if (meta.collection === 'orders_items') {
      for (const id of keys) {
        const row = await database('orders_items').where({ id }).first();
        if (row) prevItems.set(String(id), row);
      }
    }

    if (meta.collection === 'order_payments') {
      for (const id of keys) {
        const row = await database('order_payments').where({ id }).first();
        if (row) prevPayments.set(String(id), row);
      }
    }

    if (meta.collection === 'contractor_payments') {
      for (const id of keys) {
        const row = await database('contractor_payments').where({ id }).first();
        if (row) prevContractorPayments.set(String(id), row);
      }
    }

    return payload;
  });

  // AFTER CREATE ORDER
  action('items.create', async (meta, context) => {
    try {
      const { collection, key } = meta;
      if (collection !== 'orders') return;

      const order = await database('orders').where({ id: key }).first();
      if (!order) return;

      const userId = context?.accountability?.user || meta?.accountability?.user;
      const update = {};

      if (!order.order_number) {
        update.order_number = await generateOrderNumber();
      }

      if (!order.manager_employee && userId) {
        const emp = await getEmployeeByUser(userId);
        if (emp?.id) update.manager_employee = emp.id;
      }

      if (!order.office_status) {
        update.office_status = NOT_IN_OFFICE;
      }

      if (Object.keys(update).length) {
        await database('orders').where({ id: key }).update(update);
      }

      const updatedOrder = await database('orders').where({ id: key }).first();

      await assignManagerToCustomerAndCompany(updatedOrder);
      await ensureCustomerCompanyLink(updatedOrder);
      await syncItemsShippingFromOrder(key);
      await syncPaymentsFromOrder(key);
      await recalcOrder(key);
    } catch (error) {
      logger.error(error);
    }
  });

  // UPDATE ORDER
  action('items.update', async ({ collection, keys, payload }) => {
    try {
      if (collection !== 'orders') return;

      for (const orderId of keys) {
        const prevOrder = prevOrders.get(String(orderId)) || null;
        prevOrders.delete(String(orderId));

        const order = await database('orders').where({ id: orderId }).first();

        await assignManagerToCustomerAndCompany(order);
        await ensureCustomerCompanyLink(order);

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'shipping_method')) {
          await syncItemsShippingFromOrder(orderId);
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'office_status')) {
          if (payload.office_status === IN_OFFICE) {
            await setAllItemsOfficeStatus(orderId, IN_OFFICE);
          }

          if (payload.office_status === ISSUED) {
            await setAllItemsOfficeStatus(orderId, ISSUED);

            const deliveredId = await getDeliveredStatusId();
            if (deliveredId) {
              await database('orders').where({ id: orderId }).update({
                order_status: deliveredId,
              });
            }
          }

          if (payload.office_status === NOT_IN_OFFICE) {
            await setAllItemsOfficeStatus(orderId, NOT_IN_OFFICE);
          }
        }

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'payment_type')) {
          const items = await database('orders_items').where({ order: orderId });

          for (const item of items) {
            await database('orders_items').where({ id: item.id }).update({
              tax_percent: null,
            });

            await recalcItem(item.id);
          }
        }

        await syncPaymentsFromOrder(orderId);
        await recalcOrder(orderId, prevOrder);

        const updatedOrder = await database('orders').where({ id: orderId }).first();
        await recalcOrderParties(updatedOrder, prevOrder);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER ITEMS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'orders_items') return;

      const orderId = await recalcItem(key);
      await recalcOrder(orderId);
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER ITEMS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'orders_items') return;

      for (const key of keys) {
        const prevItem = prevItems.get(String(key)) || null;
        prevItems.delete(String(key));

        const orderId = await recalcItem(key, prevItem);
        await recalcOrder(orderId);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER PAYMENTS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'order_payments') return;

      const payment = await database('order_payments').where({ id: key }).first();
      if (!payment) return;

      if (payment.order) {
        const order = await database('orders').where({ id: payment.order }).first();

        await database('order_payments').where({ id: key }).update({
          customer: payment.customer || order?.customer || null,
          customer_company: payment.customer_company || order?.customer_company || null,
        });
      }

      const updatedPayment = await database('order_payments').where({ id: key }).first();

      if (updatedPayment.order && updatedPayment.allocation_mode === 'to_order' && num(updatedPayment.amount) > 0) {
        const exists = await database('payment_allocations')
          .where({ payment: key, order: updatedPayment.order })
          .first();

        if (!exists) {
          await database('payment_allocations').insert({
            payment: key,
            order: updatedPayment.order,
            amount: updatedPayment.amount,
            comment: 'Автоматическое распределение',
          });
        }

        await recalcPayment(key);
        await recalcOrder(updatedPayment.order);
      } else {
        await recalcPayment(key);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // ORDER PAYMENTS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'order_payments') return;

      for (const key of keys) {
        const prevPayment = prevPayments.get(String(key)) || null;
        prevPayments.delete(String(key));

        const payment = await database('order_payments').where({ id: key }).first();

        if (payment?.order) {
          const order = await database('orders').where({ id: payment.order }).first();

          await database('order_payments').where({ id: key }).update({
            customer: order?.customer || null,
            customer_company: order?.customer_company || null,
          });
        }

        await recalcPayment(key, prevPayment);

        const updatedPayment = await database('order_payments').where({ id: key }).first();
        if (updatedPayment?.order) {
          await recalcOrder(updatedPayment.order);
        }

        if (prevPayment?.order && prevPayment.order !== updatedPayment?.order) {
          await recalcOrder(prevPayment.order);
        }
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // PAYMENT ALLOCATIONS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'payment_allocations') return;

      const allocation = await database('payment_allocations').where({ id: key }).first();
      if (!allocation) return;

      await recalcPayment(allocation.payment);
      await recalcOrder(allocation.order);
    } catch (error) {
      logger.error(error);
    }
  });

  // PAYMENT ALLOCATIONS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'payment_allocations') return;

      for (const key of keys) {
        const allocation = await database('payment_allocations').where({ id: key }).first();
        if (!allocation) continue;

        await recalcPayment(allocation.payment);
        await recalcOrder(allocation.order);
      }
    } catch (error) {
      logger.error(error);
    }
  });

  // CONTRACTOR PAYMENTS CREATE
  action('items.create', async ({ collection, key }) => {
    try {
      if (collection !== 'contractor_payments') return;

      const payment = await database('contractor_payments').where({ id: key }).first();
      if (!payment) return;

      await recalcContractorBalance(payment.contractor);
    } catch (error) {
      logger.error(error);
    }
  });

  // CONTRACTOR PAYMENTS UPDATE
  action('items.update', async ({ collection, keys }) => {
    try {
      if (collection !== 'contractor_payments') return;

      for (const key of keys) {
        const prevPayment = prevContractorPayments.get(String(key)) || null;
        prevContractorPayments.delete(String(key));

        const payment = await database('contractor_payments').where({ id: key }).first();

        if (prevPayment?.contractor) {
          await recalcContractorBalance(prevPayment.contractor);
        }

        if (payment?.contractor) {
          await recalcContractorBalance(payment.contractor);
        }
      }
    } catch (error) {
      logger.error(error);
    }
  });
};

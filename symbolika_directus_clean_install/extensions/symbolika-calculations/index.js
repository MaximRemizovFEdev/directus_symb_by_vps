import webPush from 'web-push';

export default ({ filter, action }, { database, logger, env }) => {
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
  let pushConfigured = false;
  let pushTableReady = false;

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
      .whereILike('name', '\u0414\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d')
      .first();

    return status?.id || null;
  }

  async function getReadyStatusId() {
    const status = await database('order_statuses')
      .whereILike('name', '\u0413\u043e\u0442\u043e\u0432')
      .first();

    return status?.id || null;
  }

  async function getRoleUserIds(roleName) {
    if (!roleName) return [];

    const role = await database('directus_roles')
      .where({ name: roleName })
      .first();

    if (!role?.id) return [];

    const users = await database('directus_users')
      .where({ role: role.id, status: 'active' })
      .select('id');

    return users.map((user) => user.id).filter(Boolean);
  }

  async function getEmployeeUserId(employeeId) {
    if (!employeeId) return null;

    const employee = await database('employees')
      .where({ id: employeeId })
      .first();

    return employee?.directus_user || null;
  }

  async function getOrderLabel(orderId) {
    if (!orderId) return '\u0437\u0430\u043a\u0430\u0437';

    const order = await database('orders')
      .where({ id: orderId })
      .first();

    return order?.order_number || `#${orderId}`;
  }

  async function getOrderStatusName(statusId) {
    if (!statusId) return '\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d';

    const status = await database('order_statuses')
      .where({ id: statusId })
      .first();

    return status?.name || String(statusId);
  }

  async function getProductionStatusName(statusId) {
    if (!statusId) return '\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d';

    const status = await database('production_statuses')
      .where({ id: statusId })
      .first();

    return status?.name || String(statusId);
  }

  async function ensurePushTable() {
    if (pushTableReady) return true;

    try {
      const exists = await database.schema.hasTable('symbolika_push_subscriptions');
      if (!exists) {
        await database.schema.createTable('symbolika_push_subscriptions', (table) => {
        table.increments('id').primary();
        table.uuid('user').notNullable();
        table.text('endpoint').notNullable().unique();
        table.jsonb('subscription').notNullable();
        table.text('user_agent');
        table.text('last_error');
        table.timestamp('created_at', { useTz: true }).defaultTo(database.fn.now());
        table.timestamp('updated_at', { useTz: true }).defaultTo(database.fn.now());
        });
      }
      pushTableReady = true;
      return true;
    } catch (error) {
      logger.warn(error);
      return false;
    }
  }

  function configurePush() {
    if (pushConfigured) return true;

    const publicKey = env?.SYMBOLIKA_PUSH_PUBLIC_KEY;
    const privateKey = env?.SYMBOLIKA_PUSH_PRIVATE_KEY;
    if (!publicKey || !privateKey) return false;

    webPush.setVapidDetails(
      env?.SYMBOLIKA_PUSH_SUBJECT || 'mailto:admin@symbcorp.ru',
      publicKey,
      privateKey
    );

    pushConfigured = true;
    return true;
  }

  function getNotificationUrl(collection, item) {
    if (!collection || item == null) return '/admin';
    return `/admin/content/${collection}/${item}`;
  }

  async function sendBrowserPush(recipient, subject, message, collection = null, item = null) {
    if (!recipient || !configurePush()) return;
    if (!await ensurePushTable()) return;

    const subscriptions = await database('symbolika_push_subscriptions')
      .where({ user: recipient })
      .select('id', 'subscription');

    if (!subscriptions.length) return;

    const payload = JSON.stringify({
      title: subject,
      body: message || '',
      url: getNotificationUrl(collection, item),
      tag: collection && item != null ? `${collection}:${item}` : undefined,
    });

    for (const row of subscriptions) {
      try {
        await webPush.sendNotification(row.subscription, payload);
        await database('symbolika_push_subscriptions')
          .where({ id: row.id })
          .update({ last_error: null, updated_at: database.fn.now() });
      } catch (error) {
        if (error?.statusCode === 404 || error?.statusCode === 410) {
          await database('symbolika_push_subscriptions').where({ id: row.id }).delete();
          continue;
        }

        await database('symbolika_push_subscriptions')
          .where({ id: row.id })
          .update({
            last_error: String(error?.message || error).slice(0, 500),
            updated_at: database.fn.now(),
          });
        logger.warn(error);
      }
    }
  }

  async function notifyUser(recipient, subject, message, collection = null, item = null) {
    if (!recipient || !subject) return;

    await database('directus_notifications').insert({
      status: 'inbox',
      recipient,
      subject,
      message,
      collection,
      item: item == null ? null : String(item),
    });

    await sendBrowserPush(recipient, subject, message, collection, item);
  }

  async function notifyUsers(recipients, subject, message, collection = null, item = null) {
    const uniqueRecipients = Array.from(new Set((recipients || []).filter(Boolean)));

    for (const recipient of uniqueRecipients) {
      await notifyUser(recipient, subject, message, collection, item);
    }
  }

  async function notifyManager(employeeId, subject, message, collection = null, item = null) {
    const userId = await getEmployeeUserId(employeeId);
    await notifyUser(userId, subject, message, collection, item);
  }

  async function notifyOrderStatusChanged(order, prevOrder) {
    if (!order || !prevOrder) return;
    if (order.order_status === prevOrder.order_status) return;

    const managerUserId = await getEmployeeUserId(order.manager_employee);
    if (!managerUserId) return;

    const orderLabel = order.order_number || `#${order.id}`;
    const prevStatus = await getOrderStatusName(prevOrder.order_status);
    const nextStatus = await getOrderStatusName(order.order_status);

    await notifyUser(
      managerUserId,
      `\u0418\u0437\u043c\u0435\u043d\u0438\u043b\u0441\u044f \u0441\u0442\u0430\u0442\u0443\u0441 \u0437\u0430\u043a\u0430\u0437\u0430 ${orderLabel}`,
      `\u0421\u0442\u0430\u0442\u0443\u0441: ${prevStatus} \u2192 ${nextStatus}.`,
      'orders',
      order.id
    );
  }

  function contractorMatches(contractorName, pattern) {
    return String(contractorName || '').toLowerCase().includes(pattern);
  }

  async function getItemContractors(item) {
    const ids = [item?.contractor_1, item?.contractor_2].filter(Boolean);
    if (!ids.length) return [];

    return await database('contractors')
      .whereIn('id', ids)
      .select('id', 'name');
  }

  async function notifyNewProductionAssignments(item, prevItem = null) {
    if (!item?.id) return;

    const contractors = await getItemContractors(item);
    if (!contractors.length) return;

    const prevContractorIds = new Set([prevItem?.contractor_1, prevItem?.contractor_2].filter(Boolean));
    const orderLabel = await getOrderLabel(item.order);
    const productName = item.product_name || '\u041f\u043e\u0437\u0438\u0446\u0438\u044f';
    const quantity = item.quantity ? `, ${item.quantity} \u0448\u0442.` : '';

    for (const contractor of contractors) {
      if (prevContractorIds.has(contractor.id)) continue;

      let roleName = null;
      if (contractorMatches(contractor.name, '\u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432')) {
        roleName = '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e';
      }
      if (contractorMatches(contractor.name, '\u0448\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444')) {
        roleName = '\u0428\u0435\u043b\u043a\u043e\u0433\u0440\u0430\u0444\u0438\u044f';
      }
      if (!roleName) continue;

      const recipients = await getRoleUserIds(roleName);

      await notifyUsers(
        recipients,
        `\u041d\u043e\u0432\u0430\u044f \u043f\u043e\u0437\u0438\u0446\u0438\u044f \u0432 ${roleName}`,
        `${orderLabel}: ${productName}${quantity}.`,
        'orders_items',
        item.id
      );
    }
  }

  async function notifyLayoutRevisionIfNeeded(item, prevItem = null) {
    if (!item?.id || !item.manager_employee) return;
    if (item.production_status === prevItem?.production_status) return;

    const nextStatus = await getProductionStatusName(item.production_status);
    if (nextStatus !== '\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430') return;

    const orderLabel = await getOrderLabel(item.order);
    const productName = item.product_name || '\u041f\u043e\u0437\u0438\u0446\u0438\u044f';

    await notifyManager(
      item.manager_employee,
      `\u041d\u0443\u0436\u043d\u0430 \u0434\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430`,
      `${orderLabel}: ${productName}. \u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0441\u0442\u0432\u043e \u043f\u043e\u043c\u0435\u0442\u0438\u043b\u043e \u0441\u0442\u0430\u0442\u0443\u0441 "\u0414\u043e\u0440\u0430\u0431\u043e\u0442\u043a\u0430 \u043c\u0430\u043a\u0435\u0442\u0430".`,
      'orders_items',
      item.id
    );
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

      if (customer && customer.manager !== order.manager_employee) {
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
    const hasNotInOffice = items.some((item) => !item.office_status || item.office_status === NOT_IN_OFFICE);

    const update = {};

    if (allIssued) {
      update.office_status = ISSUED;

      const deliveredId = await getDeliveredStatusId();
      if (deliveredId) update.order_status = deliveredId;
    } else if (hasNotInOffice) {
      update.office_status = NOT_IN_OFFICE;
    } else if (allInOffice) {
      update.office_status = IN_OFFICE;
    } else {
      update.office_status = NOT_IN_OFFICE;
    }

    const order = await database('orders').where({ id: orderId }).first();
    const deliveredId = await getDeliveredStatusId();

    if (update.office_status !== ISSUED && deliveredId && order?.order_status === deliveredId) {
      const readyId = await getReadyStatusId();
      if (readyId) update.order_status = readyId;
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

  // BEFORE CREATE CUSTOMER / COMPANY
  filter('items.create', async (payload, meta, context) => {
    if (!['customers', 'customer_companies'].includes(meta.collection)) return payload;

    const next = { ...payload };
    const userId = context?.accountability?.user || meta?.accountability?.user;

    if (userId) {
      const emp = await getEmployeeByUser(userId);
      if (emp?.id) next.manager = emp.id;
    }

    return next;
  });

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

        if (Object.prototype.hasOwnProperty.call(payload || {}, 'order_status')) {
          const deliveredId = await getDeliveredStatusId();

          if (deliveredId && Number(payload.order_status) === Number(deliveredId)) {
            await setAllItemsOfficeStatus(orderId, ISSUED);
            await database('orders').where({ id: orderId }).update({
              office_status: ISSUED,
            });
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
      await notifyOrderStatusChanged(updatedOrder, prevOrder);
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
      const item = await database('orders_items').where({ id: key }).first();
      await notifyNewProductionAssignments(item);
      await notifyLayoutRevisionIfNeeded(item);
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
        const item = await database('orders_items').where({ id: key }).first();
        await notifyNewProductionAssignments(item, prevItem);
        await notifyLayoutRevisionIfNeeded(item, prevItem);
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
            comment: '\u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u043e\u0435 \u0440\u0430\u0441\u043f\u0440\u0435\u0434\u0435\u043b\u0435\u043d\u0438\u0435',
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


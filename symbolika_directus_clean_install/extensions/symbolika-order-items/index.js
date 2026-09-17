const PRIVILEGED_ROLES = new Set(['Administrator', 'Управляющий']);
const CLOSED_ORDER_STATUSES = new Set(['Доставлен', 'Отменен']);

const DUPLICATE_FIELDS = [
  'product_name', 'quantity', 'price_per_unit',
  'product_category', 'product_subcategory', 'application_method',
  'contractor_1', 'contractor_2', 'contractor_1_cost', 'contractor_2_cost',
  'deadline', 'production_comment', 'technical_task_text',
  'blank_source', 'needs_designer_help', 'designer_comment',
  'internal_route_production', 'internal_route_screen',
];

const SPEC_FIELDS = [
  'category', 'subcategory', 'technical_task_text', 'comment', 'size_text', 'color',
  'material', 'print_method', 'layout_status', 'packaging', 'notes', 'paper', 'density',
  'print_sides', 'lamination', 'postpress', 'product_color', 'sizes_grid', 'brand_model',
  'application_place', 'application_size', 'blank_type', 'print_area', 'individual_data',
  'banner_size', 'grommets', 'pockets', 'mounting',
];

function numericId(value) {
  const id = Number(value || 0);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function dateOnly(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const match = String(value || '').match(/^\d{4}-\d{2}-\d{2}/);
  return match ? match[0] : '';
}

function sameDate(left, right) {
  return dateOnly(left) === dateOnly(right);
}

function sameNullableId(left, right) {
  const leftId = numericId(left);
  const rightId = numericId(right);
  return leftId === rightId;
}

function errorResponse(res, status, message) {
  return res.status(status).json({ errors: [{ message }] });
}

export default {
  id: 'symbolika-order-items',

  handler: (router, { database, services, getSchema, logger }) => {
    const { ItemsService } = services;

    async function actorFor(req) {
      const userId = req.accountability?.user;
      if (!userId) return null;

      const user = await database('directus_users as u')
        .leftJoin('directus_roles as r', 'r.id', 'u.role')
        .where('u.id', userId)
        .select('u.id', 'r.name as role_name')
        .first();
      if (!user) return null;

      const employee = await database('employees')
        .where({ directus_user: userId })
        .select('id', 'full_name')
        .first();

      return {
        user_id: userId,
        role_name: user.role_name || '',
        employee_id: employee?.id ? Number(employee.id) : null,
        privileged: PRIVILEGED_ROLES.has(user.role_name),
      };
    }

    async function orderWithParties(orderId) {
      return database('orders as o')
        .leftJoin('customers as customer', 'customer.id', 'o.customer')
        .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
        .leftJoin('order_statuses as status', 'status.id', 'o.order_status')
        .where('o.id', orderId)
        .select(
          'o.*',
          'customer.name as customer_name',
          'company.name as company_name',
          'status.name as order_status_name',
        )
        .first();
    }

    function actorCanUseOrder(actor, order) {
      if (!actor || !order) return false;
      if (actor.privileged) return true;
      return !!actor.employee_id && Number(order.manager_employee) === Number(actor.employee_id);
    }

    async function checkedContext(req, res) {
      const actor = await actorFor(req);
      if (!actor) {
        errorResponse(res, 401, 'Необходима авторизация.');
        return null;
      }

      const itemId = numericId(req.params.id);
      const targetOrderId = numericId(req.body?.target_order);
      if (!itemId || !targetOrderId) {
        errorResponse(res, 400, 'Выберите позицию и заказ назначения.');
        return null;
      }

      const item = await database('orders_items').where({ id: itemId }).first();
      if (!item) {
        errorResponse(res, 404, 'Позиция не найдена.');
        return null;
      }

      const [sourceOrder, targetOrder] = await Promise.all([
        orderWithParties(item.order),
        orderWithParties(targetOrderId),
      ]);
      if (!sourceOrder || !targetOrder) {
        errorResponse(res, 404, 'Исходный заказ или заказ назначения не найден.');
        return null;
      }
      if (!actorCanUseOrder(actor, sourceOrder) || !actorCanUseOrder(actor, targetOrder)) {
        errorResponse(res, 403, 'Переносить и дублировать позиции можно только между своими заказами.');
        return null;
      }
      if (CLOSED_ORDER_STATUSES.has(String(targetOrder.order_status_name || '').trim())) {
        errorResponse(res, 409, 'Нельзя добавить позицию в доставленный или отменённый заказ.');
        return null;
      }

      return { actor, itemId, targetOrderId, item, sourceOrder, targetOrder };
    }

    async function checkedMergeContext(req, res) {
      const actor = await actorFor(req);
      if (!actor) {
        errorResponse(res, 401, 'Необходима авторизация.');
        return null;
      }

      const targetOrderId = numericId(req.params.id);
      const sourceOrderId = numericId(req.body?.source_order);
      if (!targetOrderId || !sourceOrderId || targetOrderId === sourceOrderId) {
        errorResponse(res, 400, 'Выберите два разных заказа для объединения.');
        return null;
      }

      const [targetOrder, sourceOrder] = await Promise.all([
        orderWithParties(targetOrderId),
        orderWithParties(sourceOrderId),
      ]);
      if (!targetOrder || !sourceOrder) {
        errorResponse(res, 404, 'Один из заказов не найден.');
        return null;
      }
      if (!actorCanUseOrder(actor, targetOrder) || !actorCanUseOrder(actor, sourceOrder)) {
        errorResponse(res, 403, 'Объединять можно только доступные вам заказы.');
        return null;
      }
      if (CLOSED_ORDER_STATUSES.has(String(targetOrder.order_status_name || '').trim())
        || CLOSED_ORDER_STATUSES.has(String(sourceOrder.order_status_name || '').trim())) {
        errorResponse(res, 409, 'Доставленные и отменённые заказы объединять нельзя.');
        return null;
      }
      if (!numericId(targetOrder.customer)
        || !sameNullableId(targetOrder.customer, sourceOrder.customer)
        || !sameNullableId(targetOrder.customer_company, sourceOrder.customer_company)) {
        errorResponse(res, 409, 'Объединить можно только заказы одного клиента и одной компании-плательщика.');
        return null;
      }

      return { actor, targetOrderId, sourceOrderId, targetOrder, sourceOrder };
    }

    function targetDeadline(item, sourceOrder, targetOrder) {
      if (!item.deadline || sameDate(item.deadline, sourceOrder.deadline)) {
        return targetOrder.deadline || null;
      }
      return item.deadline;
    }

    function adminAccountability(req) {
      return {
        ...(req.accountability || {}),
        admin: true,
        user: req.accountability?.user,
      };
    }

    router.get('/targets', async (req, res) => {
      try {
        const actor = await actorFor(req);
        if (!actor) return errorResponse(res, 401, 'Необходима авторизация.');
        if (!actor.privileged && !actor.employee_id) {
          return res.json({ data: [] });
        }

        const query = database('orders as o')
          .leftJoin('customers as customer', 'customer.id', 'o.customer')
          .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
          .leftJoin('order_statuses as status', 'status.id', 'o.order_status')
          .whereNotIn(database.raw('coalesce(status.name, ?)', ['']), [...CLOSED_ORDER_STATUSES])
          .select(
            'o.id', 'o.order_number', 'o.date', 'o.deadline', 'o.manager_employee',
            'customer.name as customer_name', 'company.name as company_name',
            'status.name as order_status_name',
          )
          .orderBy('o.id', 'desc');

        if (!actor.privileged) query.where('o.manager_employee', actor.employee_id);
        const rows = await query;
        return res.json({ data: rows });
      } catch (error) {
        logger.error(error);
        return errorResponse(res, 500, 'Не удалось загрузить доступные заказы.');
      }
    });

    router.get('/orders/:id/merge-targets', async (req, res) => {
      try {
        const actor = await actorFor(req);
        const targetOrderId = numericId(req.params.id);
        if (!actor) return errorResponse(res, 401, 'Необходима авторизация.');
        if (!targetOrderId) return errorResponse(res, 400, 'Заказ не выбран.');

        const targetOrder = await orderWithParties(targetOrderId);
        if (!targetOrder) return errorResponse(res, 404, 'Заказ не найден.');
        if (!actorCanUseOrder(actor, targetOrder)) {
          return errorResponse(res, 403, 'Этот заказ вам недоступен.');
        }
        if (!numericId(targetOrder.customer)) return res.json({ data: [] });

        const query = database('orders as o')
          .leftJoin('customers as customer', 'customer.id', 'o.customer')
          .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
          .leftJoin('order_statuses as status', 'status.id', 'o.order_status')
          .whereNot('o.id', targetOrderId)
          .where('o.customer', targetOrder.customer)
          .whereNotIn(database.raw('coalesce(status.name, ?)', ['']), [...CLOSED_ORDER_STATUSES])
          .select(
            'o.id', 'o.order_number', 'o.date', 'o.deadline', 'o.manager_employee',
            'o.order_sum', 'o.paid_amount', 'o.payment_due',
            'customer.name as customer_name', 'company.name as company_name',
            'status.name as order_status_name',
            database.raw('(select count(*)::integer from orders_items oi where oi."order" = o.id) as items_count'),
          )
          .orderBy('o.id', 'desc');

        if (numericId(targetOrder.customer_company)) {
          query.where('o.customer_company', targetOrder.customer_company);
        } else {
          query.whereNull('o.customer_company');
        }
        if (!actor.privileged) query.where('o.manager_employee', actor.employee_id);

        return res.json({ data: await query });
      } catch (error) {
        logger.error(error);
        return errorResponse(res, 500, 'Не удалось загрузить заказы для объединения.');
      }
    });

    router.post('/orders/:id/merge', async (req, res) => {
      try {
        const context = await checkedMergeContext(req, res);
        if (!context) return;
        const { targetOrderId, sourceOrderId, targetOrder, sourceOrder } = context;
        const itemRows = await database('orders_items')
          .where({ order: sourceOrderId })
          .select('id');
        const itemIds = itemRows.map((row) => Number(row.id)).filter(Boolean);

        await database.transaction(async (trx) => {
          if (itemIds.length) {
            for (const mirrorTable of [
              'orders_overview_items',
              'office_issue_items',
              'office_issue_archive_items',
              'office_items_in_office',
              'production_work',
              'screen_printing_work',
              'contractor_work',
              'my_orders_in_work_items',
              'my_orders_completed_items',
              'my_orders_unpaid_items',
            ]) {
              await trx(mirrorTable).whereIn('id', itemIds).delete();
            }
          }

          await trx('orders_items').where({ order: sourceOrderId }).update({
            order: targetOrderId,
            order_link: targetOrderId,
            manager_employee: targetOrder.manager_employee || null,
            commission_manager_employee: targetOrder.commission_manager_employee || null,
            shipping_method: targetOrder.shipping_method || null,
          });

          await Promise.all([
            trx('order_payments').where({ order: sourceOrderId }).update({ order: targetOrderId }),
            trx('payment_allocations').where({ order: sourceOrderId }).update({ order: targetOrderId }),
            trx('symbolika_tasks').where({ related_order: sourceOrderId }).update({ related_order: targetOrderId }),
            trx('procurement_requests').where({ related_order: sourceOrderId }).update({ related_order: targetOrderId }),
            trx('contractor_payments').where({ related_order: sourceOrderId }).update({ related_order: targetOrderId }),
            trx('inventory_movements').where({ related_order: sourceOrderId }).update({ related_order: targetOrderId }),
            trx('gift_certificate_transactions').where({ order: sourceOrderId }).update({ order: targetOrderId }),
            trx('symbolika_mail_threads').where({ order_id: sourceOrderId }).update({ order_id: targetOrderId }),
            trx('symbolika_automation_issues').where({ order_id: sourceOrderId }).update({ order_id: targetOrderId }),
            trx('symbolika_event_feed').where({ order_id: sourceOrderId }).update({ order_id: targetOrderId }),
            trx('order_estimates').where({ converted_order: sourceOrderId }).update({ converted_order: targetOrderId }),
          ]);

          const combinedDeadline = [dateOnly(targetOrder.deadline), dateOnly(sourceOrder.deadline)]
            .filter(Boolean)
            .sort()
            .at(-1) || null;
          await trx('orders').where({ id: targetOrderId }).update({ deadline: combinedDeadline });
          await trx('orders').where({ id: sourceOrderId }).delete();
        });

        // The item move is already complete inside the transaction and the SQL
        // synchronization trigger has refreshed every materialized work table.
        // Re-saving each item via ItemsService here starts overlapping calculation
        // hooks for the same order and can deadlock PostgreSQL on larger orders.
        const schema = await getSchema();
        const orderService = new ItemsService('orders', {
          schema,
          accountability: adminAccountability(req),
        });
        await orderService.updateOne(targetOrderId, { comment: targetOrder.comment || null });

        return res.json({
          data: {
            id: targetOrderId,
            merged_order: sourceOrderId,
            moved_items: itemIds.length,
          },
        });
      } catch (error) {
        logger.error(error);
        return errorResponse(res, Number(error?.status || error?.statusCode || 500), error?.message || 'Не удалось объединить заказы.');
      }
    });

    router.post('/:id/duplicate', async (req, res) => {
      let createdId = null;
      try {
        const context = await checkedContext(req, res);
        if (!context) return;
        const { item, targetOrder, targetOrderId, sourceOrder } = context;
        const schema = await getSchema();
        const service = new ItemsService('orders_items', {
          schema,
          accountability: adminAccountability(req),
        });

        const payload = Object.fromEntries(DUPLICATE_FIELDS.map((field) => [field, item[field]]));
        Object.assign(payload, {
          order: targetOrderId,
          order_link: targetOrderId,
          manager_employee: targetOrder.manager_employee || null,
          commission_manager_employee: targetOrder.commission_manager_employee || null,
          shipping_method: targetOrder.shipping_method || null,
          office_status: 'not_in_office',
          item_status: 'new',
          production_status: 7,
          blank_ordered: false,
          deadline: targetDeadline(item, sourceOrder, targetOrder),
          url: null,
          layout_revision_url_snapshot: null,
          designer_source_url: null,
          layout_disk_path: null,
          layout_disk_name: null,
          layout_disk_size: null,
          layout_disk_mime_type: null,
          layout_disk_uploaded_by: null,
          layout_disk_uploaded_at: null,
          layout_preview_url: null,
          layout_preview_disk_path: null,
          layout_preview_disk_name: null,
          layout_preview_disk_size: null,
          layout_preview_disk_mime_type: null,
          layout_preview_uploaded_by: null,
          layout_preview_uploaded_at: null,
        });

        createdId = Number(await service.createOne(payload));
        const specs = await database('order_item_specs').where({ order_item: item.id });
        for (const spec of specs) {
          await database('order_item_specs').insert({
            order_item: createdId,
            ...Object.fromEntries(SPEC_FIELDS.map((field) => [field, spec[field]])),
          });
        }

        return res.json({ data: { id: createdId, order: targetOrderId, mode: 'duplicate' } });
      } catch (error) {
        logger.error(error);
        if (createdId) {
          await database('orders_items').where({ id: createdId }).delete().catch(() => undefined);
        }
        return errorResponse(res, Number(error?.status || error?.statusCode || 500), error?.message || 'Не удалось дублировать позицию.');
      }
    });

    router.post('/:id/move', async (req, res) => {
      let rollback = null;
      try {
        const context = await checkedContext(req, res);
        if (!context) return;
        const { item, targetOrder, targetOrderId, sourceOrder } = context;
        if (Number(sourceOrder.id) === Number(targetOrderId)) {
          return errorResponse(res, 409, 'Для переноса выберите другой заказ.');
        }

        const schema = await getSchema();
        const service = new ItemsService('orders_items', {
          schema,
          accountability: adminAccountability(req),
        });
        rollback = {
          order: item.order,
          order_link: item.order_link,
          manager_employee: item.manager_employee,
          commission_manager_employee: item.commission_manager_employee,
          shipping_method: item.shipping_method,
          office_status: item.office_status,
          deadline: item.deadline,
        };

        await service.updateOne(item.id, {
          order: targetOrderId,
          order_link: targetOrderId,
          manager_employee: targetOrder.manager_employee || null,
          commission_manager_employee: targetOrder.commission_manager_employee || null,
          shipping_method: targetOrder.shipping_method || null,
          office_status: 'not_in_office',
          deadline: targetDeadline(item, sourceOrder, targetOrder),
        });

        await Promise.all([
          database('symbolika_tasks').where({ related_order_item: item.id }).update({ related_order: targetOrderId }),
          database('procurement_requests').where({ order_item: item.id }).update({ related_order: targetOrderId }),
          database('contractor_payments').where({ related_order_item: item.id }).update({ related_order: targetOrderId }),
        ]);

        return res.json({ data: { id: item.id, order: targetOrderId, mode: 'move' } });
      } catch (error) {
        logger.error(error);
        if (rollback && req.params.id) {
          await database('orders_items').where({ id: Number(req.params.id) }).update(rollback).catch(() => undefined);
        }
        return errorResponse(res, Number(error?.status || error?.statusCode || 500), error?.message || 'Не удалось перенести позицию.');
      }
    });
  },
};

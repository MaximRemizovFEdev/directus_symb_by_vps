const rollbackFields = {
  orders: new Set([
    'date', 'deadline', 'customer', 'customer_company', 'manager_employee', 'order_status',
    'office_status', 'shipping_method', 'shipping_comment', 'comment', 'payment_type',
    'payment_on_receipt',
  ]),
  orders_items: new Set([
    'product_name', 'quantity', 'price_per_unit', 'deadline', 'product_category',
    'product_subcategory', 'application_method', 'item_status', 'production_status',
    'office_status', 'contractor_1', 'contractor_1_cost', 'technical_task_text', 'url',
    'needs_designer_help', 'blank_source', 'blank_ordered', 'shipping_method',
    'production_comment',
  ]),
  symbolika_tasks: new Set([
    'title', 'description', 'status', 'priority', 'due_date', 'assigned_to',
    'created_by_employee', 'related_order', 'related_order_item', 'result_url',
    'waiting_for_response', 'task_type',
  ]),
};

function jsonObject(value) {
  if (value && typeof value === 'object') return value;
  try {
    return JSON.parse(value || '{}');
  } catch {
    return {};
  }
}

export default {
  id: 'symbolika-event-rollback',

  handler: (router, { database, services, getSchema, logger }) => {
    const { ItemsService } = services;

    async function revisionValueBefore(event, field) {
      const revisions = await database('directus_revisions as revision')
        .join('directus_activity as activity', 'activity.id', 'revision.activity')
        .where('revision.id', '<', Number(event.event_id))
        .where('activity.collection', event.source_collection)
        .where('activity.item', String(event.source_id))
        .orderBy('revision.id', 'desc')
        .select('revision.delta', 'revision.data');

      for (const revision of revisions) {
        const delta = jsonObject(revision.delta);
        if (Object.prototype.hasOwnProperty.call(delta, field)) return delta[field];
        const data = jsonObject(revision.data);
        if (Object.prototype.hasOwnProperty.call(data, field)) return data[field];
      }
      return null;
    }

    async function eventBeforeDelta(event) {
      const delta = jsonObject(event.delta);
      const stored = jsonObject(event.before_delta);
      const result = {};

      for (const field of Object.keys(delta)) {
        if (Object.prototype.hasOwnProperty.call(stored, field)) result[field] = stored[field];
        else result[field] = await revisionValueBefore(event, field);
      }
      return result;
    }

    router.post('/rollback', async (req, res) => {
      try {
        if (!req.accountability?.user) return res.status(401).json({ message: 'Необходима авторизация.' });

        const eventId = Number(req.body?.event_id || 0);
        const mode = req.body?.mode === 'through' ? 'through' : 'single';
        if (!eventId) return res.status(400).json({ message: 'Не указано событие для отката.' });

        const schema = await getSchema();
        const eventService = new ItemsService('symbolika_event_feed', {
          schema,
          accountability: req.accountability,
        });
        const selected = await eventService.readOne(eventId, {
          fields: ['event_id', 'event_at', 'action', 'source_collection', 'source_id', 'delta', 'before_delta'],
        });

        if (!selected || selected.action !== 'update') {
          return res.status(409).json({ message: 'Откатывать можно только события изменения.' });
        }

        const allowed = rollbackFields[selected.source_collection];
        if (!allowed) return res.status(409).json({ message: 'Этот тип события пока нельзя откатить.' });

        const events = mode === 'through'
          ? await database('symbolika_event_feed')
            .where({
              source_collection: selected.source_collection,
              source_id: Number(selected.source_id),
              action: 'update',
            })
            .where('event_id', '>=', Number(selected.event_id))
            .orderBy('event_id', 'asc')
            .select('event_id', 'source_collection', 'source_id', 'delta', 'before_delta')
          : [selected];

        const patch = {};
        for (const event of events) {
          const before = await eventBeforeDelta(event);
          for (const [field, value] of Object.entries(before)) {
            if (allowed.has(field) && !Object.prototype.hasOwnProperty.call(patch, field)) {
              patch[field] = value;
            }
          }
        }

        if (!Object.keys(patch).length) {
          return res.status(409).json({ message: 'В событии нет полей, которые можно безопасно откатить.' });
        }

        const itemService = new ItemsService(selected.source_collection, {
          schema,
          accountability: req.accountability,
        });
        await itemService.updateOne(Number(selected.source_id), patch);

        return res.json({
          ok: true,
          mode,
          event_id: eventId,
          source_collection: selected.source_collection,
          source_id: Number(selected.source_id),
          changed_fields: Object.keys(patch),
        });
      } catch (error) {
        logger.error(error);
        const status = Number(error?.status || error?.statusCode || 500);
        const safeStatus = status >= 400 && status < 600 ? status : 500;
        const message = safeStatus === 500
          ? 'Не удалось откатить изменение. Проверьте права и повторите попытку.'
          : (error?.message || 'Откат недоступен.');
        return res.status(safeStatus).json({ message });
      }
    });
  },
};

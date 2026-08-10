const CONTROL_ROLES = new Set(['Administrator', 'Управляющий']);
const REPORT_STATUSES = new Set(['new', 'in_progress', 'resolved']);

export default {
  id: 'symbolika-support',

  handler: (router, { database, services, getSchema, logger }) => {
    const { ItemsService } = services;

    async function currentActor(req) {
      if (!req.accountability?.user) return null;
      return database('directus_users as user')
        .leftJoin('directus_roles as role', 'role.id', 'user.role')
        .leftJoin('employees as employee', 'employee.directus_user', 'user.id')
        .where('user.id', req.accountability.user)
        .select('user.id', 'role.name as role_name', 'employee.id as employee_id')
        .first();
    }

    async function requireController(req, res) {
      const actor = await currentActor(req);
      if (!actor) {
        res.status(401).json({ message: 'Необходима авторизация.' });
        return null;
      }
      if (!CONTROL_ROLES.has(actor.role_name)) {
        res.status(403).json({ message: 'Раздел доступен администратору и управляющему.' });
        return null;
      }
      return actor;
    }

    router.post('/report', async (req, res) => {
      try {
        const actor = await currentActor(req);
        if (!actor) return res.status(401).json({ message: 'Необходима авторизация.' });
        const comment = String(req.body?.comment || '').trim();
        if (comment.length < 5) return res.status(400).json({ message: 'Опишите проблему хотя бы в нескольких словах.' });
        if (comment.length > 4000) return res.status(400).json({ message: 'Комментарий слишком длинный.' });

        const entityId = Number(req.body?.entity_id || 0) || null;
        const rows = await database('symbolika_feedback_reports').insert({
          reported_by: actor.id,
          employee: actor.employee_id || null,
          page_url: String(req.body?.page_url || '').slice(0, 2000),
          page_title: String(req.body?.page_title || '').slice(0, 300) || null,
          module_section: String(req.body?.module_section || '').slice(0, 80) || null,
          active_tab: String(req.body?.active_tab || '').slice(0, 100) || null,
          entity_type: String(req.body?.entity_type || '').slice(0, 40) || null,
          entity_id: entityId,
          order_number: String(req.body?.order_number || '').slice(0, 100) || null,
          entity_title: String(req.body?.entity_title || '').slice(0, 500) || null,
          comment,
          browser_info: String(req.headers['user-agent'] || '').slice(0, 1000) || null,
        }).returning(['id', 'reported_at']);
        return res.json({ ok: true, report: rows[0] });
      } catch (error) {
        logger.error(error);
        return res.status(500).json({ message: 'Не удалось сохранить сообщение об ошибке.' });
      }
    });

    router.get('/reports', async (req, res) => {
      try {
        if (!await requireController(req, res)) return;
        const rows = await database('symbolika_feedback_reports as report')
          .leftJoin('employees as employee', 'employee.id', 'report.employee')
          .select('report.*', 'employee.full_name as employee_name')
          .orderByRaw("case report.status when 'new' then 0 when 'in_progress' then 1 else 2 end")
          .orderBy('report.reported_at', 'desc')
          .limit(100);
        return res.json({ data: rows });
      } catch (error) {
        logger.error(error);
        return res.status(500).json({ message: 'Не удалось загрузить сообщения сотрудников.' });
      }
    });

    router.patch('/reports/:id', async (req, res) => {
      try {
        const actor = await requireController(req, res);
        if (!actor) return;
        const id = Number(req.params.id || 0);
        const status = String(req.body?.status || '');
        if (!id || !REPORT_STATUSES.has(status)) return res.status(400).json({ message: 'Некорректный статус сообщения.' });
        const patch = {
          status,
          resolved_at: status === 'resolved' ? database.fn.now() : null,
          resolved_by: status === 'resolved' ? actor.id : null,
        };
        await database('symbolika_feedback_reports').where({ id }).update(patch);
        return res.json({ ok: true });
      } catch (error) {
        logger.error(error);
        return res.status(500).json({ message: 'Не удалось обновить сообщение.' });
      }
    });

    router.get('/automation-health', async (req, res) => {
      try {
        if (!await requireController(req, res)) return;
        const [handlers, failures] = await Promise.all([
          database('symbolika_automation_runs').orderBy('handler_key'),
          database('symbolika_customer_notifications as notification')
            .leftJoin('orders as order', 'order.id', 'notification.order')
            .where('notification.status', 'failed')
            .select(
              'notification.id', 'notification.order', 'order.order_number', 'notification.channel',
              'notification.recipient', 'notification.attempts', 'notification.last_error', 'notification.updated_at',
            )
            .orderBy('notification.updated_at', 'desc')
            .limit(10),
        ]);
        return res.json({ data: { handlers, failures } });
      } catch (error) {
        logger.error(error);
        return res.status(500).json({ message: 'Не удалось получить состояние автоматизаций.' });
      }
    });

    router.post('/automation-health/retry', async (req, res) => {
      const actor = await requireController(req, res);
      if (!actor) return;
      const type = String(req.body?.type || '');
      try {
        if (type === 'workflow_consistency') {
          await database.raw('select refresh_symbolika_automation_issues()');
          return res.json({ ok: true, message: 'Сверка выполнена повторно.' });
        }
        if (type === 'customer_notification') {
          const id = Number(req.body?.id || 0);
          const notification = id ? await database('symbolika_customer_notifications').where({ id }).first() : null;
          if (!notification || notification.status !== 'failed') {
            return res.status(409).json({ message: 'Повтор доступен только для неотправленного уведомления.' });
          }
          const schema = await getSchema();
          const service = new ItemsService('symbolika_customer_notifications', { schema });
          await service.updateOne(id, { status: 'retry_requested', updated_at: new Date().toISOString() });
          return res.json({ ok: true, message: 'Уведомление передано на безопасный повтор.' });
        }
        return res.status(400).json({ message: 'Неизвестный тип повторного запуска.' });
      } catch (error) {
        if (type === 'workflow_consistency') {
          await database('symbolika_automation_runs').where({ handler_key: 'workflow_consistency' }).update({
            status: 'error',
            last_error_at: database.fn.now(),
            last_error: String(error?.message || error).slice(0, 1000),
            updated_at: database.fn.now(),
          }).catch(() => {});
        }
        logger.error(error);
        return res.status(500).json({ message: 'Безопасный повтор не выполнен. Ошибка сохранена в журнале.' });
      }
    });
  },
};

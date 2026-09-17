import pg from 'pg';

const { Client } = pg;
const CONTROL_ROLES = new Set(['Administrator', 'Управляющий']);
const REPORT_STATUSES = new Set(['new', 'in_progress', 'resolved']);
const DIRECTUS_DATABASE_APP = 'symbolika-directus';

function databaseRecoveryClient() {
  return new Client({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_DATABASE,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    application_name: 'symbolika-emergency-control',
    connectionTimeoutMillis: 3000,
    statement_timeout: 5000,
    query_timeout: 6000,
  });
}

async function withRecoveryDatabase(callback) {
  const client = databaseRecoveryClient();
  await client.connect();
  try {
    return await callback(client);
  } finally {
    await client.end().catch(() => {});
  }
}

async function readDirectusDatabaseHealth(client) {
  const result = await client.query(`
    SELECT
      pid,
      state,
      wait_event_type,
      wait_event,
      EXTRACT(EPOCH FROM (clock_timestamp() - query_start))::integer AS age_seconds,
      query_start,
      LEFT(REGEXP_REPLACE(COALESCE(query, ''), '\\s+', ' ', 'g'), 240) AS query_preview
    FROM pg_stat_activity
    WHERE datname = current_database()
      AND application_name = $1
      AND pid <> pg_backend_pid()
      AND state IS DISTINCT FROM 'idle'
    ORDER BY query_start
  `, [DIRECTUS_DATABASE_APP]);

  const sessions = result.rows.map((row) => ({
    ...row,
    pid: Number(row.pid),
    age_seconds: Number(row.age_seconds || 0),
  }));
  return {
    sessions,
    active: sessions.filter((row) => row.state === 'active').length,
    blocked: sessions.filter((row) => row.wait_event_type === 'Lock').length,
    oldest_seconds: sessions.reduce((max, row) => Math.max(max, row.age_seconds), 0),
    statement_timeout_seconds: 60,
    lock_timeout_seconds: 10,
  };
}

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

    async function requireAdministrator(req, res) {
      if (!req.accountability?.user) {
        res.status(401).json({ message: 'Необходима авторизация.' });
        return null;
      }
      // Do not query through the ordinary Directus pool here: this endpoint
      // must remain useful precisely when that pool is occupied by stalled
      // work. Directus has already resolved the administrator flag.
      if (req.accountability.admin !== true) {
        res.status(403).json({ message: 'Аварийная остановка доступна только администратору.' });
        return null;
      }
      return req.accountability;
    }

    router.get('/database-health', async (req, res) => {
      try {
        if (!await requireAdministrator(req, res)) return;
        const health = await withRecoveryDatabase(readDirectusDatabaseHealth);
        return res.json({ data: health });
      } catch (error) {
        logger.error(error);
        return res.status(503).json({ message: 'Не удалось проверить состояние вычислений.' });
      }
    });

    router.post('/database-health/cancel', async (req, res) => {
      try {
        if (!await requireAdministrator(req, res)) return;
        if (req.body?.confirmation !== 'STOP_DIRECTUS_CALCULATIONS') {
          return res.status(400).json({ message: 'Не подтверждена аварийная остановка.' });
        }

        const result = await withRecoveryDatabase(async (client) => client.query(`
          SELECT pid, pg_cancel_backend(pid) AS cancelled
          FROM pg_stat_activity
          WHERE datname = current_database()
            AND application_name = $1
            AND pid <> pg_backend_pid()
            AND state = 'active'
        `, [DIRECTUS_DATABASE_APP]));
        const cancelled = result.rows.filter((row) => row.cancelled).map((row) => Number(row.pid));
        logger.warn(`[Symbolika database guard] administrator cancelled ${cancelled.length} Directus database operation(s)`);
        return res.json({
          ok: true,
          data: { cancelled_count: cancelled.length },
          message: cancelled.length
            ? `Остановлено операций: ${cancelled.length}. Их незавершённые транзакции откатятся.`
            : 'Активных вычислений для остановки нет.',
        });
      } catch (error) {
        logger.error(error);
        return res.status(503).json({ message: 'Аварийная остановка не выполнена.' });
      }
    });

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

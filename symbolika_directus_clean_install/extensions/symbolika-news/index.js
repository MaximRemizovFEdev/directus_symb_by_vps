const CONTROL_ROLES = new Set(['Administrator', 'Управляющий']);

const cleanText = (value, limit = 500) => String(value || '').trim().slice(0, limit);
const sanitizeHtml = (value) => String(value || '')
  .replace(/<\s*(script|style|iframe|object|embed|form|input|button|meta|link)[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi, '')
  .replace(/<\s*(script|style|iframe|object|embed|form|input|button|meta|link)[^>]*\/?\s*>/gi, '')
  .replace(/\son\w+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, '')
  .replace(/(href|src)\s*=\s*(["'])\s*javascript:[\s\S]*?\2/gi, '$1="#"');
const plainText = (value) => String(value || '').replace(/<br\s*\/?\s*>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

export default {
  id: 'symbolika-news',
  handler: (router, { database, logger }) => {
    async function actor(req) {
      if (!req.accountability?.user) return null;
      return database('directus_users as user')
        .leftJoin('directus_roles as role', 'role.id', 'user.role')
        .leftJoin('employees as employee', 'employee.directus_user', 'user.id')
        .where('user.id', req.accountability.user)
        .select('user.id as user_id', 'role.name as role_name', 'employee.id as employee_id', 'employee.full_name')
        .first();
    }
    async function requireEmployee(req, res) {
      const current = await actor(req);
      if (!current?.employee_id && current?.role_name !== 'Administrator') {
        res.status(current ? 403 : 401).json({ message: 'Раздел доступен только сотрудникам.' });
        return null;
      }
      return current;
    }
    const canManage = (current) => CONTROL_ROLES.has(current?.role_name);

    router.get('/', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        const query = database('symbolika_news as news')
          .leftJoin('employees as author', 'author.id', 'news.author_employee')
          .leftJoin('symbolika_news_reads as reading', function joinRead() {
            this.on('reading.news', '=', 'news.id').andOnVal('reading.user', '=', current.user_id);
          })
          .select('news.*', 'author.full_name as author_name', database.raw('(reading.news is not null) as is_read'));
        if (!(canManage(current) && req.query.scope === 'all')) query.where({ 'news.status': 'published' });
        const rows = await query.orderByRaw("case news.status when 'published' then 0 when 'draft' then 1 else 2 end")
          .orderBy('news.published_at', 'desc').orderBy('news.created_at', 'desc').limit(200);
        res.json({ data: rows, meta: { can_manage: canManage(current) } });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось загрузить новости.' }); }
    });

    router.get('/:id', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        const row = await database('symbolika_news as news').leftJoin('employees as author', 'author.id', 'news.author_employee')
          .where('news.id', Number(req.params.id)).select('news.*', 'author.full_name as author_name').first();
        if (!row || (row.status !== 'published' && !canManage(current))) return res.status(404).json({ message: 'Новость не найдена.' });
        res.json({ data: row, meta: { can_manage: canManage(current) } });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось открыть новость.' }); }
    });

    router.post('/', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        if (!canManage(current)) return res.status(403).json({ message: 'Публиковать новости могут админ и управляющий.' });
        const title = cleanText(req.body?.title, 240);
        const contentHtml = sanitizeHtml(req.body?.content_html);
        if (!title || !plainText(contentHtml)) return res.status(400).json({ message: 'Заполните заголовок и текст новости.' });
        const [row] = await database('symbolika_news').insert({
          status: 'draft', title, summary: cleanText(req.body?.summary || plainText(contentHtml), 500),
          content_html: contentHtml, cover_url: cleanText(req.body?.cover_url, 2000) || null,
          author_employee: current.employee_id || null, created_by: current.user_id, updated_by: current.user_id,
        }).returning('*');
        res.json({ data: row });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось сохранить новость.' }); }
    });

    router.patch('/:id', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        if (!canManage(current)) return res.status(403).json({ message: 'Редактировать новости могут админ и управляющий.' });
        const patch = { updated_by: current.user_id, updated_at: database.fn.now() };
        if (req.body?.title !== undefined) patch.title = cleanText(req.body.title, 240);
        if (req.body?.summary !== undefined) patch.summary = cleanText(req.body.summary, 500);
        if (req.body?.content_html !== undefined) patch.content_html = sanitizeHtml(req.body.content_html);
        if (req.body?.cover_url !== undefined) patch.cover_url = cleanText(req.body.cover_url, 2000) || null;
        const [row] = await database('symbolika_news').where({ id: Number(req.params.id) }).update(patch).returning('*');
        if (!row) return res.status(404).json({ message: 'Новость не найдена.' });
        res.json({ data: row });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось обновить новость.' }); }
    });

    router.post('/:id/publish', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        if (!canManage(current)) return res.status(403).json({ message: 'Публиковать новости могут админ и управляющий.' });
        const id = Number(req.params.id);
        const news = await database('symbolika_news').where({ id }).first();
        if (!news) return res.status(404).json({ message: 'Новость не найдена.' });
        if (!news.title || !plainText(news.content_html)) return res.status(400).json({ message: 'Заполните заголовок и текст новости.' });
        await database('symbolika_news').where({ id }).update({ status: 'published', published_at: news.published_at || database.fn.now(), updated_by: current.user_id, updated_at: database.fn.now() });
        if (!news.notifications_sent_at) {
          const recipients = await database('employees as employee').join('directus_users as user', 'user.id', 'employee.directus_user')
            .where({ 'employee.is_active': true, 'user.status': 'active' }).whereNotNull('employee.directus_user').pluck('user.id');
          if (recipients.length) await database('directus_notifications').insert(recipients.map((recipient) => ({
            recipient, sender: current.user_id, subject: `Новая новость: ${news.title}`,
            message: cleanText(news.summary || plainText(news.content_html), 500), collection: 'symbolika_news', item: String(id), status: 'inbox', timestamp: database.fn.now(),
          })));
          await database('symbolika_news').where({ id }).update({ notifications_sent_at: database.fn.now() });
        }
        res.json({ data: await database('symbolika_news').where({ id }).first() });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось опубликовать новость.' }); }
    });

    router.post('/:id/read', async (req, res) => {
      try {
        const current = await requireEmployee(req, res); if (!current) return;
        await database('symbolika_news_reads').insert({ news: Number(req.params.id), user: current.user_id, read_at: database.fn.now() }).onConflict(['news', 'user']).merge({ read_at: database.fn.now() });
        res.json({ ok: true });
      } catch (error) { logger.error(error); res.status(500).json({ message: 'Не удалось отметить новость прочитанной.' }); }
    });
  },
};

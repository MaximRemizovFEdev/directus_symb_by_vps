export default {
  id: 'symbolika-push',

  handler: (router, { database, env, logger }) => {
  let tableReady = false;

  async function ensureTable() {
    if (tableReady) return;

    const exists = await database.schema.hasTable('symbolika_push_subscriptions');
    if (exists) {
      tableReady = true;
      return;
    }

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

    tableReady = true;
  }

  router.get('/public-key', (_req, res) => {
    res.json({
      publicKey: env.SYMBOLIKA_PUSH_PUBLIC_KEY || '',
    });
  });

  router.post('/subscribe', async (req, res) => {
    try {
      const userId = req.accountability?.user;
      if (!userId) return res.status(401).json({ error: 'unauthorized' });

      const subscription = req.body?.subscription;
      if (!subscription?.endpoint || !subscription?.keys?.p256dh || !subscription?.keys?.auth) {
        return res.status(400).json({ error: 'invalid_subscription' });
      }

      await ensureTable();

      await database('symbolika_push_subscriptions')
        .insert({
          user: userId,
          endpoint: subscription.endpoint,
          subscription,
          user_agent: req.headers['user-agent'] || null,
          last_error: null,
          updated_at: database.fn.now(),
        })
        .onConflict('endpoint')
        .merge({
          user: userId,
          subscription,
          user_agent: req.headers['user-agent'] || null,
          last_error: null,
          updated_at: database.fn.now(),
        });

      res.json({ ok: true });
    } catch (error) {
      logger.error(error);
      res.status(500).json({ error: 'subscribe_failed' });
    }
  });

  router.post('/unsubscribe', async (req, res) => {
    try {
      const userId = req.accountability?.user;
      if (!userId) return res.status(401).json({ error: 'unauthorized' });

      const endpoint = req.body?.endpoint;
      if (!endpoint) return res.status(400).json({ error: 'missing_endpoint' });

      await ensureTable();
      await database('symbolika_push_subscriptions')
        .where({ user: userId, endpoint })
        .delete();

      res.json({ ok: true });
    } catch (error) {
      logger.error(error);
      res.status(500).json({ error: 'unsubscribe_failed' });
    }
  });
  },
};

const API_ROOT = 'https://cloud-api.yandex.net/v1/disk';
const MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024;
const MAX_PREVIEW_SIZE = 20 * 1024 * 1024;

function cleanSegment(value, fallback = 'file') {
  const cleaned = String(value || '')
    .normalize('NFKC')
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-')
    .replace(/\s+/g, ' ')
    .replace(/^\.+|\.+$/g, '')
    .trim()
    .slice(0, 160);
  return cleaned || fallback;
}

function formatOrderDate(value) {
  const match = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) return `${match[3]}${match[2]}${match[1].slice(-2)}`;

  const parts = new Intl.DateTimeFormat('ru-RU', {
    timeZone: 'Europe/Moscow',
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).formatToParts(new Date());
  const part = (type) => parts.find((entry) => entry.type === type)?.value || '';
  return `${part('day')}${part('month')}${part('year')}`;
}

function formatQuantity(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return cleanSegment(value, '0');
  return new Intl.NumberFormat('ru-RU', {
    maximumFractionDigits: 3,
    useGrouping: false,
  }).format(number);
}

function fileExtension(value) {
  const match = String(value || '').trim().match(/(\.[a-zA-Z0-9]{1,12})$/);
  return match ? match[1].toLowerCase() : '';
}

function buildLayoutFileName({ orderDate, customerName, productName, quantity, originalName }) {
  const date = formatOrderDate(orderDate);
  const customer = cleanSegment(customerName, 'Без заказчика').slice(0, 60);
  const product = cleanSegment(productName, 'Позиция').slice(0, 80);
  const amount = cleanSegment(formatQuantity(quantity), '0');
  const extension = fileExtension(originalName);
  return cleanSegment(`${date}, ${customer}, ${product} - ${amount}шт`, 'Макет').slice(0, 220 - extension.length) + extension;
}

function buildAttachmentFileName(context, originalName) {
  const primaryName = buildLayoutFileName({ ...context, originalName });
  const extension = fileExtension(primaryName);
  const stem = primaryName.slice(0, Math.max(0, primaryName.length - extension.length));
  const originalStem = cleanSegment(String(originalName || '').replace(/\.[^.]+$/, ''), 'Файл').slice(0, 48);
  const uniquePart = Date.now().toString(36);
  return cleanSegment(`${stem} - ${originalStem}-${uniquePart}`, 'Материал').slice(0, 220 - extension.length) + extension;
}

function isManagedOldPath(oldPath, { root, orderFolder, itemFolder }) {
  const value = String(oldPath || '').trim();
  if (!value) return false;
  if (value === root || value.startsWith(`${root}/`)) return true;
  return value.startsWith('disk:/') && value.includes(`/${orderFolder}/${itemFolder}/`);
}

export { buildLayoutFileName, isManagedOldPath };

function booleanValue(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  return value === true || value === 1 || value === '1' || String(value).toLowerCase() === 'true';
}

function apiError(message, status = 500) {
  const error = new Error(message);
  error.status = status;
  return error;
}

export default {
  id: 'symbolika-yandex-disk',
  handler: (router, { database, services, getSchema, env, logger }) => {
    const token = String(env.SYMBOLIKA_YANDEX_DISK_TOKEN || process.env.SYMBOLIKA_YANDEX_DISK_TOKEN || '').trim();
    const root = String(env.SYMBOLIKA_YANDEX_DISK_ROOT || process.env.SYMBOLIKA_YANDEX_DISK_ROOT || 'app:/Заказы').replace(/\/+$/, '');
    const publishFiles = booleanValue(
        env.SYMBOLIKA_YANDEX_DISK_PUBLISH_FILES || process.env.SYMBOLIKA_YANDEX_DISK_PUBLISH_FILES,
        true,
    );
    const deleteReplacedFiles = booleanValue(
        env.SYMBOLIKA_YANDEX_DISK_DELETE_REPLACED || process.env.SYMBOLIKA_YANDEX_DISK_DELETE_REPLACED,
        true,
    );

    const requireUser = (req, res) => {
      if (req.accountability?.user) return req.accountability.user;
      res.status(401).json({ errors: [{ message: 'Требуется авторизация.' }] });
      return null;
    };

    const assertCanReadOrderItem = async (itemId, accountability, schema) => {
      const itemService = new services.ItemsService('orders_items', { schema, accountability });
      try {
        await itemService.readOne(itemId, { fields: ['id'] });
        return;
      } catch (directError) {
        // Production roles intentionally have no direct access to a foreign
        // orders_items row. The dedicated work collection is their scoped,
        // read-only proof that this routed position belongs to their workshop.
        for (const collection of ['production_work', 'screen_printing_work']) {
          try {
            const workService = new services.ItemsService(collection, { schema, accountability });
            await workService.readOne(itemId, { fields: ['id'] });
            return;
          } catch {
            // Try the other workshop view before returning the original error.
          }
        }
        throw directError;
      }
    };

    const requestYandex = async (path, options = {}) => {
      if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);
      const url = new URL(`${API_ROOT}${path}`);
      for (const [key, value] of Object.entries(options.query || {})) {
        if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
      }
      const response = await fetch(url, {
        method: options.method || 'GET',
        headers: {
          Authorization: `OAuth ${token}`,
          ...(options.headers || {}),
        },
        body: options.body,
        ...(options.duplex ? { duplex: options.duplex } : {}),
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        const detail = payload?.description || payload?.message || `HTTP ${response.status}`;
        const error = apiError(`Яндекс Диск: ${detail}`, response.status >= 400 && response.status < 500 ? 400 : 502);
        error.yandexCode = payload?.error || '';
        throw error;
      }
      return payload;
    };

    const waitForYandexOperation = async (operation) => {
      const href = String(operation?.href || '').trim();
      if (!href) return;
      for (let attempt = 0; attempt < 40; attempt += 1) {
        const response = await fetch(href, { headers: { Authorization: `OAuth ${token}` } });
        const payload = await response.json().catch(() => null);
        if (!response.ok) throw apiError(`Яндекс Диск: ${payload?.description || payload?.message || `HTTP ${response.status}`}`, 502);
        if (payload?.status === 'success') return;
        if (payload?.status === 'failed') throw apiError('Яндекс Диск не смог переместить загруженный файл.', 502);
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
      throw apiError('Яндекс Диск слишком долго закрепляет файл за позицией. Повторите сохранение.', 504);
    };

    const ensureFolder = async (path) => {
      try {
        await requestYandex('/resources', { method: 'PUT', query: { path } });
      } catch (error) {
        if (error.yandexCode !== 'DiskPathPointsToExistentDirectoryError' && !/уже существует|already exists/i.test(error.message)) throw error;
      }
    };

    const ensureFolderTree = async (path) => {
      const prefix = path.startsWith('app:/') ? 'app:' : '';
      const segments = path.replace(/^app:\/?/, '').split('/').filter(Boolean);
      let current = prefix;
      for (const segment of segments) {
        current = `${current}/${segment}`;
        await ensureFolder(current);
      }
    };

    const safeDraftToken = (value) => {
      const tokenValue = String(value || '').trim();
      if (!/^[A-Za-z0-9_-]{12,100}$/.test(tokenValue)) throw apiError('Некорректный идентификатор фоновой загрузки.', 400);
      return tokenValue;
    };

    const draftFolderPath = (userId, draftToken) => `${root}/_drafts/${cleanSegment(userId, 'user')}/${safeDraftToken(draftToken)}`;

    const loadLayoutContext = async (itemId, accountability, schema) => {
      const itemService = new services.ItemsService('orders_items', { schema, accountability });
      await itemService.readOne(itemId, { fields: ['id'] });
      const item = await database('orders_items')
        .where('id', itemId)
        .select('id', 'order', 'product_name', 'quantity', 'layout_disk_path')
        .first();
      if (!item) throw apiError('Позиция заказа не найдена.', 404);
      const orderId = typeof item.order === 'object' ? item.order?.id : item.order;
      const order = await database('orders as o')
        .leftJoin('customers as customer', 'customer.id', 'o.customer')
        .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
        .where('o.id', orderId)
        .select('o.id', 'o.order_number', 'o.date', 'customer.name as customer_name', 'company.name as company_name')
        .first();
      if (!order) throw apiError('Заказ позиции не найден.', 404);
      return { itemService, item, order };
    };

    router.get('/status', async (req, res, next) => {
      try {
        if (!requireUser(req, res)) return;
        if (!token) return res.json({ data: { configured: false, connected: false, root } });
        await requestYandex('/resources', { query: { path: 'app:/', limit: 1, fields: 'path,name,type' } });
        return res.json({ data: { configured: true, connected: true, root, publish_files: publishFiles } });
      } catch (error) {
        logger.warn(`[Symbolika Yandex Disk] status: ${error.message}`);
        return res.status(error.status || 502).json({ errors: [{ message: error.message }] });
      }
    });

    router.post('/draft-layouts/:token/upload', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);
        const draftToken = safeDraftToken(req.params.token);
        const encodedName = String(req.headers['x-file-name'] || '');
        let originalName;
        try { originalName = decodeURIComponent(encodedName); } catch { originalName = encodedName; }
        const declaredSize = Number(req.headers['x-file-size'] || 0);
        if (!declaredSize || declaredSize < 0) throw apiError('Не удалось определить размер файла.', 400);
        if (declaredSize > MAX_FILE_SIZE) throw apiError('Файл больше 2 ГБ. Загрузите его на Диск вручную и вставьте ссылку.', 413);

        const folderPath = draftFolderPath(userId, draftToken);
        await ensureFolderTree(folderPath);
        const fileName = cleanSegment(originalName, 'Макет').slice(0, 220);
        const diskPath = `${folderPath}/${fileName}`;
        const upload = await requestYandex('/resources/upload', { query: { path: diskPath, overwrite: true } });
        if (!upload?.href) throw apiError('Яндекс Диск не вернул адрес загрузки.', 502);
        const uploadResponse = await fetch(upload.href, {
          method: upload.method || 'PUT',
          headers: { 'Content-Type': req.headers['content-type'] || 'application/octet-stream' },
          body: req,
          duplex: 'half',
        });
        if (!uploadResponse.ok) throw apiError(`Не удалось загрузить файл на Яндекс Диск: HTTP ${uploadResponse.status}.`, 502);
        const meta = await requestYandex('/resources', {
          query: { path: diskPath, fields: 'name,path,size,mime_type,created,modified,md5' },
        });
        return res.json({ data: {
          draft_token: draftToken,
          path: diskPath,
          name: meta.name || fileName,
          size: Number(meta.size || declaredSize),
          mime_type: meta.mime_type || req.headers['content-type'] || '',
        } });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] draft upload: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось загрузить черновой макет.' }] });
      }
    });

    router.post('/draft-layouts/:token/attach/:id', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);
        const draftToken = safeDraftToken(req.params.token);
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const draftRoot = draftFolderPath(userId, draftToken);
        const sourcePath = String(req.body?.path || '').trim();
        if (!sourcePath.startsWith(`${draftRoot}/`)) throw apiError('Черновой файл не принадлежит текущему пользователю.', 403);

        const schema = await getSchema();
        const { itemService, item, order } = await loadLayoutContext(itemId, req.accountability, schema);
        const sourceMeta = await requestYandex('/resources', {
          query: { path: sourcePath, fields: 'name,path,size,mime_type' },
        });
        const fileName = buildLayoutFileName({
          orderDate: order.date,
          customerName: order.company_name || order.customer_name,
          productName: item.product_name,
          quantity: item.quantity,
          originalName: sourceMeta.name,
        });
        const orderFolder = cleanSegment(order.order_number || `Заказ-${order.id}`, `Заказ-${order.id}`);
        const itemFolder = `Позиция-${itemId}`;
        const folderPath = `${root}/${orderFolder}/${itemFolder}`;
        await ensureFolderTree(folderPath);
        const diskPath = `${folderPath}/${fileName}`;
        const moveOperation = await requestYandex('/resources/move', {
          method: 'POST',
          query: { from: sourcePath, path: diskPath, overwrite: true },
        });
        await waitForYandexOperation(moveOperation);
        if (publishFiles) await requestYandex('/resources/publish', { method: 'PUT', query: { path: diskPath } });
        const meta = await requestYandex('/resources', {
          query: { path: diskPath, fields: 'name,path,size,mime_type,public_url,created,modified,md5' },
        });
        const link = meta.public_url || '';
        if (publishFiles && !link) throw apiError('Файл загружен, но публичная ссылка не была создана.', 502);
        await itemService.updateOne(itemId, { url: link || null });
        await database('orders_items').where('id', itemId).update({
          layout_disk_path: diskPath,
          layout_disk_name: meta.name || fileName,
          layout_disk_size: Number(meta.size || sourceMeta.size || 0),
          layout_disk_mime_type: meta.mime_type || sourceMeta.mime_type || null,
          layout_disk_uploaded_by: userId,
          layout_disk_uploaded_at: database.fn.now(),
        });
        const oldDiskPath = String(item.layout_disk_path || '').trim();
        if (deleteReplacedFiles && oldDiskPath && oldDiskPath !== diskPath && isManagedOldPath(oldDiskPath, { root, orderFolder, itemFolder })) {
          try {
            await requestYandex('/resources', { method: 'DELETE', query: { path: oldDiskPath, permanently: true } });
          } catch (cleanupError) {
            logger.warn(`[Symbolika Yandex Disk] old file cleanup (${oldDiskPath}): ${cleanupError.message}`);
          }
        }
        try {
          await requestYandex('/resources', { method: 'DELETE', query: { path: draftRoot, permanently: true } });
        } catch (cleanupError) {
          if (cleanupError.yandexCode !== 'DiskNotFoundError') logger.warn(`[Symbolika Yandex Disk] draft folder cleanup (${draftRoot}): ${cleanupError.message}`);
        }
        return res.json({ data: {
          item_id: itemId,
          url: link,
          name: meta.name || fileName,
          size: Number(meta.size || sourceMeta.size || 0),
          mime_type: meta.mime_type || sourceMeta.mime_type || '',
          path: diskPath,
        } });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] draft attach: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось прикрепить черновой макет.' }] });
      }
    });

    router.delete('/draft-layouts/:token', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const folderPath = draftFolderPath(userId, req.params.token);
        try {
          await requestYandex('/resources', { method: 'DELETE', query: { path: folderPath, permanently: true } });
        } catch (error) {
          if (error.yandexCode !== 'DiskNotFoundError') throw error;
        }
        return res.json({ data: { deleted: true } });
      } catch (error) {
        logger.warn(`[Symbolika Yandex Disk] draft cleanup: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось удалить черновой макет.' }] });
      }
    });

    router.get('/orders-items/:id/attachments', async (req, res) => {
      try {
        if (!requireUser(req, res)) return;
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const schema = await getSchema();
        await assertCanReadOrderItem(itemId, req.accountability, schema);
        const rows = await database('order_item_attachments')
          .where('order_item', itemId)
          .select('id', 'order_item', 'attachment_type', 'title', 'url', 'disk_path', 'file_name', 'file_size', 'mime_type', 'uploaded_by', 'date_created')
          .orderBy('date_created', 'asc')
          .orderBy('id', 'asc');
        return res.json({ data: rows });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] attachments list: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось загрузить материалы позиции.' }] });
      }
    });

    router.post('/orders-items/:id/attachments/link', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const rawUrl = String(req.body?.url || '').trim();
        const candidate = /^https?:\/\//i.test(rawUrl) ? rawUrl : `https://${rawUrl}`;
        let externalUrl = '';
        try {
          const parsed = new URL(candidate);
          if (['http:', 'https:'].includes(parsed.protocol) && parsed.hostname) externalUrl = parsed.href;
        } catch {
          externalUrl = '';
        }
        if (!externalUrl) throw apiError('Укажите корректную ссылку.', 400);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        const accessibleItem = await itemService.readOne(itemId, { fields: ['id', 'url'] });
        // updateOne also enforces edit permissions for the current user.
        await itemService.updateOne(itemId, { url: accessibleItem.url || externalUrl });
        const [row] = await database('order_item_attachments').insert({
          order_item: itemId,
          attachment_type: 'link',
          title: String(req.body?.title || '').trim() || null,
          url: externalUrl,
          uploaded_by: userId,
        }).returning(['id', 'order_item', 'attachment_type', 'title', 'url', 'disk_path', 'file_name', 'file_size', 'mime_type', 'uploaded_by', 'date_created']);
        return res.json({ data: row });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] attachment link: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось добавить ссылку.' }] });
      }
    });

    router.post('/orders-items/:id/attachments/upload', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const encodedName = String(req.headers['x-file-name'] || '');
        let originalName;
        try { originalName = decodeURIComponent(encodedName); } catch { originalName = encodedName; }
        const declaredSize = Number(req.headers['x-file-size'] || 0);
        if (!declaredSize || declaredSize < 0) throw apiError('Не удалось определить размер файла.', 400);
        if (declaredSize > MAX_FILE_SIZE) throw apiError('Файл больше 2 ГБ. Добавьте ссылку на него.', 413);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        const accessibleItem = await itemService.readOne(itemId, { fields: ['id', 'url'] });
        // This is deliberately performed before accepting the stream so a user
        // with read-only access cannot append files to the position.
        await itemService.updateOne(itemId, { url: accessibleItem.url || null });
        const item = await database('orders_items')
          .where('orders_items.id', itemId)
          .leftJoin('orders as o', 'o.id', 'orders_items.order')
          .leftJoin('customers as customer', 'customer.id', 'o.customer')
          .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
          .select(
            'orders_items.id', 'orders_items.product_name', 'orders_items.quantity',
            'o.id as order_id', 'o.order_number', 'o.date as order_date',
            'customer.name as customer_name', 'company.name as company_name',
          )
          .first();
        if (!item) throw apiError('Позиция заказа не найдена.', 404);

        const fileName = buildAttachmentFileName({
          orderDate: item.order_date,
          customerName: item.company_name || item.customer_name,
          productName: item.product_name,
          quantity: item.quantity,
        }, originalName);
        const orderFolder = cleanSegment(item.order_number || `Заказ-${item.order_id}`, `Заказ-${item.order_id}`);
        const itemFolder = `Позиция-${itemId}`;
        const folderPath = `${root}/${orderFolder}/${itemFolder}/Материалы`;
        await ensureFolderTree(folderPath);
        const diskPath = `${folderPath}/${fileName}`;
        const upload = await requestYandex('/resources/upload', { query: { path: diskPath, overwrite: false } });
        if (!upload?.href) throw apiError('Яндекс Диск не вернул адрес загрузки.', 502);
        const uploadResponse = await fetch(upload.href, {
          method: upload.method || 'PUT',
          headers: { 'Content-Type': req.headers['content-type'] || 'application/octet-stream' },
          body: req,
          duplex: 'half',
        });
        if (!uploadResponse.ok) throw apiError(`Не удалось загрузить файл на Яндекс Диск: HTTP ${uploadResponse.status}.`, 502);
        if (publishFiles) await requestYandex('/resources/publish', { method: 'PUT', query: { path: diskPath } });
        const meta = await requestYandex('/resources', {
          query: { path: diskPath, fields: 'name,path,size,mime_type,public_url,created,modified' },
        });
        const link = meta.public_url || '';
        if (publishFiles && !link) throw apiError('Файл загружен, но публичная ссылка не создана.', 502);
        if (!accessibleItem.url && link) await itemService.updateOne(itemId, { url: link });
        const [row] = await database('order_item_attachments').insert({
          order_item: itemId,
          attachment_type: 'file',
          title: originalName || meta.name || fileName,
          url: link,
          disk_path: diskPath,
          file_name: meta.name || fileName,
          file_size: Number(meta.size || declaredSize),
          mime_type: meta.mime_type || req.headers['content-type'] || null,
          uploaded_by: userId,
        }).returning(['id', 'order_item', 'attachment_type', 'title', 'url', 'disk_path', 'file_name', 'file_size', 'mime_type', 'uploaded_by', 'date_created']);
        return res.json({ data: row });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] attachment upload: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось загрузить материал.' }] });
      }
    });

    router.delete('/orders-items/:itemId/attachments/:attachmentId', async (req, res) => {
      try {
        if (!requireUser(req, res)) return;
        const itemId = Number(req.params.itemId);
        const attachmentId = Number(req.params.attachmentId);
        if (!Number.isInteger(itemId) || itemId <= 0 || !Number.isInteger(attachmentId) || attachmentId <= 0) {
          throw apiError('Некорректный материал позиции.', 400);
        }
        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        const accessibleItem = await itemService.readOne(itemId, { fields: ['id', 'url'] });
        await itemService.updateOne(itemId, { url: accessibleItem.url || null });
        const attachment = await database('order_item_attachments').where({ id: attachmentId, order_item: itemId }).first();
        if (!attachment) throw apiError('Материал не найден.', 404);
        await database('order_item_attachments').where({ id: attachmentId, order_item: itemId }).delete();
        if (attachment.url && attachment.url === accessibleItem.url) {
          const replacement = await database('order_item_attachments').where('order_item', itemId).orderBy('date_created', 'asc').orderBy('id', 'asc').first();
          await itemService.updateOne(itemId, { url: replacement?.url || null });
        }
        const diskPath = String(attachment.disk_path || '').trim();
        if (token && deleteReplacedFiles && diskPath && (diskPath === root || diskPath.startsWith(`${root}/`))) {
          try {
            await requestYandex('/resources', { method: 'DELETE', query: { path: diskPath, permanently: true } });
          } catch (cleanupError) {
            logger.warn(`[Symbolika Yandex Disk] attachment cleanup (${diskPath}): ${cleanupError.message}`);
          }
        }
        return res.json({ data: { id: attachmentId, deleted: true } });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] attachment delete: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось удалить материал.' }] });
      }
    });

    router.delete('/orders-items/:id', async (req, res) => {
      try {
        if (!requireUser(req, res)) return;
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        const accessibleItem = await itemService.readOne(itemId, { fields: ['id', 'item_status'] });
        const diskMeta = await database('orders_items')
          .where('id', itemId)
          .select('layout_disk_path', 'layout_preview_disk_path')
          .first();
        const attachmentDiskPaths = await database('order_item_attachments')
          .where('order_item', itemId)
          .whereNotNull('disk_path')
          .pluck('disk_path');
        const item = { ...accessibleItem, ...(diskMeta || {}) };
        const status = String(item?.item_status || 'new').trim().toLowerCase();
        if (!['new', 'approval'].includes(status)) {
          throw apiError('Удалить позицию можно только до её запуска в работу.', 409);
        }

        const relatedTaskIds = (await database('symbolika_tasks')
          .where('related_order_item', itemId)
          .pluck('id'))
          .map((value) => Number(value))
          .filter(Number.isInteger);
        await itemService.deleteOne(itemId);

        // Unlaunched design/production tasks have no meaning without their item.
        // Their checklist, comments and attachments are removed by task cascades.
        if (relatedTaskIds.length) await database('symbolika_tasks').whereIn('id', relatedTaskIds).delete();

        if (token && deleteReplacedFiles) {
          const paths = [...new Set([item.layout_disk_path, item.layout_preview_disk_path, ...attachmentDiskPaths]
            .map((value) => String(value || '').trim())
            .filter((value) => value && (value === root || value.startsWith(`${root}/`))))];
          for (const path of paths) {
            try {
              await requestYandex('/resources', { method: 'DELETE', query: { path, permanently: true } });
            } catch (cleanupError) {
              logger.warn(`[Symbolika Yandex Disk] deleted item file cleanup (${path}): ${cleanupError.message}`);
            }
          }
        }

        return res.json({ data: { id: itemId, deleted: true } });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] delete item: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось удалить позицию.' }] });
      }
    });

    router.post('/orders-items/:id/upload', async (req, res, next) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);

        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const encodedName = String(req.headers['x-file-name'] || '');
        let originalName;
        try { originalName = decodeURIComponent(encodedName); } catch { originalName = encodedName; }
        const declaredSize = Number(req.headers['x-file-size'] || 0);
        if (!declaredSize || declaredSize < 0) throw apiError('Не удалось определить размер файла.', 400);
        if (declaredSize > MAX_FILE_SIZE) throw apiError('Файл больше 2 ГБ. Загрузите его на Диск вручную и вставьте ссылку.', 413);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        await itemService.readOne(itemId, { fields: ['id'] });
        const item = await database('orders_items')
          .where('id', itemId)
          .select('id', 'order', 'product_name', 'quantity', 'layout_disk_path')
          .first();
        if (!item) throw apiError('Позиция заказа не найдена.', 404);
        const orderId = typeof item.order === 'object' ? item.order?.id : item.order;
        const order = await database('orders as o')
          .leftJoin('customers as customer', 'customer.id', 'o.customer')
          .leftJoin('customer_companies as company', 'company.id', 'o.customer_company')
          .where('o.id', orderId)
          .select(
            'o.id',
            'o.order_number',
            'o.date',
            'customer.name as customer_name',
            'company.name as company_name',
          )
          .first();
        if (!order) throw apiError('Заказ позиции не найден.', 404);

        const fileName = buildLayoutFileName({
          orderDate: order.date,
          customerName: order.company_name || order.customer_name,
          productName: item.product_name,
          quantity: item.quantity,
          originalName,
        });

        const orderFolder = cleanSegment(order.order_number || `Заказ-${order.id}`, `Заказ-${order.id}`);
        const itemFolder = `Позиция-${itemId}`;
        const folderPath = `${root}/${orderFolder}/${itemFolder}`;
        await ensureFolderTree(folderPath);

        const diskPath = `${folderPath}/${fileName}`;
        const upload = await requestYandex('/resources/upload', { query: { path: diskPath, overwrite: true } });
        if (!upload?.href) throw apiError('Яндекс Диск не вернул адрес загрузки.', 502);

        const uploadResponse = await fetch(upload.href, {
          method: upload.method || 'PUT',
          headers: { 'Content-Type': req.headers['content-type'] || 'application/octet-stream' },
          body: req,
          duplex: 'half',
        });
        if (!uploadResponse.ok) throw apiError(`Не удалось загрузить файл на Яндекс Диск: HTTP ${uploadResponse.status}.`, 502);

        if (publishFiles) await requestYandex('/resources/publish', { method: 'PUT', query: { path: diskPath } });
        const meta = await requestYandex('/resources', {
          query: { path: diskPath, fields: 'name,path,size,mime_type,public_url,created,modified,md5' },
        });
        const link = meta.public_url || '';
        if (publishFiles && !link) throw apiError('Файл загружен, но публичная ссылка не была создана.', 502);

        await itemService.updateOne(itemId, { url: link || null });
        await database('orders_items').where('id', itemId).update({
          layout_disk_path: diskPath,
          layout_disk_name: meta.name || fileName,
          layout_disk_size: Number(meta.size || declaredSize),
          layout_disk_mime_type: meta.mime_type || req.headers['content-type'] || null,
          layout_disk_uploaded_by: userId,
          layout_disk_uploaded_at: database.fn.now(),
        });

        const oldDiskPath = String(item.layout_disk_path || '').trim();
        const oldPathIsManaged = isManagedOldPath(oldDiskPath, { root, orderFolder, itemFolder });
        if (deleteReplacedFiles && oldPathIsManaged && oldDiskPath !== diskPath) {
          try {
            await requestYandex('/resources', {
              method: 'DELETE',
              query: { path: oldDiskPath, permanently: true },
            });
          } catch (cleanupError) {
            logger.warn(`[Symbolika Yandex Disk] old file cleanup (${oldDiskPath}): ${cleanupError.message}`);
          }
        }

        return res.json({
          data: {
            item_id: itemId,
            url: link,
            name: meta.name || fileName,
            size: Number(meta.size || declaredSize),
            mime_type: meta.mime_type || req.headers['content-type'] || '',
            path: diskPath,
          },
        });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] upload: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось загрузить макет.' }] });
      }
    });

    router.post('/orders-items/:id/link', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;

        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const rawUrl = String(req.body?.url || '').trim();
        const candidate = /^https?:\/\//i.test(rawUrl) ? rawUrl : `https://${rawUrl}`;
        let externalUrl = '';
        try {
          const parsed = new URL(candidate);
          if (['http:', 'https:'].includes(parsed.protocol) && parsed.hostname) externalUrl = parsed.href;
        } catch {
          externalUrl = '';
        }
        if (!externalUrl) throw apiError('Укажите корректную ссылку на макет.', 400);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        await itemService.readOne(itemId, { fields: ['id'] });
        const item = await database('orders_items')
          .where('id', itemId)
          .select('id', 'layout_disk_path')
          .first();
        if (!item) throw apiError('Позиция заказа не найдена.', 404);

        await itemService.updateOne(itemId, { url: externalUrl });
        await database('orders_items').where('id', itemId).update({
          layout_disk_path: null,
          layout_disk_name: null,
          layout_disk_size: null,
          layout_disk_mime_type: null,
          layout_disk_uploaded_by: null,
          layout_disk_uploaded_at: null,
        });

        const oldDiskPath = String(item.layout_disk_path || '').trim();
        const oldPathIsManaged = oldDiskPath === root || oldDiskPath.startsWith(`${root}/`);
        if (token && deleteReplacedFiles && oldPathIsManaged) {
          try {
            await requestYandex('/resources', {
              method: 'DELETE',
              query: { path: oldDiskPath, permanently: true },
            });
          } catch (cleanupError) {
            logger.warn(`[Symbolika Yandex Disk] old file cleanup (${oldDiskPath}): ${cleanupError.message}`);
          }
        }

        return res.json({ data: { item_id: itemId, url: externalUrl } });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] external link: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось сохранить ссылку на макет.' }] });
      }
    });

    router.get('/orders-items/:id/preview/content', async (req, res) => {
      try {
        if (!requireUser(req, res)) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);
        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);
        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        await itemService.readOne(itemId, { fields: ['id'] });
        const item = await database('orders_items')
          .where('id', itemId)
          .select('layout_preview_disk_path')
          .first();
        if (!item?.layout_preview_disk_path) throw apiError('Превью макета не найдено.', 404);
        const download = await requestYandex('/resources/download', { query: { path: item.layout_preview_disk_path } });
        if (!download?.href) throw apiError('Яндекс Диск не вернул адрес превью.', 502);
        res.setHeader('Cache-Control', 'private, max-age=300');
        return res.redirect(302, download.href);
      } catch (error) {
        logger.warn(`[Symbolika Yandex Disk] preview content: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось открыть превью макета.' }] });
      }
    });

    router.post('/orders-items/:id/preview', async (req, res) => {
      try {
        const userId = requireUser(req, res);
        if (!userId) return;
        if (!token) throw apiError('Интеграция с Яндекс Диском не настроена.', 503);

        const itemId = Number(req.params.id);
        if (!Number.isInteger(itemId) || itemId <= 0) throw apiError('Некорректная позиция заказа.', 400);

        const encodedName = String(req.headers['x-file-name'] || 'preview.png');
        let originalName;
        try { originalName = decodeURIComponent(encodedName); } catch { originalName = encodedName; }
        const declaredSize = Number(req.headers['x-file-size'] || 0);
        const contentType = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
        const extension = fileExtension(originalName);
        const allowedType = contentType === 'image/jpeg' || contentType === 'image/png';
        const allowedExtension = ['.jpg', '.jpeg', '.png'].includes(extension);
        if (!declaredSize || declaredSize < 0) throw apiError('Не удалось определить размер превью.', 400);
        if (declaredSize > MAX_PREVIEW_SIZE) throw apiError('Превью больше 20 МБ. Уменьшите изображение и повторите загрузку.', 413);
        if (!allowedType || !allowedExtension) throw apiError('Для превью можно загрузить только JPEG или PNG.', 415);

        const schema = await getSchema();
        const itemService = new services.ItemsService('orders_items', { schema, accountability: req.accountability });
        await itemService.readOne(itemId, { fields: ['id'] });
        const item = await database('orders_items')
          .where('id', itemId)
          .select('id', 'order', 'product_name', 'layout_preview_disk_path')
          .first();
        if (!item) throw apiError('Позиция заказа не найдена.', 404);

        const orderId = typeof item.order === 'object' ? item.order?.id : item.order;
        const order = await database('orders').where('id', orderId).select('id', 'order_number').first();
        if (!order) throw apiError('Заказ позиции не найден.', 404);

        const orderFolder = cleanSegment(order.order_number || `Заказ-${order.id}`, `Заказ-${order.id}`);
        const itemFolder = `Позиция-${itemId}`;
        const folderPath = `${root}/${orderFolder}/${itemFolder}`;
        await ensureFolderTree(folderPath);

        const normalizedExtension = contentType === 'image/png' ? '.png' : '.jpg';
        const previewBase = cleanSegment(`Превью-${item.product_name || itemId}`, `Превью-${itemId}`).slice(0, 190);
        const fileName = `${previewBase}${normalizedExtension}`;
        const diskPath = `${folderPath}/${fileName}`;
        const upload = await requestYandex('/resources/upload', { query: { path: diskPath, overwrite: true } });
        if (!upload?.href) throw apiError('Яндекс Диск не вернул адрес загрузки превью.', 502);

        const uploadResponse = await fetch(upload.href, {
          method: upload.method || 'PUT',
          headers: { 'Content-Type': contentType },
          body: req,
          duplex: 'half',
        });
        if (!uploadResponse.ok) throw apiError(`Не удалось загрузить превью на Яндекс Диск: HTTP ${uploadResponse.status}.`, 502);

        if (publishFiles) await requestYandex('/resources/publish', { method: 'PUT', query: { path: diskPath } });
        const meta = await requestYandex('/resources', {
          query: { path: diskPath, fields: 'name,path,size,mime_type,public_url,created,modified' },
        });
        const link = meta.public_url || '';
        if (publishFiles && !link) throw apiError('Превью загружено, но публичная ссылка не была создана.', 502);

        await database('orders_items').where('id', itemId).update({
          layout_preview_url: link || null,
          layout_preview_disk_path: diskPath,
          layout_preview_disk_name: meta.name || fileName,
          layout_preview_disk_size: Number(meta.size || declaredSize),
          layout_preview_disk_mime_type: meta.mime_type || contentType,
          layout_preview_uploaded_by: userId,
          layout_preview_uploaded_at: database.fn.now(),
        });

        const oldDiskPath = String(item.layout_preview_disk_path || '').trim();
        const oldPathIsManaged = isManagedOldPath(oldDiskPath, { root, orderFolder, itemFolder });
        if (deleteReplacedFiles && oldPathIsManaged && oldDiskPath !== diskPath) {
          try {
            await requestYandex('/resources', {
              method: 'DELETE',
              query: { path: oldDiskPath, permanently: true },
            });
          } catch (cleanupError) {
            logger.warn(`[Symbolika Yandex Disk] old preview cleanup (${oldDiskPath}): ${cleanupError.message}`);
          }
        }

        return res.json({
          data: {
            item_id: itemId,
            url: link,
            name: meta.name || fileName,
            size: Number(meta.size || declaredSize),
            mime_type: meta.mime_type || contentType,
            path: diskPath,
          },
        });
      } catch (error) {
        logger.error(`[Symbolika Yandex Disk] preview upload: ${error.message}`);
        return res.status(error.status || 500).json({ errors: [{ message: error.message || 'Не удалось загрузить превью макета.' }] });
      }
    });
  },
};

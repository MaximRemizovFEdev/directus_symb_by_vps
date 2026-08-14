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

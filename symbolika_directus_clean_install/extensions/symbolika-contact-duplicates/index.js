const ENTITY_CONFIG = {
  customer: {
    table: 'customers',
    label: 'клиента',
    relations: [
      ['customer_company_links', 'customer'],
      ['gift_certificates', 'customer'],
      ['order_estimates', 'customer'],
      ['order_payments', 'customer'],
      ['orders', 'customer'],
      ['procurement_requests', 'customer'],
      ['symbolika_customer_notifications', 'customer'],
      ['symbolika_mail_threads', 'customer_id'],
      ['symbolika_tasks', 'related_customer'],
    ],
  },
  company: {
    table: 'customer_companies',
    label: 'компанию',
    relations: [
      ['customer_company_links', 'customer_companies'],
      ['customers', 'company'],
      ['order_estimates', 'customer_company'],
      ['order_payments', 'customer_company'],
      ['orders', 'customer_company'],
      ['procurement_requests', 'customer_company'],
      ['symbolika_customer_notifications', 'customer_company'],
      ['symbolika_mail_threads', 'company_id'],
      ['symbolika_tasks', 'related_company'],
    ],
  },
};

function numericId(value) {
  const id = Number(value || 0);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function normalizePhone(value) {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('8')) digits = `7${digits.slice(1)}`;
  if (digits.length === 10) digits = `7${digits}`;
  return digits.length >= 7 ? digits : '';
}

function normalizeEmail(value) {
  return String(value || '').trim().toLocaleLowerCase('ru-RU');
}

function normalizeName(value) {
  return String(value || '')
    .trim()
    .toLocaleLowerCase('ru-RU')
    .replace(/ё/g, 'е')
    .replace(/[«»"'`]/g, '')
    .replace(/[^a-zа-я0-9]+/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function signedOpeningBalance(row) {
  const amount = Number(row?.opening_balance_amount || 0);
  return row?.opening_balance_direction === 'we_owe_customer' ? -amount : amount;
}

function duplicateGroups(rows, entityType) {
  const parents = rows.map((_, index) => index);
  const find = (index) => {
    let current = index;
    while (parents[current] !== current) current = parents[current];
    while (parents[index] !== index) {
      const next = parents[index];
      parents[index] = current;
      index = next;
    }
    return current;
  };
  const unite = (left, right) => {
    const leftRoot = find(left);
    const rightRoot = find(right);
    if (leftRoot !== rightRoot) parents[rightRoot] = leftRoot;
  };
  const indexes = { phone: new Map(), email: new Map(), name: new Map() };

  rows.forEach((row, rowIndex) => {
    const values = {
      phone: normalizePhone(row.phone),
      email: normalizeEmail(row.email),
      name: normalizeName(row.name),
    };
    Object.entries(values).forEach(([kind, value]) => {
      if (!value) return;
      const previous = indexes[kind].get(value);
      if (previous !== undefined) unite(previous, rowIndex);
      else indexes[kind].set(value, rowIndex);
    });
  });

  const components = new Map();
  rows.forEach((row, index) => {
    const root = find(index);
    if (!components.has(root)) components.set(root, []);
    components.get(root).push(row);
  });

  return [...components.values()]
    .filter((records) => records.length > 1)
    .map((records) => {
      const reasons = [];
      const fields = [
        ['phone', normalizePhone, 'телефон'],
        ['email', normalizeEmail, 'email'],
        ['name', normalizeName, entityType === 'company' ? 'название' : 'имя'],
      ];
      fields.forEach(([field, normalize, label]) => {
        const counts = new Map();
        records.forEach((record) => {
          const value = normalize(record[field]);
          if (value) counts.set(value, (counts.get(value) || 0) + 1);
        });
        if ([...counts.values()].some((count) => count > 1)) reasons.push(label);
      });
      return {
        key: `${entityType}:${records.map((record) => record.id).sort((a, b) => a - b).join('-')}`,
        entity_type: entityType,
        reasons,
        records: records.sort((a, b) => Number(b.orders_count || 0) - Number(a.orders_count || 0) || Number(a.id) - Number(b.id)),
      };
    })
    .sort((a, b) => b.records.length - a.records.length || a.key.localeCompare(b.key));
}

function errorResponse(res, status, message) {
  return res.status(status).json({ errors: [{ message }] });
}

export default {
  id: 'symbolika-contact-duplicates',

  handler: (router, { database, logger }) => {
    async function requireAdministrator(req, res) {
      const userId = req.accountability?.user;
      if (!userId) {
        errorResponse(res, 401, 'Необходима авторизация.');
        return false;
      }
      const actor = await database('directus_users as u')
        .leftJoin('directus_roles as r', 'r.id', 'u.role')
        .where('u.id', userId)
        .select('r.name as role_name')
        .first();
      if (actor?.role_name !== 'Administrator') {
        errorResponse(res, 403, 'Проверка и объединение дублей доступны только администратору.');
        return false;
      }
      return true;
    }

    async function rowsFor(entityType) {
      const config = ENTITY_CONFIG[entityType];
      const companyField = entityType === 'customer' ? 'company' : database.raw('NULL::integer as company');
      return database(`${config.table} as entity`)
        .leftJoin('employees as manager_employee', 'manager_employee.id', 'entity.manager')
        .select(
          'entity.id', 'entity.name', 'entity.phone', 'entity.email', 'entity.manager', 'entity.comment',
          'entity.opening_balance_amount', 'entity.opening_balance_direction', 'entity.opening_balance_date',
          'manager_employee.full_name as manager_name',
          companyField,
          database.raw(`(select count(*)::integer from orders o where o.${entityType === 'customer' ? 'customer' : 'customer_company'} = entity.id) as orders_count`),
          database.raw(`(select count(*)::integer from symbolika_tasks t where t.${entityType === 'customer' ? 'related_customer' : 'related_company'} = entity.id) as tasks_count`),
          database.raw(`(select count(*)::integer from symbolika_mail_threads m where m.${entityType === 'customer' ? 'customer_id' : 'company_id'} = entity.id) as mail_threads_count`),
        )
        .orderBy('entity.id', 'asc');
    }

    router.get('/', async (req, res) => {
      try {
        if (!await requireAdministrator(req, res)) return;
        const requestedType = String(req.query?.type || '').trim();
        const types = ENTITY_CONFIG[requestedType] ? [requestedType] : ['customer', 'company'];
        const groups = [];
        for (const entityType of types) {
          groups.push(...duplicateGroups(await rowsFor(entityType), entityType));
        }
        return res.json({ data: groups });
      } catch (error) {
        logger.error(error);
        return errorResponse(res, 500, 'Не удалось проверить контакты на дубли.');
      }
    });

    router.post('/merge', async (req, res) => {
      try {
        if (!await requireAdministrator(req, res)) return;
        const entityType = String(req.body?.entity_type || '').trim();
        const config = ENTITY_CONFIG[entityType];
        const primaryId = numericId(req.body?.primary_id);
        const duplicateIds = [...new Set((Array.isArray(req.body?.duplicate_ids) ? req.body.duplicate_ids : [req.body?.duplicate_id])
          .map(numericId)
          .filter((id) => id && id !== primaryId))];
        if (!config || !primaryId || !duplicateIds.length) {
          return errorResponse(res, 400, 'Выберите основную запись и хотя бы один дубль.');
        }

        const result = await database.transaction(async (trx) => {
          const records = await trx(config.table)
            .whereIn('id', [primaryId, ...duplicateIds])
            .forUpdate();
          const primary = records.find((row) => Number(row.id) === primaryId);
          const duplicates = records.filter((row) => duplicateIds.includes(Number(row.id)));
          if (!primary || duplicates.length !== duplicateIds.length) {
            throw Object.assign(new Error('Одна из объединяемых записей уже удалена или недоступна.'), { status: 409 });
          }

          const missingValue = (value) => value === null || value === undefined || String(value).trim() === '';
          const update = {};
          ['phone', 'email', 'manager', 'notification_channel', 'telegram_chat_id', 'vk_peer_id'].forEach((field) => {
            if (!missingValue(primary[field])) return;
            const source = duplicates.find((row) => !missingValue(row[field]));
            if (source) update[field] = source[field];
          });
          if (entityType === 'customer') {
            ['company', 'vk_page_url'].forEach((field) => {
              if (!missingValue(primary[field])) return;
              const source = duplicates.find((row) => !missingValue(row[field]));
              if (source) update[field] = source[field];
            });
          }

          const comments = [primary, ...duplicates]
            .map((row) => String(row.comment || '').trim())
            .filter((value, index, values) => value && values.indexOf(value) === index);
          const alternativeContacts = duplicates
            .map((row) => {
              const values = [];
              if (normalizePhone(row.phone) && normalizePhone(row.phone) !== normalizePhone(primary.phone)) values.push(`телефон ${row.phone}`);
              if (normalizeEmail(row.email) && normalizeEmail(row.email) !== normalizeEmail(primary.email)) values.push(`email ${row.email}`);
              return values.length ? `Данные объединённой записи #${row.id}: ${values.join(', ')}.` : '';
            })
            .filter(Boolean);
          update.comment = [...comments, ...alternativeContacts].join('\n\n') || null;

          const openingComments = [primary, ...duplicates]
            .map((row) => String(row.opening_balance_comment || '').trim())
            .filter((value, index, values) => value && values.indexOf(value) === index);
          update.opening_balance_comment = openingComments.join('\n\n') || null;

          const openingBalance = [primary, ...duplicates].reduce((sum, row) => sum + signedOpeningBalance(row), 0);
          update.opening_balance_amount = Math.abs(openingBalance);
          update.opening_balance_direction = openingBalance < 0 ? 'we_owe_customer' : 'customer_owes_us';
          const openingDates = [primary, ...duplicates].map((row) => row.opening_balance_date).filter(Boolean).sort();
          if (openingDates.length) update.opening_balance_date = openingDates[0];

          const moved = {};
          const customerOperationField = entityType === 'customer' ? 'customer' : 'customer_company';
          const removedOpeningOperations = await trx('customer_operations')
            .whereIn(customerOperationField, duplicateIds)
            .where({ operation_type: 'opening_balance' })
            .delete();
          moved.customer_operations = Number(await trx('customer_operations')
            .whereIn(customerOperationField, duplicateIds)
            .update({ [customerOperationField]: primaryId }) || 0);
          moved.opening_balance_operations_merged = Number(removedOpeningOperations || 0);

          for (const [table, field] of config.relations) {
            const count = await trx(table).whereIn(field, duplicateIds).update({ [field]: primaryId });
            moved[table] = Number(count || 0);
          }

          if (entityType === 'customer') {
            await trx.raw(`
              delete from customer_company_links duplicate_link
              using customer_company_links kept_link
              where duplicate_link.id > kept_link.id
                and duplicate_link.customer = kept_link.customer
                and duplicate_link.customer_companies = kept_link.customer_companies
            `);
          }

          await trx(config.table).where({ id: primaryId }).update(update);
          await trx(config.table).whereIn('id', duplicateIds).delete();
          return { id: primaryId, removed_ids: duplicateIds, moved };
        });

        return res.json({ data: result });
      } catch (error) {
        logger.error(error);
        return errorResponse(res, Number(error?.status || error?.statusCode || 500), error?.message || 'Не удалось объединить дубли.');
      }
    });
  },
};

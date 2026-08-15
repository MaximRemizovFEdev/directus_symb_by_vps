import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';
import nodemailer from 'nodemailer';
import { randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MAIL_ROLES = new Set(['Administrator', 'Управляющий', 'Менеджер']);
const ADMIN_ROLES = new Set(['Administrator', 'Управляющий']);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/i;
const MAIL_ATTACHMENT_ROOT = '/directus/uploads/symbolika-mail';
const BRAND_LOGO_FILE = fileURLToPath(new URL('./assets/symbolika-logo.png', import.meta.url));
const BRAND_LOGO_URL = 'https://symbcorp.ru/symbolika-mail/brand-logo.png';
const LEGACY_BRAND_LOGO_URL = 'https://static.tildacdn.com/tild6465-3739-4736-b565-653037393965/2.png';

function cleanText(value, max = 5000) {
  return String(value ?? '').trim().slice(0, max);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function sanitizeSignatureHtml(value) {
  const source = cleanText(value, 20000);
  if (!source) return '';
  const withMarkup = /<\/?[a-z][^>]*>/i.test(source)
    ? source
    : escapeHtml(source).replace(/\r?\n/g, '<br>');
  const withoutUnsafeBlocks = withMarkup
    .replace(/<(script|style|iframe|object|embed|form|input|button)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<(script|style|iframe|object|embed|form|input|button)\b[^>]*\/?>/gi, '');
  const allowed = new Set(['p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 'u', 's', 'ul', 'ol', 'li', 'a']);
  return withoutUnsafeBlocks.replace(/<\/?([a-z0-9]+)\b([^>]*)>/gi, (match, rawTag, rawAttributes) => {
    const tag = rawTag.toLowerCase();
    if (!allowed.has(tag)) return '';
    if (match.startsWith('</')) return tag === 'br' ? '' : `</${tag}>`;
    if (tag === 'br') return '<br>';
    const attributes = [];
    const alignment = String(rawAttributes || '').match(/(?:style\s*=\s*["'][^"']*text-align\s*:\s*|align\s*=\s*["']?)(left|center|right)/i)?.[1];
    if (alignment && ['p', 'div'].includes(tag)) attributes.push(`style="text-align:${alignment.toLowerCase()}"`);
    if (tag === 'a') {
      const href = String(rawAttributes || '').match(/href\s*=\s*(["'])(.*?)\1/i)?.[2] || '';
      if (/^(https?:\/\/|mailto:|tel:)/i.test(href)) {
        attributes.push(`href="${escapeHtml(href)}"`, 'target="_blank"', 'rel="noopener noreferrer"');
      }
    }
    return `<${tag}${attributes.length ? ` ${attributes.join(' ')}` : ''}>`;
  }).slice(0, 20000);
}

function signaturePlainText(value) {
  return sanitizeSignatureHtml(value)
    .replace(/<br\s*>/gi, '\n')
    .replace(/<\/\s*(p|div|li)\s*>/gi, '\n')
    .replace(/<li\b[^>]*>/gi, '• ')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

const SIGNATURE_DEFAULTS = Object.freeze({
  website_label: 'symb62.ru',
  website_url: 'https://symb62.ru',
  address: 'г. Рязань, ул. Соборная, 46г',
  map_url: 'https://yandex.ru/maps/?text=%D0%B3.%20%D0%A0%D1%8F%D0%B7%D0%B0%D0%BD%D1%8C%2C%20%D1%83%D0%BB.%20%D0%A1%D0%BE%D0%B1%D0%BE%D1%80%D0%BD%D0%B0%D1%8F%2C%2046%D0%B3',
  vk_label: 'vk.com/universymbols',
  vk_url: 'https://vk.com/universymbols',
  slogan_line_1: 'Создаём бренд. Печатаем идеи.',
  slogan_line_2: 'Работаем с вниманием к деталям.',
  logo_url: BRAND_LOGO_URL,
});

function jsonObject(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  try {
    const parsed = JSON.parse(value || '{}');
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function safeUrl(value, fallback = '') {
  const url = cleanText(value, 1500);
  return !url || /^https?:\/\//i.test(url) ? url : fallback;
}

function signatureDefaults(employee, email) {
  return {
    full_name: cleanText(employee?.employee_name || employee?.full_name || 'Символика', 255),
    position: cleanText(employee?.public_position || 'Команда Символики', 255),
    phone: cleanText(employee?.employee_phone || employee?.phone, 64),
    email: cleanText(email || employee?.email, 255).toLowerCase(),
    ...SIGNATURE_DEFAULTS,
  };
}

function signatureSettings(employee, email, input = undefined) {
  const defaults = signatureDefaults(employee, email);
  const source = input === undefined ? jsonObject(employee?.email_signature_settings) : jsonObject(input);
  const text = (key, max = 500) => Object.prototype.hasOwnProperty.call(source, key)
    ? cleanText(source[key], max)
    : defaults[key];
  return {
    full_name: text('full_name', 255), position: text('position', 255), phone: text('phone', 64),
    email: EMAIL_PATTERN.test(text('email', 255)) ? text('email', 255).toLowerCase() : defaults.email,
    website_label: text('website_label', 255), website_url: safeUrl(text('website_url', 1500), defaults.website_url),
    address: text('address', 500), map_url: safeUrl(text('map_url', 1500), defaults.map_url),
    vk_label: text('vk_label', 255), vk_url: safeUrl(text('vk_url', 1500), defaults.vk_url),
    slogan_line_1: text('slogan_line_1', 500), slogan_line_2: text('slogan_line_2', 500),
    logo_url: safeUrl(text('logo_url', 1500), defaults.logo_url) === LEGACY_BRAND_LOGO_URL
      ? BRAND_LOGO_URL
      : safeUrl(text('logo_url', 1500), defaults.logo_url),
  };
}

function legacyBrandedSignatureHtml(employee, email) {
  const settings = signatureSettings(employee, email);
  const phoneLink = settings.phone.replace(/[^+\d]/g, '');
  const contactRow = (icon, content, href = '') => content ? `<tr><td style="padding:5px 10px 5px 0;vertical-align:middle"><span style="display:inline-block;width:26px;height:26px;border-radius:50%;background:#f97316;color:#fff;text-align:center;line-height:26px;font-size:13px">${icon}</span></td><td style="padding:5px 0;border-bottom:1px solid #46515e;color:#f5f7fa;font-size:13px;line-height:18px">${href ? `<a href="${escapeHtml(href)}" style="color:#f5f7fa;text-decoration:none">${escapeHtml(content)}</a>` : escapeHtml(content)}</td></tr>` : '';
  const custom = sanitizeSignatureHtml(employee?.email_signature);
  return `<style>@media only screen and (max-width:620px){.symb-signature .symb-cell{display:block!important;width:auto!important;padding:15px 18px!important;border-left:0!important}.symb-signature .symb-person{border-top:1px solid #46515e!important;border-bottom:1px solid #46515e!important}}</style><table role="presentation" class="symb-signature" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:760px;margin-top:22px;border:1px solid #39434f;border-radius:14px;background:#171c22;color:#f5f7fa;font-family:Arial,sans-serif;box-shadow:0 4px 16px rgba(15,23,42,.18)"><tr>
<td class="symb-cell" style="width:190px;padding:25px;vertical-align:middle;text-align:center">${settings.logo_url ? `<img src="${escapeHtml(settings.logo_url)}" width="168" alt="Символика" style="display:block;width:168px;max-width:100%;height:auto;margin:0 auto">` : '<div style="font-size:24px;font-weight:800">Символика</div>'}</td>
<td class="symb-cell symb-person" style="width:235px;padding:25px 28px;border-left:2px solid #f97316;vertical-align:middle"><div style="color:#f5f7fa;font-size:22px;font-weight:800;line-height:27px">${escapeHtml(settings.full_name)}</div><div style="margin-top:5px;color:#f97316;font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase">${escapeHtml(settings.position)}</div><div style="width:38px;height:2px;margin:15px 0;background:#f97316"></div><div style="color:#c3c9d1;font-size:12px;font-style:italic;line-height:18px">${escapeHtml(settings.slogan_line_1)}${settings.slogan_line_2 ? `<br>${escapeHtml(settings.slogan_line_2)}` : ''}</div></td>
<td class="symb-cell" style="padding:20px 24px;vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0" style="width:100%">${contactRow('☎', settings.phone, phoneLink ? `tel:${phoneLink}` : '')}${contactRow('✉', settings.email, settings.email ? `mailto:${settings.email}` : '')}${contactRow('◎', settings.website_label, settings.website_url)}${contactRow('◉', settings.address, settings.map_url)}${contactRow('VK', settings.vk_label, settings.vk_url)}</table></td>
</tr></table>${custom ? `<div style="max-width:760px;margin-top:10px;font-family:Arial,sans-serif;font-size:12px;color:#66717f">${custom}</div>` : ''}`;
}

function brandedSignatureHtml(employee, email) {
  const settings = signatureSettings(employee, email);
  const logoUrl = settings.logo_url === LEGACY_BRAND_LOGO_URL ? BRAND_LOGO_URL : settings.logo_url;
  const phoneLink = settings.phone.replace(/[^+\d]/g, '');
  const contactRow = (icon, content, href = '') => content ? `<tr><td style="padding:3px 7px 3px 0;vertical-align:middle"><span style="display:inline-block;width:20px;height:20px;border-radius:50%;background:#f97316;color:#fff;text-align:center;line-height:20px;font-size:9px;font-weight:700">${icon}</span></td><td style="padding:3px 0;border-bottom:1px solid #46515e;color:#f5f7fa;font-size:11px;line-height:14px">${href ? `<a href="${escapeHtml(href)}" style="color:#f5f7fa;text-decoration:none">${escapeHtml(content)}</a>` : escapeHtml(content)}</td></tr>` : '';
  const custom = sanitizeSignatureHtml(employee?.email_signature);
  return `<style>@media only screen and (max-width:480px){.symb-signature .symb-slogan{display:none!important}.symb-signature .symb-brand{width:82px!important;padding:10px!important}.symb-signature .symb-person{width:125px!important;padding:10px 12px!important}.symb-signature .symb-contacts{padding:8px 10px!important}}</style><table role="presentation" class="symb-signature" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;margin-top:14px;border:1px solid #39434f;border-radius:11px;background:#171c22;color:#f5f7fa;font-family:Arial,sans-serif"><tr>
<td class="symb-cell symb-brand" style="width:112px;padding:14px;vertical-align:middle;text-align:center">${logoUrl ? `<img src="${escapeHtml(logoUrl)}" width="104" alt="Символика" style="display:block;width:104px;max-width:100%;height:auto;margin:0 auto">` : '<div style="font-size:18px;font-weight:800">Символика</div>'}</td>
<td class="symb-cell symb-person" style="width:168px;padding:14px 16px;border-left:2px solid #f97316;vertical-align:middle"><div style="color:#f5f7fa;font-size:17px;font-weight:800;line-height:20px">${escapeHtml(settings.full_name)}</div><div style="margin-top:4px;color:#f97316;font-size:10px;font-weight:800;letter-spacing:.06em;text-transform:uppercase">${escapeHtml(settings.position)}</div><div style="width:30px;height:2px;margin:9px 0;background:#f97316"></div><div class="symb-slogan" style="color:#c3c9d1;font-size:10px;font-style:italic;line-height:14px">${escapeHtml(settings.slogan_line_1)}${settings.slogan_line_2 ? `<br>${escapeHtml(settings.slogan_line_2)}` : ''}</div></td>
<td class="symb-cell symb-contacts" style="padding:10px 14px;vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0" style="width:100%">${contactRow('&#9742;', settings.phone, phoneLink ? `tel:${phoneLink}` : '')}${contactRow('&#9993;', settings.email, settings.email ? `mailto:${settings.email}` : '')}${contactRow('www', settings.website_label, settings.website_url)}${contactRow('&#9679;', settings.address, settings.map_url)}${contactRow('VK', settings.vk_label, settings.vk_url)}</table></td>
</tr></table>${custom ? `<div style="max-width:600px;margin-top:8px;font-family:Arial,sans-serif;font-size:11px;color:#66717f">${custom}</div>` : ''}`;
}

function boolEnv(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  return ['true', '1', 'yes', 'on'].includes(String(value).toLowerCase());
}

function jsonArray(value) {
  if (Array.isArray(value)) return value;
  if (!value) return [];
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function addressList(value) {
  const rows = value?.value || value || [];
  return (Array.isArray(rows) ? rows : [rows]).map((row) => ({
    name: cleanText(row?.name, 255),
    email: cleanText(row?.address || row?.email || row, 255).toLowerCase(),
  })).filter((row) => EMAIL_PATTERN.test(row.email));
}

function normalizeSubject(value) {
  return cleanText(value || '(без темы)', 1000)
    .replace(/^\s*((re|fw|fwd|ответ|пересылка)\s*:\s*)+/i, '')
    .toLowerCase();
}

function plainMailPreview(value, max = 240) {
  return cleanText(value, Math.max(max * 6, 1000))
    .replace(/<!doctype[^>]*>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<\/p\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function apiError(res, status, message) {
  return res.status(status).json({ errors: [{ message }] });
}

function safeAttachmentName(value) {
  const normalized = cleanText(value || 'Вложение', 500)
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/^\.+/, '')
    .trim();
  return normalized || 'Вложение';
}

function contentDisposition(disposition, filename) {
  const fallback = safeAttachmentName(filename).replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
  const encoded = encodeURIComponent(safeAttachmentName(filename))
    .replace(/['()]/g, (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
  return `${disposition}; filename="${fallback}"; filename*=UTF-8''${encoded}`;
}

export default {
  id: 'symbolika-mail',
  handler: (router, { database, env, logger }) => {
    let smtpTransport = null;

    router.get('/brand-logo.png', (req, res, next) => {
      res.set({
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=604800, immutable',
        'Cross-Origin-Resource-Policy': 'cross-origin',
      });
      createReadStream(BRAND_LOGO_FILE).on('error', next).pipe(res);
    });

    const mailMode = () => cleanText(env?.SYMBOLIKA_MAIL_MODE || 'mock', 20).toLowerCase();

    const actorContext = async (req, res) => {
      const userId = req.accountability?.user;
      if (!userId) {
        apiError(res, 401, 'Требуется авторизация.');
        return null;
      }
      const actor = await database('directus_users as u')
        .leftJoin('directus_roles as r', 'r.id', 'u.role')
        .leftJoin('employees as e', 'e.directus_user', 'u.id')
        .where('u.id', userId)
        .select(
          'u.id as user_id', 'u.email', 'u.first_name', 'u.last_name', 'u.avatar',
          'r.name as role_name', 'e.id as employee_id', 'e.full_name as employee_name',
          'e.email_signature', 'e.email_signature_settings', 'e.public_position', 'e.phone as employee_phone',
        )
        .first();
      if (!actor || !MAIL_ROLES.has(actor.role_name)) {
        apiError(res, 403, 'Почта доступна администраторам, управляющим и менеджерам.');
        return null;
      }
      actor.is_admin = ADMIN_ROLES.has(actor.role_name);
      actor.name = actor.employee_name
        || [actor.first_name, actor.last_name].filter(Boolean).join(' ')
        || actor.email;
      const mainSender = cleanText(env?.SYMBOLIKA_EMAIL_FROM || env?.SYMBOLIKA_SMTP_USER, 255).toLowerCase();
      const mainDomain = mainSender.includes('@') ? mainSender.split('@').pop() : '';
      const actorEmail = cleanText(actor.email, 255).toLowerCase();
      const employeeFolder = actor.employee_id
        ? await database('symbolika_mail_folders')
          .where('employee', actor.employee_id)
          .where('is_active', true)
          .whereNotNull('alias_email')
          .whereNot('alias_email', '')
          .orderBy('sort', 'asc')
          .first('alias_email')
        : null;
      const corporateActorEmail = EMAIL_PATTERN.test(actorEmail)
        && (!mainDomain || actorEmail.endsWith(`@${mainDomain}`))
        ? actorEmail
        : '';
      actor.sender_alias = cleanText(employeeFolder?.alias_email, 255).toLowerCase()
        || corporateActorEmail
        || mainSender
        || 'start@symb62.ru';
      return actor;
    };

    const applyFolderAccess = (query, actor, alias = 'f') => {
      if (actor.is_admin) return query;
      return query.where((builder) => {
        builder.where(`${alias}.is_shared`, true);
        if (actor.employee_id) builder.orWhere(`${alias}.employee`, actor.employee_id);
      });
    };

    const accessibleFolder = async (folderId, actor) => {
      let query = database('symbolika_mail_folders as f')
        .where('f.id', Number(folderId))
        .where('f.is_active', true)
        .select('f.*');
      query = applyFolderAccess(query, actor);
      return query.first();
    };

    const accessibleThread = async (threadId, actor) => {
      let query = database('symbolika_mail_threads as t')
        .join('symbolika_mail_folders as f', 'f.id', 't.folder_id')
        .where('t.id', Number(threadId))
        .select('t.*', 'f.name as folder_name', 'f.alias_email', 'f.employee as folder_employee');
      query = applyFolderAccess(query, actor);
      return query.first();
    };

    const folderRows = async (actor) => {
      let query = database('symbolika_mail_folders as f')
        .where('f.is_active', true)
        .select('f.*')
        .orderBy('f.sort', 'asc')
        .orderBy('f.name', 'asc');
      query = applyFolderAccess(query, actor);
      const folders = await query;
      const ids = folders.map((row) => row.id);
      const counts = ids.length
        ? await database('symbolika_mail_threads')
          .whereIn('folder_id', ids)
          .where('is_archived', false)
          .groupBy('folder_id')
          .select('folder_id')
          .count('* as total')
          .sum({ unread: database.raw('CASE WHEN is_unread THEN 1 ELSE 0 END') })
        : [];
      const byFolder = new Map(counts.map((row) => [Number(row.folder_id), row]));
      return folders.map((folder) => ({
        ...folder,
        total: Number(byFolder.get(Number(folder.id))?.total || 0),
        unread: Number(byFolder.get(Number(folder.id))?.unread || 0),
      }));
    };

    const threadQuery = (actor) => {
      let query = database('symbolika_mail_threads as t')
        .join('symbolika_mail_folders as f', 'f.id', 't.folder_id')
        .leftJoin('customers as c', 'c.id', 't.customer_id')
        .leftJoin('customer_companies as cc', 'cc.id', 't.company_id')
        .leftJoin('orders as o', 'o.id', 't.order_id')
        .leftJoin('symbolika_tasks as task', 'task.id', 't.task_id')
        .select(
          't.*', 'f.name as folder_name', 'f.alias_email',
          'c.name as customer_name', 'cc.name as company_name',
          'o.order_number', 'task.title as task_title',
        );
      return applyFolderAccess(query, actor);
    };

    const mailNotificationRecipients = async (folder) => {
      if (folder?.employee) {
        const owner = await database('employees').where('id', folder.employee).whereNotNull('directus_user').first('directus_user');
        return owner?.directus_user ? [owner.directus_user] : [];
      }
      if (!folder?.is_shared) return [];
      const users = await database('directus_users as u')
        .join('directus_roles as r', 'r.id', 'u.role')
        .where('u.status', 'active')
        .whereIn('r.name', [...MAIL_ROLES])
        .select('u.id');
      return users.map((row) => row.id);
    };

    const mailTopicEnabled = async (userId) => {
      const row = await database('symbolika_employee_notification_settings').where('user', userId).select('topics').first().catch(() => null);
      return row?.topics?.mail === true;
    };

    const notifyIncomingMail = async (folder, thread, from) => {
      const recipients = await mailNotificationRecipients(folder);
      for (const userId of recipients) {
        if (!await mailTopicEnabled(userId)) continue;
        await database('directus_notifications').insert({
          status: 'inbox',
          recipient: userId,
          subject: `Новое письмо: ${thread.subject || '(без темы)'}`,
          message: `От: ${from.name || from.email} <${from.email}>`,
          collection: 'symbolika_mail_threads',
          item: String(thread.id),
        });
      }
    };

    const smtpSender = () => {
      if (smtpTransport) return smtpTransport;
      const host = env?.SYMBOLIKA_SMTP_HOST || env?.EMAIL_SMTP_HOST;
      const port = Number(env?.SYMBOLIKA_SMTP_PORT || env?.EMAIL_SMTP_PORT || 465);
      const user = env?.SYMBOLIKA_SMTP_USER || env?.EMAIL_SMTP_USER;
      const pass = env?.SYMBOLIKA_SMTP_PASSWORD || env?.EMAIL_SMTP_PASSWORD;
      if (!host || !user || !pass) return null;
      smtpTransport = nodemailer.createTransport({
        host,
        port,
        secure: boolEnv(env?.SYMBOLIKA_SMTP_SECURE, port === 465),
        auth: { user, pass },
      });
      return smtpTransport;
    };

    const persistAttachments = async (parsed) => {
      const sourceAttachments = parsed.attachments || [];
      if (!sourceAttachments.length) return [];
      await mkdir(MAIL_ATTACHMENT_ROOT, { recursive: true });
      const saved = [];
      for (const item of sourceAttachments) {
        const content = Buffer.isBuffer(item.content) ? item.content : Buffer.from(item.content || '');
        const name = safeAttachmentName(item.filename || 'Вложение');
        const extension = path.extname(name).replace(/[^.A-Za-z0-9_-]/g, '').slice(0, 20);
        const storageName = `${randomUUID()}${extension}`;
        await writeFile(path.join(MAIL_ATTACHMENT_ROOT, storageName), content, { mode: 0o600 });
        saved.push({
          name,
          size: Number(item.size || content.length || 0),
          type: cleanText(item.contentType || 'application/octet-stream', 255),
          storage_name: storageName,
        });
      }
      return saved;
    };

    const upsertIncomingMessage = async (folder, parsed, actor) => {
      const from = addressList(parsed.from)[0] || { name: '', email: 'unknown@symb62.ru' };
      const to = addressList(parsed.to);
      const references = Array.isArray(parsed.references) ? parsed.references : (parsed.references ? [parsed.references] : []);
      const externalThreadId = cleanText(references[0] || parsed.inReplyTo || `${normalizeSubject(parsed.subject)}|${from.email}`, 500);
      const messageId = cleanText(parsed.messageId, 1000) || null;
      if (messageId) {
        const exists = await database('symbolika_mail_messages').where('message_id', messageId).first('id', 'attachments');
        if (exists) {
          const currentAttachments = jsonArray(exists.attachments);
          const needsFiles = (parsed.attachments || []).length > 0
            && (!currentAttachments.length || currentAttachments.some((item) => !item.storage_name));
          if (needsFiles) {
            const attachments = await persistAttachments(parsed);
            await database('symbolika_mail_messages').where('id', exists.id).update({ attachments: JSON.stringify(attachments) });
          }
          return false;
        }
      }

      const customer = await database('customers').whereRaw('lower(email) = lower(?)', [from.email]).first('id', 'company');
      const company = !customer
        ? await database('customer_companies').whereRaw('lower(email) = lower(?)', [from.email]).first('id')
        : null;
      const orderNumber = cleanText(parsed.subject, 2000).match(/SO-\d+/i)?.[0]?.toUpperCase() || '';
      const linkedOrder = orderNumber
        ? await database('orders').whereRaw('upper(order_number) = ?', [orderNumber]).first('id', 'customer', 'customer_company')
        : null;
      const sentAt = parsed.date || new Date();
      const preview = plainMailPreview(parsed.text || parsed.html || '', 240);
      const participants = [{ name: from.name, email: from.email }];
      const threadInsert = {
        folder_id: folder.id,
        external_thread_id: externalThreadId,
        subject: cleanText(parsed.subject || '(без темы)', 2000),
        preview,
        participants: JSON.stringify(participants),
        customer_id: customer?.id || linkedOrder?.customer || null,
        company_id: customer?.company || company?.id || linkedOrder?.customer_company || null,
        order_id: linkedOrder?.id || null,
        is_unread: true,
        last_message_at: sentAt,
        date_updated: new Date(),
      };
      const [thread] = await database('symbolika_mail_threads')
        .insert(threadInsert)
        .onConflict(['folder_id', 'external_thread_id'])
        .merge({
          subject: threadInsert.subject,
          preview,
          participants: threadInsert.participants,
          is_unread: true,
          last_message_at: sentAt,
          date_updated: new Date(),
        })
        .returning('*');

      const attachments = await persistAttachments(parsed);
      await database('symbolika_mail_messages').insert({
        thread_id: thread.id,
        message_id: messageId,
        in_reply_to: cleanText(parsed.inReplyTo, 1000) || null,
        direction: from.email.endsWith('@symb62.ru') ? 'outbound' : 'inbound',
        from_email: from.email,
        from_name: from.name || null,
        to_emails: JSON.stringify(to.map((row) => row.email)),
        cc_emails: JSON.stringify(addressList(parsed.cc).map((row) => row.email)),
        sender_alias: from.email.endsWith('@symb62.ru') ? from.email : null,
        subject: threadInsert.subject,
        body_text: cleanText(parsed.text || '', 200000),
        body_html: cleanText(parsed.html || '', 500000),
        attachments: JSON.stringify(attachments),
        is_read: from.email.endsWith('@symb62.ru'),
        is_test: false,
        author_user: actor?.user_id || null,
        sent_at: sentAt,
      }).onConflict('message_id').ignore();
      await notifyIncomingMail(folder, thread, from);
      return true;
    };

    router.get('/bootstrap', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const folders = await folderRows(actor);
        const requestedFolder = Number(req.query?.folder || 0);
        const scope = cleanText(req.query?.scope, 30);
        const starredScope = scope === 'starred';
        const selected = folders.find((row) => Number(row.id) === requestedFolder) || folders[0] || null;
        const limit = Math.min(Math.max(Number(req.query?.limit || 50), 1), 100);
        const search = cleanText(req.query?.search, 200);
        let query = threadQuery(actor).where('t.is_archived', false);
        if (starredScope) query = query.where('t.is_starred', true);
        else if (selected) query = query.where('t.folder_id', selected.id);
        if (search) {
          query = query.where((builder) => builder
            .whereILike('t.subject', `%${search}%`)
            .orWhereILike('t.preview', `%${search}%`)
            .orWhereRaw("t.participants::text ILIKE ?", [`%${search}%`])
            .orWhereExists(function messageTextSearch() {
              this.select(database.raw('1'))
                .from('symbolika_mail_messages as smm')
                .whereRaw('smm.thread_id = t.id')
                .whereILike('smm.body_text', `%${search}%`);
            }));
        }
        const threads = await query.orderBy('t.last_message_at', 'desc').limit(limit);
        let starredCountQuery = database('symbolika_mail_threads as t')
          .join('symbolika_mail_folders as f', 'f.id', 't.folder_id')
          .where('t.is_archived', false)
          .where('t.is_starred', true);
        starredCountQuery = applyFolderAccess(starredCountQuery, actor);
        const starredCountRow = await starredCountQuery.count('t.id as count').first();
        return res.json({
          data: {
            actor: {
              id: actor.user_id,
              employee_id: actor.employee_id,
              name: actor.name,
              email: actor.email,
              sender_alias: actor.sender_alias,
              role: actor.role_name,
              is_admin: actor.is_admin,
              signature: brandedSignatureHtml(actor, actor.email),
              signature_custom: sanitizeSignatureHtml(actor.email_signature),
              signature_settings: signatureSettings(actor, actor.email),
              signature_defaults: signatureDefaults(actor, actor.email),
            },
            mode: mailMode(),
            configured: Boolean(env?.SYMBOLIKA_IMAP_HOST && env?.SYMBOLIKA_IMAP_USER && env?.SYMBOLIKA_IMAP_PASSWORD),
            folders,
            selected_folder: starredScope ? null : (selected?.id || null),
            scope: starredScope ? 'starred' : 'folder',
            starred_count: Number(starredCountRow?.count || 0),
            threads: threads.map((row) => ({
              ...row,
              preview: plainMailPreview(row.preview, 240),
              participants: jsonArray(row.participants),
              tags: jsonArray(row.tags),
            })),
          },
        });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/threads/:id', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const thread = await accessibleThread(req.params.id, actor);
        if (!thread) return apiError(res, 404, 'Переписка не найдена или недоступна.');
        const linked = await threadQuery(actor).where('t.id', thread.id).first();
        const messages = await database('symbolika_mail_messages')
          .where('thread_id', thread.id)
          .orderBy('sent_at', 'asc')
          .select('*');
        await database('symbolika_mail_threads').where('id', thread.id).update({ is_unread: false, date_updated: new Date() });
        await database('symbolika_mail_messages').where('thread_id', thread.id).update({ is_read: true });
        return res.json({
          data: {
            thread: { ...linked, participants: jsonArray(linked.participants), tags: jsonArray(linked.tags) },
            messages: messages.map((row) => ({
              ...row,
              to_emails: jsonArray(row.to_emails),
              cc_emails: jsonArray(row.cc_emails),
              attachments: jsonArray(row.attachments),
            })),
          },
        });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/messages/:messageId/attachments/:attachmentIndex', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const messageId = Number(req.params.messageId);
        const attachmentIndex = Number(req.params.attachmentIndex);
        if (!Number.isInteger(messageId) || !Number.isInteger(attachmentIndex) || attachmentIndex < 0) {
          return apiError(res, 400, 'Некорректная ссылка на вложение.');
        }
        const message = await database('symbolika_mail_messages').where('id', messageId).first('id', 'thread_id', 'attachments');
        if (!message || !await accessibleThread(message.thread_id, actor)) {
          return apiError(res, 404, 'Вложение не найдено или недоступно.');
        }
        const attachment = jsonArray(message.attachments)[attachmentIndex];
        const storageName = cleanText(attachment?.storage_name, 255);
        if (!attachment || !/^[A-Za-z0-9._-]+$/.test(storageName)) {
          return apiError(res, 404, 'Файл ещё не загружен. Обновите почту и повторите попытку.');
        }
        const filePath = path.join(MAIL_ATTACHMENT_ROOT, storageName);
        const resolvedRoot = path.resolve(MAIL_ATTACHMENT_ROOT) + path.sep;
        if (!path.resolve(filePath).startsWith(resolvedRoot)) return apiError(res, 400, 'Некорректный путь вложения.');
        const fileStat = await stat(filePath).catch(() => null);
        if (!fileStat?.isFile()) return apiError(res, 404, 'Файл вложения отсутствует. Обновите почту.');
        const contentType = cleanText(attachment.type, 255) || 'application/octet-stream';
        const inlineTypes = new Set(['application/pdf', 'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'text/plain']);
        const disposition = req.query?.download === '1' || !inlineTypes.has(contentType.toLowerCase()) ? 'attachment' : 'inline';
        res.setHeader('Content-Type', contentType);
        res.setHeader('Content-Length', String(fileStat.size));
        res.setHeader('Content-Disposition', contentDisposition(disposition, attachment.name));
        res.setHeader('X-Content-Type-Options', 'nosniff');
        return createReadStream(filePath).on('error', next).pipe(res);
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/threads/:id', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const thread = await accessibleThread(req.params.id, actor);
        if (!thread) return apiError(res, 404, 'Переписка не найдена или недоступна.');
        const update = { date_updated: new Date() };
        if (!actor.is_admin) {
          const customerId = Number(req.body?.customer_id || 0);
          const companyId = Number(req.body?.company_id || 0);
          const orderId = Number(req.body?.order_id || 0);
          if (customerId && !await database('customers').where({ id: customerId, manager: actor.employee_id }).first('id')) {
            return apiError(res, 403, 'Этот клиент не закреплен за текущим сотрудником.');
          }
          if (companyId && !await database('customer_companies').where({ id: companyId, manager: actor.employee_id }).first('id')) {
            return apiError(res, 403, 'Эта компания не закреплена за текущим сотрудником.');
          }
          if (orderId && !await database('orders').where({ id: orderId, manager_employee: actor.employee_id }).first('id')) {
            return apiError(res, 403, 'Этот заказ не закреплен за текущим сотрудником.');
          }
        }
        for (const field of ['is_unread', 'is_starred', 'is_archived']) {
          if (Object.prototype.hasOwnProperty.call(req.body || {}, field)) update[field] = Boolean(req.body[field]);
        }
        for (const field of ['customer_id', 'company_id', 'order_id', 'task_id']) {
          if (Object.prototype.hasOwnProperty.call(req.body || {}, field)) {
            const value = Number(req.body[field] || 0);
            update[field] = value || null;
          }
        }
        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'tags')) {
          update.tags = JSON.stringify(jsonArray(req.body.tags)
            .map((value) => cleanText(value, 60))
            .filter(Boolean)
            .slice(0, 20));
        }
        if (Object.prototype.hasOwnProperty.call(req.body || {}, 'folder_id')) {
          const folder = await accessibleFolder(req.body.folder_id, actor);
          if (!folder) return apiError(res, 400, 'Выберите доступную папку.');
          update.folder_id = folder.id;
          update.is_archived = false;
        }
        if (update.is_archived === true) {
          let archiveQuery = database('symbolika_mail_folders as f')
            .where('f.slug', 'archive')
            .where('f.is_active', true)
            .select('f.id');
          archiveQuery = applyFolderAccess(archiveQuery, actor);
          const archiveFolder = await archiveQuery.first();
          if (archiveFolder) {
            update.folder_id = archiveFolder.id;
            update.is_archived = false;
          }
        }
        await database('symbolika_mail_threads').where('id', thread.id).update(update);
        return res.json({ data: { id: thread.id, ...update } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/send', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const to = cleanText(req.body?.to, 2000).split(/[;,]/).map((value) => value.trim().toLowerCase()).filter(Boolean);
        if (!to.length || to.some((email) => !EMAIL_PATTERN.test(email))) return apiError(res, 400, 'Укажите корректный адрес получателя.');
        const subject = cleanText(req.body?.subject || '(без темы)', 2000);
        const body = cleanText(req.body?.body, 200000);
        if (!body) return apiError(res, 400, 'Введите текст письма.');

        const replyThread = req.body?.thread_id ? await accessibleThread(req.body.thread_id, actor) : null;
        const requestedFolderId = Number(req.body?.folder_id || replyThread?.folder_id || 0);
        const folder = await accessibleFolder(requestedFolderId, actor);
        if (!folder) return apiError(res, 400, 'Выберите доступную почтовую папку.');
        const fromAlias = cleanText(req.body?.from_alias || actor.sender_alias || folder.alias_email || env?.SYMBOLIKA_EMAIL_FROM || env?.SYMBOLIKA_SMTP_USER, 255).toLowerCase();
        if (!EMAIL_PATTERN.test(fromAlias)) return apiError(res, 400, 'Для папки не настроен адрес отправителя.');
        const configuredAliases = cleanText(env?.SYMBOLIKA_MAIL_ALLOWED_ALIASES, 10000)
          .split(/[;,]/).map((value) => value.trim().toLowerCase()).filter(Boolean);
        const allowedAliases = new Set([
          cleanText(folder.alias_email, 255).toLowerCase(),
          cleanText(actor.sender_alias, 255).toLowerCase(),
          cleanText(env?.SYMBOLIKA_EMAIL_FROM || env?.SYMBOLIKA_SMTP_USER, 255).toLowerCase(),
          ...configuredAliases,
        ].filter(Boolean));
        if (!allowedAliases.has(fromAlias)) {
          return apiError(res, 403, 'Этот псевдоним не назначен выбранной почтовой папке.');
        }
        const signatureHtml = req.body?.include_signature === false ? '' : brandedSignatureHtml(actor, fromAlias);
        const signatureText = signaturePlainText(signatureHtml);
        const deliveredBody = signatureText ? `${body}\n\n-- \n${signatureText}` : body;
        const deliveredHtml = `${escapeHtml(body).replace(/\r?\n/g, '<br>')}${signatureHtml ? `<div style="margin-top:24px">${signatureHtml}</div>` : ''}`;

        let messageId = `<mock-${Date.now()}-${Math.random().toString(16).slice(2)}@symb62.ru>`;
        let delivered = false;
        if (mailMode() === 'imap') {
          const transport = smtpSender();
          if (!transport) return apiError(res, 503, 'SMTP не настроен. Проверьте серверные переменные почты.');
          const result = await transport.sendMail({
            from: { name: actor.name, address: fromAlias },
            replyTo: fromAlias,
            to,
            subject,
            text: deliveredBody,
            html: deliveredHtml,
            inReplyTo: replyThread?.external_thread_id?.startsWith('<') ? replyThread.external_thread_id : undefined,
          });
          messageId = result?.messageId || messageId;
          delivered = true;
        }

        let threadId = replyThread?.id;
        if (!threadId) {
          const [created] = await database('symbolika_mail_threads').insert({
            folder_id: folder.id,
            external_thread_id: messageId,
            subject,
            preview: deliveredBody.slice(0, 240),
            participants: JSON.stringify(to.map((email) => ({ name: '', email }))),
            customer_id: Number(req.body?.customer_id || 0) || null,
            company_id: Number(req.body?.company_id || 0) || null,
            order_id: Number(req.body?.order_id || 0) || null,
            task_id: Number(req.body?.task_id || 0) || null,
            is_unread: false,
            last_message_at: new Date(),
          }).returning('*');
          threadId = created.id;
        } else {
          await database('symbolika_mail_threads').where('id', threadId).update({
            preview: deliveredBody.slice(0, 240),
            is_unread: false,
            last_message_at: new Date(),
            date_updated: new Date(),
          });
        }
        await database('symbolika_mail_messages').insert({
          thread_id: threadId,
          message_id: messageId,
          direction: 'outbound',
          from_email: fromAlias,
          from_name: actor.name,
          to_emails: JSON.stringify(to),
          cc_emails: '[]',
          sender_alias: fromAlias,
          subject,
          body_text: deliveredBody,
          body_html: deliveredHtml,
          attachments: '[]',
          is_read: true,
          is_test: mailMode() !== 'imap',
          author_user: actor.user_id,
          sent_at: new Date(),
        });
        return res.json({ data: { thread_id: threadId, message_id: messageId, delivered, mode: mailMode() } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/sync', async (req, res, next) => {
      let client;
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (mailMode() !== 'imap') return res.json({ data: { mode: 'mock', synced: 0, message: 'Демо-режим: тестовые письма уже загружены.' } });
        const host = env?.SYMBOLIKA_IMAP_HOST;
        const user = env?.SYMBOLIKA_IMAP_USER;
        const pass = env?.SYMBOLIKA_IMAP_PASSWORD;
        const port = Number(env?.SYMBOLIKA_IMAP_PORT || 993);
        if (!host || !user || !pass) return apiError(res, 503, 'IMAP не настроен.');
        client = new ImapFlow({
          host,
          port,
          secure: boolEnv(env?.SYMBOLIKA_IMAP_SECURE, port === 993),
          auth: { user, pass },
          logger: false,
        });
        await client.connect();
        const folders = (await folderRows(actor)).filter((folder) => folder.imap_name);
        let synced = 0;
        const perFolder = Math.min(Math.max(Number(req.body?.limit || 60), 1), 200);
        for (const folder of folders) {
          let lock;
          try {
            lock = await client.getMailboxLock(folder.imap_name);
            const total = Number(client.mailbox?.exists || 0);
            if (!total) continue;
            const range = `${Math.max(1, total - perFolder + 1)}:*`;
            for await (const message of client.fetch(range, { source: true, uid: true, internalDate: true })) {
              const parsed = await simpleParser(message.source);
              if (!parsed.date && message.internalDate) parsed.date = message.internalDate;
              if (await upsertIncomingMessage(folder, parsed, actor)) synced += 1;
            }
          } catch (error) {
            logger.warn({ folder: folder.imap_name, error: error?.message }, '[Symbolika Mail] folder sync failed');
          } finally {
            lock?.release?.();
          }
        }
        await client.logout();
        return res.json({ data: { mode: 'imap', synced } });
      } catch (error) {
        try { await client?.logout?.(); } catch { /* connection already closed */ }
        return next(error);
      }
    });

    router.get('/options', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        let customerOptions = database('customers').select('id', 'name', 'email', 'company').orderBy('name').limit(500);
        let companyOptions = database('customer_companies').select('id', 'name', 'email').orderBy('name').limit(500);
        let orderOptions = database('orders as o')
          .leftJoin('customers as c', 'c.id', 'o.customer')
          .leftJoin('customer_companies as cc', 'cc.id', 'o.customer_company')
          .select('o.id', 'o.order_number', 'o.customer', 'o.customer_company', 'c.name as customer_name', 'cc.name as company_name')
          .orderBy('o.date', 'desc').limit(500);
        if (!actor.is_admin) {
          customerOptions = actor.employee_id ? customerOptions.where('manager', actor.employee_id) : customerOptions.whereRaw('false');
          companyOptions = actor.employee_id ? companyOptions.where('manager', actor.employee_id) : companyOptions.whereRaw('false');
          orderOptions = actor.employee_id ? orderOptions.where('o.manager_employee', actor.employee_id) : orderOptions.whereRaw('false');
        }
        const [customers, companies, orders, employees] = await Promise.all([
          customerOptions,
          companyOptions,
          orderOptions,
          database('employees').where('is_active', true).select('id', 'full_name').orderBy('full_name'),
        ]);
        return res.json({ data: { customers, companies, orders, employees, folders: await folderRows(actor) } });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/signature', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        return res.json({ data: {
          signature: brandedSignatureHtml(actor, actor.email),
          signature_custom: sanitizeSignatureHtml(actor.email_signature),
          signature_settings: signatureSettings(actor, actor.email),
          signature_defaults: signatureDefaults(actor, actor.email),
        } });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/signature', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.employee_id) return apiError(res, 400, 'У пользователя не заполнена карточка сотрудника.');
        const signature = sanitizeSignatureHtml(req.body?.signature) || null;
        const settings = signatureSettings(actor, actor.email, req.body?.settings);
        await database('employees').where('id', actor.employee_id).update({
          email_signature: signature,
          email_signature_settings: JSON.stringify(settings),
        });
        actor.email_signature = signature;
        actor.email_signature_settings = settings;
        return res.json({ data: {
          signature: signature || '',
          signature_html: brandedSignatureHtml(actor, actor.email),
          signature_settings: settings,
          signature_defaults: signatureDefaults(actor, actor.email),
        } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/threads/:id/task', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const thread = await accessibleThread(req.params.id, actor);
        if (!thread) return apiError(res, 404, 'Переписка не найдена или недоступна.');
        const title = cleanText(req.body?.title || `Письмо: ${thread.subject}`, 500);
        const assignedTo = Number(req.body?.assigned_to || 0) || actor.employee_id || null;
        const description = cleanText(req.body?.description, 10000)
          || `Обработать письмо «${thread.subject}» от ${jsonArray(thread.participants)[0]?.email || 'неизвестного отправителя'}.`;
        const [task] = await database('symbolika_tasks').insert({
          title,
          description,
          status: 'new',
          priority: cleanText(req.body?.priority, 32) || 'normal',
          due_date: cleanText(req.body?.due_date, 20) || null,
          assigned_to: assignedTo,
          created_by_employee: actor.employee_id || null,
          related_order: thread.order_id || null,
          related_customer: thread.customer_id || null,
          related_company: thread.company_id || null,
          task_type: 'general',
          result_url: `/admin/symbolika-mail-module?thread=${thread.id}`,
        }).returning('*');
        await database('symbolika_mail_threads').where('id', thread.id).update({ task_id: task.id, date_updated: new Date() });
        return res.json({ data: { task } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/threads/:id/payment-tasks', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        const thread = await accessibleThread(req.params.id, actor);
        if (!thread) return apiError(res, 404, 'Переписка не найдена или недоступна.');
        const existing = await database('symbolika_mail_payment_tasks').where('thread_id', thread.id).first();
        if (existing) return apiError(res, 409, 'Задачи на оплату по этому письму уже созданы.');
        const recipients = await database('employees as e')
          .join('directus_users as u', 'u.id', 'e.directus_user')
          .join('directus_roles as r', 'r.id', 'u.role')
          .where('e.is_active', true)
          .whereIn('r.name', [...ADMIN_ROLES])
          .select('e.id', 'e.full_name');
        if (!recipients.length) return apiError(res, 400, 'Не найдены активные администраторы или управляющие.');
        const latestMessage = await database('symbolika_mail_messages').where('thread_id', thread.id).orderBy('sent_at', 'desc').first();
        const files = jsonArray(latestMessage?.attachments).map((file) => file.name).filter(Boolean);
        const comment = cleanText(req.body?.comment, 5000);
        const description = [
          `Оплатить счет из письма «${thread.subject}».`,
          files.length ? `Вложения: ${files.join(', ')}.` : 'Вложения в письме не найдены.',
          comment,
        ].filter(Boolean).join('\n');
        const created = [];
        for (const recipient of recipients) {
          const [task] = await database('symbolika_tasks').insert({
            title: cleanText(`Оплатить счет: ${thread.subject}`, 500),
            description,
            status: 'new',
            priority: 'important',
            due_date: cleanText(req.body?.due_date, 20) || null,
            assigned_to: recipient.id,
            created_by_employee: actor.employee_id || null,
            related_order: thread.order_id || null,
            related_customer: thread.customer_id || null,
            related_company: thread.company_id || null,
            task_type: 'general',
            result_url: `/admin/symbolika-mail-module?thread=${thread.id}`,
          }).returning('*');
          await database('symbolika_mail_payment_tasks').insert({ thread_id: thread.id, task_id: task.id });
          created.push(task);
        }
        await database('symbolika_mail_threads').where('id', thread.id).update({ task_id: created[0].id, date_updated: new Date() });
        return res.json({ data: { tasks: created } });
      } catch (error) {
        return next(error);
      }
    });

    router.get('/settings', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Настройки почты доступны только администратору и управляющему.');
        const employees = await database('employees as e')
          .leftJoin('directus_users as u', 'u.id', 'e.directus_user')
          .where('e.is_active', true)
          .select('e.id', 'e.full_name', 'e.email_signature', 'e.email_signature_settings', 'e.public_position', 'e.phone', 'u.email')
          .orderBy('e.full_name');
        employees.forEach((employee) => {
          employee.email_signature = sanitizeSignatureHtml(employee.email_signature);
          employee.signature_settings = signatureSettings(employee, employee.email);
          employee.signature_defaults = signatureDefaults(employee, employee.email);
          employee.signature_preview = brandedSignatureHtml(employee, employee.email);
        });
        return res.json({
          data: {
            folders: await folderRows(actor),
            employees,
            connection: {
              mode: mailMode(),
              imap_host: env?.SYMBOLIKA_IMAP_HOST || '',
              imap_port: Number(env?.SYMBOLIKA_IMAP_PORT || 993),
              smtp_host: env?.SYMBOLIKA_SMTP_HOST || '',
              smtp_port: Number(env?.SYMBOLIKA_SMTP_PORT || 465),
              user: env?.SYMBOLIKA_IMAP_USER || env?.SYMBOLIKA_SMTP_USER || '',
              password_configured: Boolean(env?.SYMBOLIKA_IMAP_PASSWORD || env?.SYMBOLIKA_SMTP_PASSWORD),
            },
          },
        });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/folders/:id', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Изменять почтовые папки может только администратор или управляющий.');
        const current = await database('symbolika_mail_folders').where('id', Number(req.params.id)).first();
        if (!current) return apiError(res, 404, 'Папка не найдена.');
        const update = { date_updated: new Date() };
        if ('name' in (req.body || {})) update.name = cleanText(req.body.name, 255) || current.name;
        if ('imap_name' in (req.body || {})) update.imap_name = cleanText(req.body.imap_name, 500) || null;
        if ('alias_email' in (req.body || {})) {
          const value = cleanText(req.body.alias_email, 255).toLowerCase();
          if (value && !EMAIL_PATTERN.test(value)) return apiError(res, 400, 'Некорректный адрес псевдонима.');
          update.alias_email = value || null;
        }
        if ('employee' in (req.body || {})) update.employee = Number(req.body.employee || 0) || null;
        if ('is_shared' in (req.body || {})) update.is_shared = Boolean(req.body.is_shared);
        if ('is_active' in (req.body || {})) update.is_active = Boolean(req.body.is_active);
        await database('symbolika_mail_folders').where('id', current.id).update(update);
        return res.json({ data: { id: current.id, ...update } });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/folders', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Создавать почтовые папки может только администратор или управляющий.');
        const name = cleanText(req.body?.name, 255);
        if (!name) return apiError(res, 400, 'Укажите название папки.');
        const aliasEmail = cleanText(req.body?.alias_email, 255).toLowerCase();
        if (aliasEmail && !EMAIL_PATTERN.test(aliasEmail)) return apiError(res, 400, 'Некорректный адрес псевдонима.');
        const baseSlug = cleanText(name, 120).toLowerCase()
          .replace(/[^a-zа-яё0-9]+/gi, '-')
          .replace(/^-+|-+$/g, '') || 'folder';
        let slug = baseSlug;
        let suffix = 2;
        while (await database('symbolika_mail_folders').where('slug', slug).first('id')) slug = `${baseSlug}-${suffix++}`;
        const maxSort = await database('symbolika_mail_folders').max('sort as value').first();
        const [created] = await database('symbolika_mail_folders').insert({
          slug,
          name,
          imap_name: cleanText(req.body?.imap_name, 500) || null,
          alias_email: aliasEmail || null,
          employee: Number(req.body?.employee || 0) || null,
          is_shared: Boolean(req.body?.is_shared),
          is_system: false,
          is_active: true,
          sort: Number(maxSort?.value || 100) + 10,
          date_created: new Date(),
          date_updated: new Date(),
        }).returning('*');
        return res.status(201).json({ data: created });
      } catch (error) {
        return next(error);
      }
    });

    router.patch('/employees/:id/signature', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Подписи сотрудников может настраивать только администратор или управляющий.');
        const employeeId = Number(req.params.id);
        if (!Number.isInteger(employeeId) || employeeId <= 0) return apiError(res, 400, 'Некорректный идентификатор сотрудника.');
        const employee = await database('employees as e')
          .leftJoin('directus_users as u', 'u.id', 'e.directus_user')
          .where('e.id', employeeId)
          .first('e.id', 'e.full_name', 'e.email_signature_settings', 'e.public_position', 'e.phone', 'u.email');
        if (!employee) return apiError(res, 404, 'Сотрудник не найден.');
        const signature = sanitizeSignatureHtml(req.body?.signature) || null;
        const settings = signatureSettings(employee, employee.email, req.body?.settings);
        await database('employees').where('id', employee.id).update({
          email_signature: signature,
          email_signature_settings: JSON.stringify(settings),
        });
        employee.email_signature = signature;
        employee.email_signature_settings = settings;
        return res.json({ data: {
          id: employee.id,
          signature: signature || '',
          signature_html: brandedSignatureHtml(employee, employee.email),
          signature_settings: settings,
          signature_defaults: signatureDefaults(employee, employee.email),
        } });
      } catch (error) {
        return next(error);
      }
    });
  },
};

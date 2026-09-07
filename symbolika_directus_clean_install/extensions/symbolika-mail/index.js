import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';
import nodemailer from 'nodemailer';
import Busboy from 'busboy';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ADMIN_ROLES = new Set(['Administrator', 'Управляющий']);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/i;
const MAIL_ATTACHMENT_ROOT = '/directus/uploads/symbolika-mail';
const BRAND_LOGO_FILE = fileURLToPath(new URL('./assets/symbolika-logo.png', import.meta.url));
const BRAND_LOGO_URL = 'https://symbcorp.ru/symbolika-mail/brand-logo.png';
const SIGNATURE_ICON_BASE_URL = 'https://symbcorp.ru/symbolika-mail/signature-icon';
const LEGACY_BRAND_LOGO_URL = 'https://static.tildacdn.com/tild6465-3739-4736-b565-653037393965/2.png';
const BACKGROUND_SYNC_STATE_KEY = Symbol.for('symbolika.mail.background-sync');
const DEFAULT_ATTACHMENT_MAX_FILES = 10;
const DEFAULT_ATTACHMENT_MAX_FILE_BYTES = 15 * 1024 * 1024;
const DEFAULT_ATTACHMENT_MAX_TOTAL_BYTES = 20 * 1024 * 1024;

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
  map_url: 'https://yandex.ru/maps/-/CTsI7Q5l',
  vk_label: 'vk.com/universymbols',
  vk_url: 'https://vk.com/universymbols',
  slogan_line_1: 'Воплощаем ваши идеи в жизнь.',
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
    website_label: defaults.website_label, website_url: defaults.website_url,
    address: defaults.address, map_url: defaults.map_url,
    vk_label: defaults.vk_label, vk_url: defaults.vk_url,
    slogan_line_1: defaults.slogan_line_1, slogan_line_2: defaults.slogan_line_2,
    logo_url: defaults.logo_url,
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
  const phoneLink = settings.phone.replace(/[^+\d]/g, '');
  const contactRow = (icon, content, href = '') => content ? `<tr><td width="24" style="width:24px;padding:4px 6px 4px 0;vertical-align:middle"><img src="${SIGNATURE_ICON_BASE_URL}/${icon}.svg?v=2" width="20" height="20" alt="" style="display:block;width:20px;height:20px;border:0"></td><td style="padding:4px 0;border-bottom:1px solid #46515e;color:#f5f7fa;font-size:12px;line-height:16px;word-break:break-word">${href ? `<a href="${escapeHtml(href)}" style="color:#f5f7fa;text-decoration:none">${escapeHtml(content)}</a>` : escapeHtml(content)}</td></tr>` : '';
  const custom = sanitizeSignatureHtml(employee?.email_signature);
  return `<style>@media only screen and (max-width:560px){.symb-signature .symb-brand{width:24%!important;padding:10px!important}.symb-signature .symb-person{width:31%!important;padding:10px 11px!important}.symb-signature .symb-contacts{width:45%!important;padding:8px 10px!important}.symb-signature .symb-name{font-size:16px!important;line-height:18px!important}.symb-signature .symb-slogan{font-size:9px!important;line-height:12px!important}}</style><table role="presentation" class="symb-signature" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;max-width:100%;margin-top:14px;border:1px solid #39434f;border-radius:12px;background:#171c22;color:#f5f7fa;font-family:Arial,sans-serif;table-layout:fixed"><tr>
<td class="symb-brand" width="24%" style="width:24%;padding:14px;vertical-align:middle;text-align:center"><img src="${escapeHtml(BRAND_LOGO_URL)}" width="150" alt="Символика" style="display:block;width:100%;max-width:150px;height:auto;margin:0 auto;border:0"></td>
<td class="symb-person" width="32%" style="width:32%;padding:14px 18px;border-left:2px solid #f97316;vertical-align:middle"><div class="symb-name" style="color:#f5f7fa;font-size:19px;font-weight:800;line-height:22px;word-break:break-word">${escapeHtml(settings.full_name)}</div><div style="margin-top:4px;color:#f97316;font-size:10px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;word-break:break-word">${escapeHtml(settings.position)}</div><div style="width:32px;height:2px;margin:9px 0;background:#f97316"></div><div class="symb-slogan" style="color:#c3c9d1;font-size:10px;font-style:italic;line-height:14px">${escapeHtml(settings.slogan_line_1)}<br>${escapeHtml(settings.slogan_line_2)}</div></td>
<td class="symb-contacts" width="44%" style="width:44%;padding:10px 16px;vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%">${contactRow('phone', settings.phone, phoneLink ? `tel:${phoneLink}` : '')}${contactRow('mail', settings.email, settings.email ? `mailto:${settings.email}` : '')}${contactRow('website', settings.website_label, settings.website_url)}${contactRow('location', settings.address, settings.map_url)}${contactRow('vk', settings.vk_label, settings.vk_url)}</table></td>
</tr></table>${custom ? `<div style="width:100%;margin-top:8px;font-family:Arial,sans-serif;font-size:11px;color:#66717f">${custom}</div>` : ''}`;
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
    const attachmentLimits = () => ({
      files: Math.min(Math.max(Number(env?.SYMBOLIKA_MAIL_ATTACHMENT_MAX_FILES || DEFAULT_ATTACHMENT_MAX_FILES), 1), 30),
      fileBytes: Math.min(Math.max(Number(env?.SYMBOLIKA_MAIL_ATTACHMENT_MAX_FILE_MB || (DEFAULT_ATTACHMENT_MAX_FILE_BYTES / 1024 / 1024)), 1), 50) * 1024 * 1024,
      totalBytes: Math.min(Math.max(Number(env?.SYMBOLIKA_MAIL_ATTACHMENT_MAX_TOTAL_MB || (DEFAULT_ATTACHMENT_MAX_TOTAL_BYTES / 1024 / 1024)), 1), 75) * 1024 * 1024,
    });

    const outgoingPayload = (req) => {
      if (!String(req.headers?.['content-type'] || '').toLowerCase().startsWith('multipart/form-data')) {
        return Promise.resolve({ fields: req.body || {}, attachments: [] });
      }
      const limits = attachmentLimits();
      return new Promise((resolve, reject) => {
        const fields = {};
        const attachments = [];
        let totalBytes = 0;
        let failed = null;
        let parser;
        try {
          parser = Busboy({
            headers: req.headers,
            limits: { files: limits.files, fileSize: limits.fileBytes, fields: 80, fieldSize: 250000 },
          });
        } catch (error) {
          reject(error);
          return;
        }
        parser.on('field', (name, value) => {
          fields[name] = value;
        });
        parser.on('file', (name, stream, info = {}) => {
          if (name !== 'attachments') {
            stream.resume();
            return;
          }
          const chunks = [];
          let fileBytes = 0;
          stream.on('data', (chunk) => {
            fileBytes += chunk.length;
            totalBytes += chunk.length;
            if (totalBytes > limits.totalBytes) {
              failed ||= new Error(`Общий размер вложений не должен превышать ${Math.round(limits.totalBytes / 1024 / 1024)} МБ.`);
              return;
            }
            chunks.push(chunk);
          });
          stream.on('limit', () => {
            failed ||= new Error(`Размер одного вложения не должен превышать ${Math.round(limits.fileBytes / 1024 / 1024)} МБ.`);
          });
          stream.on('end', () => {
            if (failed || !fileBytes) return;
            attachments.push({
              filename: safeAttachmentName(info.filename || 'Вложение'),
              contentType: cleanText(info.mimeType || 'application/octet-stream', 255),
              size: fileBytes,
              content: Buffer.concat(chunks, fileBytes),
            });
          });
        });
        parser.on('filesLimit', () => {
          failed ||= new Error(`К одному письму можно прикрепить не более ${limits.files} файлов.`);
        });
        parser.on('error', reject);
        parser.on('finish', () => {
          if (failed) reject(failed);
          else resolve({ fields, attachments });
        });
        req.pipe(parser);
      });
    };

    router.get('/brand-logo.png', (req, res, next) => {
      res.set({
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=604800, immutable',
        'Cross-Origin-Resource-Policy': 'cross-origin',
      });
      createReadStream(BRAND_LOGO_FILE).on('error', next).pipe(res);
    });

    router.get('/signature-icon/:name.svg', (req, res) => {
      const icons = {
        phone: '<path d="M7.2 3.5 5.3 5.4c-.6.6-.7 1.5-.3 2.3 2.2 4.4 5.8 8 10.2 10.2.8.4 1.7.3 2.3-.3l1.9-1.9-3.8-2.5-1.5 1.5c-2.1-1.2-3.8-2.9-5-5l1.5-1.5-2.4-3.7Z" fill="none" stroke="#f97316" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
        mail: '<path d="M5 7h14v10H5V7Zm.7.8 6.3 5 6.3-5" fill="none" stroke="#f97316" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
        website: '<circle cx="12" cy="12" r="7" fill="none" stroke="#f97316" stroke-width="1.8"/><path d="M5.5 12h13M12 5c2.5 2.3 2.5 11.7 0 14M12 5c-2.5 2.3-2.5 11.7 0 14" fill="none" stroke="#f97316" stroke-width="1.6"/>',
        location: '<path d="M12 20s6-5.4 6-11a6 6 0 1 0-12 0c0 5.6 6 11 6 11Z" fill="none" stroke="#f97316" stroke-width="1.9"/><circle cx="12" cy="9" r="2" fill="#f97316"/>',
        vk: '<path d="M7.1 8.2h2.2c.2 2.5 1.2 3.6 2 3.8V8.2h2.1v2.2c1.9-.2 3-2 3-2h2.1s-.6 2.3-2.3 3.5c1.8.9 2.8 3 2.8 3h-2.4s-1.2-2.1-3.2-2.2v2.2h-.3c-4.5 0-5.7-3.1-6-6.7Z" fill="#f97316"/>',
      };
      const name = cleanText(req.params.name, 30);
      if (!icons[name]) return res.status(404).end();
      res.set({
        'Content-Type': 'image/svg+xml; charset=utf-8',
        'Cache-Control': 'public, max-age=604800, immutable',
        'Cross-Origin-Resource-Policy': 'cross-origin',
      });
      return res.send(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">${icons[name]}</svg>`);
    });

    const mailMode = () => cleanText(env?.SYMBOLIKA_MAIL_MODE || 'mock', 20).toLowerCase();

    const credentialKey = () => {
      const secret = String(env?.SECRET || '');
      if (!secret) throw new Error('Для безопасного сохранения паролей почты не настроен SECRET Directus.');
      return createHash('sha256').update(`symbolika-mail-accounts:v1:${secret}`).digest();
    };

    const encryptCredential = (value) => {
      const plain = String(value || '');
      if (!plain) return null;
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', credentialKey(), iv);
      const encrypted = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
      return `v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${encrypted.toString('base64')}`;
    };

    const decryptCredential = (value) => {
      const [version, iv, tag, encrypted] = String(value || '').split(':');
      if (version !== 'v1' || !iv || !tag || !encrypted) return '';
      const decipher = createDecipheriv('aes-256-gcm', credentialKey(), Buffer.from(iv, 'base64'));
      decipher.setAuthTag(Buffer.from(tag, 'base64'));
      return Buffer.concat([decipher.update(Buffer.from(encrypted, 'base64')), decipher.final()]).toString('utf8');
    };

    const serverConfiguredAliases = () => cleanText(env?.SYMBOLIKA_MAIL_ALLOWED_ALIASES, 10000)
      .split(/[;,]/).map((email) => email.trim().toLowerCase()).filter((email) => EMAIL_PATTERN.test(email));

    const publicMailAccount = (account, aliases = []) => ({
      id: account.id,
      name: account.name,
      email: account.email,
      employee: account.employee,
      use_server_credentials: Boolean(account.use_server_credentials),
      imap_host: account.use_server_credentials ? cleanText(env?.SYMBOLIKA_IMAP_HOST, 255) : account.imap_host,
      imap_port: account.use_server_credentials ? Number(env?.SYMBOLIKA_IMAP_PORT || 993) : account.imap_port,
      imap_secure: account.use_server_credentials ? boolEnv(env?.SYMBOLIKA_IMAP_SECURE, true) : Boolean(account.imap_secure),
      imap_username: account.use_server_credentials ? cleanText(env?.SYMBOLIKA_IMAP_USER, 255) : account.imap_username,
      imap_password_configured: account.use_server_credentials
        ? Boolean(env?.SYMBOLIKA_IMAP_PASSWORD)
        : Boolean(account.imap_password_encrypted),
      smtp_host: account.use_server_credentials ? cleanText(env?.SYMBOLIKA_SMTP_HOST || env?.EMAIL_SMTP_HOST, 255) : account.smtp_host,
      smtp_port: account.use_server_credentials ? Number(env?.SYMBOLIKA_SMTP_PORT || env?.EMAIL_SMTP_PORT || 465) : account.smtp_port,
      smtp_secure: account.use_server_credentials ? boolEnv(env?.SYMBOLIKA_SMTP_SECURE, true) : Boolean(account.smtp_secure),
      smtp_username: account.use_server_credentials ? cleanText(env?.SYMBOLIKA_SMTP_USER || env?.EMAIL_SMTP_USER, 255) : account.smtp_username,
      smtp_password_configured: account.use_server_credentials
        ? Boolean(env?.SYMBOLIKA_SMTP_PASSWORD || env?.EMAIL_SMTP_PASSWORD)
        : Boolean(account.smtp_password_encrypted),
      is_active: Boolean(account.is_active),
      aliases: [...new Map([
        ...aliases,
        ...(account.use_server_credentials ? serverConfiguredAliases().map((email) => ({ email, name: '' })) : []),
      ].filter((alias) => cleanText(alias.email, 255).toLowerCase() !== cleanText(account.email, 255).toLowerCase())
        .map((alias) => [cleanText(alias.email, 255).toLowerCase(), alias])).values()],
    });

    const mailAccount = async (accountId) => {
      let query = database('symbolika_mail_accounts').where('is_active', true);
      if (Number(accountId || 0)) query = query.where('id', Number(accountId));
      else query = query.orderBy('use_server_credentials', 'desc').orderBy('id', 'asc');
      return query.first();
    };

    const accountImapSettings = (account) => {
      const server = Boolean(account?.use_server_credentials);
      const host = cleanText(server ? env?.SYMBOLIKA_IMAP_HOST : account?.imap_host, 255);
      const user = cleanText(server ? env?.SYMBOLIKA_IMAP_USER : account?.imap_username, 255);
      const pass = server ? String(env?.SYMBOLIKA_IMAP_PASSWORD || '') : decryptCredential(account?.imap_password_encrypted);
      const port = Number(server ? env?.SYMBOLIKA_IMAP_PORT : account?.imap_port) || 993;
      return { host, user, pass, port, secure: server ? boolEnv(env?.SYMBOLIKA_IMAP_SECURE, port === 993) : Boolean(account?.imap_secure), configured: Boolean(host && user && pass) };
    };

    const accountSmtpSettings = (account) => {
      const server = Boolean(account?.use_server_credentials);
      const host = cleanText(server ? (env?.SYMBOLIKA_SMTP_HOST || env?.EMAIL_SMTP_HOST) : account?.smtp_host, 255);
      const user = cleanText(server ? (env?.SYMBOLIKA_SMTP_USER || env?.EMAIL_SMTP_USER) : account?.smtp_username, 255);
      const pass = server ? String(env?.SYMBOLIKA_SMTP_PASSWORD || env?.EMAIL_SMTP_PASSWORD || '') : decryptCredential(account?.smtp_password_encrypted);
      const port = Number(server ? (env?.SYMBOLIKA_SMTP_PORT || env?.EMAIL_SMTP_PORT) : account?.smtp_port) || 465;
      return { host, user, pass, port, secure: server ? boolEnv(env?.SYMBOLIKA_SMTP_SECURE, port === 465) : Boolean(account?.smtp_secure), configured: Boolean(host && user && pass) };
    };

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
          'e.is_active as employee_is_active',
          'e.email_signature', 'e.email_signature_settings', 'e.public_position', 'e.phone as employee_phone',
        )
        .first();
      if (!actor) {
        apiError(res, 403, 'Почта недоступна для текущего пользователя.');
        return null;
      }
      actor.is_admin = ADMIN_ROLES.has(actor.role_name);
      if (!actor.is_admin && (!actor.employee_id || actor.employee_is_active === false)) {
        apiError(res, 403, 'Почта доступна активным сотрудникам с учетной записью.');
        return null;
      }
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

    const permissionColumn = (permission = 'read') => ({
      read: 'can_read',
      reply: 'can_reply',
      send: 'can_send',
    }[permission] || 'can_read');

    const folderAccess = async (folder, actor) => {
      if (!folder) return { read: false, reply: false, send: false };
      if (actor.is_admin || Number(folder.employee) === Number(actor.employee_id)) {
        return { read: true, reply: true, send: true };
      }
      if (!actor.employee_id) return { read: false, reply: false, send: false };
      const member = await database('symbolika_mail_folder_members')
        .where({ folder_id: folder.id, employee: actor.employee_id })
        .first('can_read', 'can_reply', 'can_send');
      return {
        read: Boolean(member?.can_read),
        reply: Boolean(member?.can_reply),
        send: Boolean(member?.can_send),
      };
    };

    const applyFolderAccess = (query, actor, alias = 'f', permission = 'read') => {
      if (actor.is_admin) return query;
      const permissionField = permissionColumn(permission);
      if (!actor.employee_id) return query.whereRaw('false');
      return query.where((builder) => {
        builder.where(`${alias}.employee`, actor.employee_id)
          .orWhereExists(function memberFolderAccess() {
            this.select(database.raw('1'))
              .from('symbolika_mail_folder_members as mail_member')
              .whereRaw(`mail_member.folder_id = ${alias}.id`)
              .where('mail_member.employee', actor.employee_id)
              .where(`mail_member.${permissionField}`, true);
          });
      });
    };

    const accessibleFolder = async (folderId, actor, permission = 'read') => {
      let query = database('symbolika_mail_folders as f')
        .where('f.id', Number(folderId))
        .where('f.is_active', true)
        .select('f.*');
      query = applyFolderAccess(query, actor, 'f', permission);
      const folder = await query.first();
      return folder ? { ...folder, access: await folderAccess(folder, actor) } : null;
    };

    const accessibleSystemFolder = async (folderType, actor, permission = 'read', accountId = null) => {
      let query = database('symbolika_mail_folders as f')
        .where('f.folder_type', folderType)
        .where('f.is_active', true)
        .select('f.*');
      if (Number(accountId || 0)) query = query.where('f.mail_account', Number(accountId));
      query = applyFolderAccess(query, actor, 'f', permission);
      const folder = await query.first();
      return folder ? { ...folder, access: await folderAccess(folder, actor) } : null;
    };

    const accessibleThread = async (threadId, actor) => {
      let query = database('symbolika_mail_threads as t')
        .join('symbolika_mail_folders as f', 'f.id', 't.folder_id')
        .where('t.id', Number(threadId))
        .select('t.*', 'f.name as folder_name', 'f.alias_email', 'f.employee as folder_employee', 'f.mail_account');
      query = applyFolderAccess(query, actor);
      const thread = await query.first();
      if (!thread) return null;
      thread.access = await folderAccess({ id: thread.folder_id, employee: thread.folder_employee }, actor);
      return thread;
    };

    const folderRows = async (actor) => {
      let query = database('symbolika_mail_folders as f')
        .where('f.is_active', true)
        .select('f.*')
        .orderBy('f.sort', 'asc')
        .orderBy('f.name', 'asc');
      query = applyFolderAccess(query, actor);
      const folders = await query;
      const accountIds = [...new Set(folders.map((row) => Number(row.mail_account)).filter(Number.isInteger))];
      const accountRows = accountIds.length
        ? await database('symbolika_mail_accounts').whereIn('id', accountIds).where('is_active', true).select('id', 'email', 'use_server_credentials')
        : [];
      const aliasRows = accountIds.length
        ? await database('symbolika_mail_aliases').whereIn('mail_account', accountIds).where('is_active', true).select('mail_account', 'email')
        : [];
      const accountEmails = new Map(accountRows.map((row) => [Number(row.id), cleanText(row.email, 255).toLowerCase()]));
      const accountSenders = new Map(accountRows.map((row) => [Number(row.id), [
        cleanText(row.email, 255).toLowerCase(),
        ...(row.use_server_credentials ? serverConfiguredAliases() : []),
        ...aliasRows.filter((alias) => Number(alias.mail_account) === Number(row.id)).map((alias) => cleanText(alias.email, 255).toLowerCase()),
      ].filter(Boolean)]));
      const activeAccountIds = new Set(accountRows.map((row) => Number(row.id)));
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
      return Promise.all(folders.filter((folder) => activeAccountIds.has(Number(folder.mail_account))).map(async (folder) => ({
        ...folder,
        account_email: accountEmails.get(Number(folder.mail_account)) || '',
        sender_addresses: [...new Set(accountSenders.get(Number(folder.mail_account)) || [])],
        access: await folderAccess(folder, actor),
        total: Number(byFolder.get(Number(folder.id))?.total || 0),
        unread: Number(byFolder.get(Number(folder.id))?.unread || 0),
      })));
    };

    const folderMembers = async (folderIds) => {
      const ids = [...new Set((folderIds || []).map(Number).filter(Number.isInteger))];
      if (!ids.length) return new Map();
      const rows = await database('symbolika_mail_folder_members as member')
        .join('employees as e', 'e.id', 'member.employee')
        .whereIn('member.folder_id', ids)
        .select(
          'member.folder_id', 'member.employee', 'member.can_read', 'member.can_reply', 'member.can_send',
          'e.full_name as employee_name',
        )
        .orderBy('e.full_name');
      const result = new Map(ids.map((id) => [id, []]));
      rows.forEach((row) => result.get(Number(row.folder_id))?.push({
        employee: Number(row.employee),
        employee_name: row.employee_name,
        can_read: Boolean(row.can_read),
        can_reply: Boolean(row.can_reply),
        can_send: Boolean(row.can_send),
      }));
      return result;
    };

    const aliasesByAccount = async (accountIds) => {
      const ids = [...new Set((accountIds || []).map(Number).filter(Number.isInteger))];
      if (!ids.length) return new Map();
      const rows = await database('symbolika_mail_aliases')
        .whereIn('mail_account', ids)
        .where('is_active', true)
        .select('id', 'mail_account', 'email', 'name')
        .orderBy('email');
      const result = new Map(ids.map((id) => [id, []]));
      rows.forEach((row) => result.get(Number(row.mail_account))?.push({ id: row.id, email: row.email, name: row.name || '' }));
      return result;
    };

    const normalizeAccountAliases = (input, primaryEmail) => {
      const aliases = [];
      const seen = new Set([cleanText(primaryEmail, 255).toLowerCase()]);
      jsonArray(input).forEach((row) => {
        const email = cleanText(typeof row === 'string' ? row : row?.email, 255).toLowerCase();
        if (!email || seen.has(email)) return;
        if (!EMAIL_PATTERN.test(email)) throw new Error(`Некорректный адрес псевдонима: ${email}`);
        seen.add(email);
        aliases.push({ email, name: cleanText(row?.name, 255) || null });
      });
      return aliases;
    };

    const replaceAccountAliases = async (trx, accountId, aliases) => {
      await trx('symbolika_mail_aliases').where('mail_account', accountId).delete();
      if (aliases.length) {
        await trx('symbolika_mail_aliases').insert(aliases.map((alias) => ({
          mail_account: accountId,
          ...alias,
          is_active: true,
          date_created: new Date(),
          date_updated: new Date(),
        })));
      }
    };

    const assertAccountSender = async (accountId, senderEmail) => {
      const account = await database('symbolika_mail_accounts').where('id', Number(accountId)).where('is_active', true).first('id', 'email');
      if (!account) throw new Error('Выберите активный почтовый аккаунт.');
      const sender = cleanText(senderEmail, 255).toLowerCase();
      if (!sender || sender === cleanText(account.email, 255).toLowerCase()) return account;
      const alias = await database('symbolika_mail_aliases')
        .where('mail_account', account.id).where('is_active', true)
        .whereRaw('lower(email) = lower(?)', [sender]).first('id');
      if (!alias) throw new Error('Адрес отправителя должен быть основным адресом или псевдонимом выбранного аккаунта.');
      return account;
    };

    const syncFolderMembers = async (trx, folderId, ownerId, input) => {
      const requested = new Map();
      jsonArray(input).forEach((row) => {
        const employee = Number(row?.employee || 0);
        if (!Number.isInteger(employee) || employee <= 0 || employee === Number(ownerId)) return;
        const canReply = Boolean(row?.can_reply);
        const canSend = Boolean(row?.can_send);
        requested.set(employee, {
          folder_id: folderId,
          employee,
          can_read: Boolean(row?.can_read) || canReply || canSend,
          can_reply: canReply,
          can_send: canSend,
          date_created: new Date(),
          date_updated: new Date(),
        });
      });
      const employeeIds = [...requested.keys()];
      const activeIds = employeeIds.length
        ? new Set((await trx('employees as e')
          .join('directus_users as u', 'u.id', 'e.directus_user')
          .whereIn('e.id', employeeIds)
          .where('e.is_active', true)
          .where('u.status', 'active')
          .pluck('e.id')).map(Number))
        : new Set();
      await trx('symbolika_mail_folder_members').where('folder_id', folderId).delete();
      const members = [...requested.values()].filter((row) => activeIds.has(row.employee));
      if (members.length) await trx('symbolika_mail_folder_members').insert(members);
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
      if (!folder) return [];
      const recipients = new Set();
      if (folder.employee) {
        const owner = await database('employees as e')
          .join('directus_users as u', 'u.id', 'e.directus_user')
          .where('e.id', folder.employee)
          .where('e.is_active', true)
          .where('u.status', 'active')
          .first('u.id');
        if (owner?.id) recipients.add(owner.id);
      }
      const members = await database('symbolika_mail_folder_members as member')
        .join('employees as e', 'e.id', 'member.employee')
        .join('directus_users as u', 'u.id', 'e.directus_user')
        .where('member.folder_id', folder.id)
        .where('member.can_read', true)
        .where('u.status', 'active')
        .where('e.is_active', true)
        .distinct('u.id');
      members.forEach((row) => recipients.add(row.id));
      return [...recipients];
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

    const smtpSender = (account) => {
      const settings = accountSmtpSettings(account);
      if (!settings.configured) return null;
      return nodemailer.createTransport({
        host: settings.host,
        port: settings.port,
        secure: settings.secure,
        auth: { user: settings.user, pass: settings.pass },
      });
    };

    const smtpEnvelopeSender = (account) => cleanText(
      accountSmtpSettings(account).user || account?.email,
      255,
    ).toLowerCase();

    const smtpErrorMessage = (error, fromAlias) => {
      const code = cleanText(error?.code, 40).toUpperCase();
      const responseCode = Number(error?.responseCode || 0);
      if (code === 'EAUTH' || responseCode === 535) {
        return 'Почтовый сервер отклонил авторизацию. Проверьте логин и пароль SMTP.';
      }
      if (['ECONNECTION', 'ETIMEDOUT', 'ESOCKET', 'ECONNREFUSED'].includes(code)) {
        return 'Не удалось соединиться с почтовым сервером. Повторите отправку позже.';
      }
      if ([550, 551, 553].includes(responseCode)) {
        return `Почтовый сервер не разрешил отправку от ${fromAlias}. Проверьте, что этот адрес создан как псевдоним общего ящика.`;
      }
      return 'Почтовый сервер не принял письмо. Повторите попытку или обратитесь к администратору.';
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

    let imapSyncQueue = Promise.resolve();
    const missingImapFolders = new Set();
    const synchronizeImapFolders = (folders, { actor = null, limit = 60 } = {}) => {
      const run = async () => {
        let synced = 0;
        let configuredAccounts = 0;
        const failedAccounts = [];
        const perFolder = Math.min(Math.max(Number(limit || 60), 1), 200);
        const grouped = new Map();
        for (const folder of folders.filter((row) => cleanText(row?.imap_name, 500))) {
          const accountId = Number(folder.mail_account || 0);
          if (!grouped.has(accountId)) grouped.set(accountId, []);
          grouped.get(accountId).push(folder);
        }
        for (const [accountId, accountFolders] of grouped) {
          const account = await mailAccount(accountId || null);
          if (!account) continue;
          let settings;
          try {
            settings = accountImapSettings(account);
          } catch (error) {
            logger.warn({ account: account.email, error: error?.message }, '[Symbolika Mail] cannot decrypt IMAP credentials');
            continue;
          }
          if (!settings.configured) continue;
          configuredAccounts += 1;
          const client = new ImapFlow({
            host: settings.host,
            port: settings.port,
            secure: settings.secure,
            auth: { user: settings.user, pass: settings.pass },
            logger: false,
          });
          try {
            await client.connect();
            const availableFolders = new Set((await client.list()).map((row) => cleanText(row?.path, 500)).filter(Boolean));
            for (const folder of accountFolders) {
            const imapName = cleanText(folder.imap_name, 500);
            const missingKey = `${account.id}:${imapName}`;
            if (!availableFolders.has(imapName)) {
              if (!missingImapFolders.has(missingKey)) {
                missingImapFolders.add(missingKey);
                logger.warn({ account: account.email, folder: imapName }, '[Symbolika Mail] configured folder is missing on IMAP server');
              }
              continue;
            }
            missingImapFolders.delete(missingKey);
            let lock;
            try {
              lock = await client.getMailboxLock(imapName);
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
          } catch (error) {
            failedAccounts.push(account.email);
            logger.warn({ account: account.email, error: error?.message }, '[Symbolika Mail] account sync failed');
          } finally {
            try { await client.logout(); } catch { /* connection already closed */ }
          }
        }
        if (grouped.size && !configuredAccounts) {
          const error = new Error('IMAP не настроен ни для одного доступного почтового аккаунта.');
          error.code = 'IMAP_NOT_CONFIGURED';
          throw error;
        }
        return { synced, accounts: configuredAccounts, failed_accounts: failedAccounts };
      };

      const queued = imapSyncQueue.then(run, run);
      imapSyncQueue = queued.catch(() => undefined);
      return queued;
    };

    globalThis[BACKGROUND_SYNC_STATE_KEY]?.stop?.();
    const backgroundSyncEnabled = boolEnv(env?.SYMBOLIKA_MAIL_BACKGROUND_SYNC_ENABLED, true);
    if (mailMode() === 'imap' && backgroundSyncEnabled) {
      const requestedInterval = Number(env?.SYMBOLIKA_MAIL_BACKGROUND_SYNC_INTERVAL_MS || 20000);
      const intervalMs = Math.min(Math.max(Number.isFinite(requestedInterval) ? requestedInterval : 20000, 10000), 600000);
      const requestedLimit = Number(env?.SYMBOLIKA_MAIL_BACKGROUND_SYNC_LIMIT || 60);
      const backgroundLimit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 60, 1), 200);
      let stopped = false;
      let backgroundRunning = false;
      const syncAllFolders = async () => {
        if (stopped || backgroundRunning) return;
        backgroundRunning = true;
        try {
          const folders = await database('symbolika_mail_folders')
            .where('is_active', true)
            .whereNotNull('imap_name')
            .whereNot('imap_name', '')
            .orderBy('sort', 'asc')
            .orderBy('name', 'asc');
          if (!folders.length) return;
          const result = await synchronizeImapFolders(folders, { limit: backgroundLimit });
          if (result.synced > 0) logger.info({ synced: result.synced }, '[Symbolika Mail] background sync completed');
        } catch (error) {
          logger.warn({ error: error?.message }, '[Symbolika Mail] background sync failed');
        } finally {
          backgroundRunning = false;
        }
      };
      const startupTimer = setTimeout(syncAllFolders, 3000);
      const intervalTimer = setInterval(syncAllFolders, intervalMs);
      startupTimer.unref?.();
      intervalTimer.unref?.();
      globalThis[BACKGROUND_SYNC_STATE_KEY] = {
        stop() {
          stopped = true;
          clearTimeout(startupTimer);
          clearInterval(intervalTimer);
        },
      };
      logger.info({ interval_ms: intervalMs }, '[Symbolika Mail] background sync enabled');
    } else {
      globalThis[BACKGROUND_SYNC_STATE_KEY] = { stop() {} };
      if (mailMode() === 'imap' && backgroundSyncEnabled) {
        logger.warn('[Symbolika Mail] background sync disabled because IMAP is not configured');
      }
    }

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
        const accessibleAccountIds = [...new Set(folders.map((folder) => Number(folder.mail_account)).filter(Number.isInteger))];
        const configuredAccount = accessibleAccountIds.length
          ? await database('symbolika_mail_accounts')
            .whereIn('id', accessibleAccountIds)
            .where('is_active', true)
            .where((builder) => builder
              .where((server) => server.where('use_server_credentials', true))
              .orWhere((stored) => stored.whereNotNull('imap_password_encrypted').whereNotNull('smtp_password_encrypted')))
            .first('id')
          : null;
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
            configured: Boolean(configuredAccount),
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

    router.post('/threads/read-all', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;

        const requestedFolder = Number(req.body?.folder_id || 0);
        const starredScope = cleanText(req.body?.scope, 30) === 'starred';
        const threadFilter = cleanText(req.body?.filter, 30);
        const search = cleanText(req.body?.search, 200);

        if (!starredScope) {
          const folder = await accessibleFolder(requestedFolder, actor);
          if (!folder) return apiError(res, 400, 'Выберите доступную почтовую папку.');
        }

        let query = threadQuery(actor)
          .where('t.is_archived', false)
          .where('t.is_unread', true);
        if (starredScope) query = query.where('t.is_starred', true);
        else query = query.where('t.folder_id', requestedFolder);
        if (threadFilter === 'starred') query = query.where('t.is_starred', true);
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

        const rows = await query;
        const threadIds = [...new Set(rows.map((row) => Number(row.id)).filter(Number.isInteger))];
        if (threadIds.length) {
          await database.transaction(async (trx) => {
            await trx('symbolika_mail_threads')
              .whereIn('id', threadIds)
              .update({ is_unread: false, date_updated: new Date() });
            await trx('symbolika_mail_messages')
              .whereIn('thread_id', threadIds)
              .update({ is_read: true });
          });
        }

        return res.json({ data: { updated: threadIds.length } });
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
            .where('f.folder_type', 'archive')
            .where('f.mail_account', thread.mail_account)
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
        let parsedPayload;
        try {
          parsedPayload = await outgoingPayload(req);
        } catch (error) {
          return apiError(res, 400, cleanText(error?.message, 1000) || 'Не удалось прочитать вложения письма.');
        }
        req.body = parsedPayload.fields;
        req.body.include_signature = String(req.body.include_signature ?? 'true') !== 'false';
        const outgoingAttachments = parsedPayload.attachments;
        const to = cleanText(req.body?.to, 2000).split(/[;,]/).map((value) => value.trim().toLowerCase()).filter(Boolean);
        if (!to.length || to.some((email) => !EMAIL_PATTERN.test(email))) return apiError(res, 400, 'Укажите корректный адрес получателя.');
        const subject = cleanText(req.body?.subject || '(без темы)', 2000);
        const body = cleanText(req.body?.body, 200000);
        if (!body && !outgoingAttachments.length) return apiError(res, 400, 'Введите текст письма или прикрепите файл.');

        const requestedThreadId = Number(req.body?.thread_id || 0);
        const replyThread = requestedThreadId ? await accessibleThread(requestedThreadId, actor) : null;
        if (requestedThreadId && !replyThread) return apiError(res, 404, 'Переписка не найдена или недоступна.');
        const requestedFolderId = Number(req.body?.folder_id || replyThread?.folder_id || 0);
        const requiredPermission = replyThread ? 'reply' : 'send';
        const folder = await accessibleFolder(requestedFolderId, actor, requiredPermission);
        if (!folder) {
          return apiError(res, 403, replyThread
            ? 'У вас нет права отвечать из этой почтовой папки.'
            : 'У вас нет права отправлять письма из этой почтовой папки.');
        }
        const account = await mailAccount(folder.mail_account);
        if (!account) return apiError(res, 503, 'Для папки не выбран активный почтовый аккаунт.');
        const storageFolder = replyThread ? folder : (await accessibleSystemFolder('sent', actor, 'send', account.id) || folder);
        const folderAlias = cleanText(folder.alias_email, 255).toLowerCase();
        const accountEmail = cleanText(account.email, 255).toLowerCase();
        const fromAlias = cleanText(req.body?.from_alias || folderAlias || accountEmail, 255).toLowerCase();
        if (!EMAIL_PATTERN.test(fromAlias)) return apiError(res, 400, 'Для папки не настроен адрес отправителя.');
        const accountAliases = await database('symbolika_mail_aliases')
          .where('mail_account', account.id)
          .where('is_active', true)
          .select('email');
        const allowedAliases = new Set([
          accountEmail,
          ...accountAliases.map((row) => cleanText(row.email, 255).toLowerCase()),
          ...(account.use_server_credentials ? serverConfiguredAliases() : []),
        ]);
        if (!allowedAliases.has(fromAlias)) {
          return apiError(res, 403, 'Этот адрес не принадлежит выбранному почтовому аккаунту.');
        }
        const signatureHtml = req.body?.include_signature === false ? '' : brandedSignatureHtml(actor, fromAlias);
        const signatureText = signaturePlainText(signatureHtml);
        const deliveredBody = signatureText ? `${body}\n\n-- \n${signatureText}` : body;
        const deliveredHtml = `${escapeHtml(body).replace(/\r?\n/g, '<br>')}${signatureHtml ? `<div style="margin-top:24px">${signatureHtml}</div>` : ''}`;

        let messageId = `<mock-${Date.now()}-${Math.random().toString(16).slice(2)}@symb62.ru>`;
        let delivered = false;
        if (mailMode() === 'imap') {
          let transport;
          try {
            transport = smtpSender(account);
          } catch (error) {
            logger.error({ account: account.email, error: error?.message }, 'Symbolika mail SMTP credentials failed');
            return apiError(res, 503, 'Не удалось прочитать настройки SMTP этого аккаунта.');
          }
          if (!transport) return apiError(res, 503, 'SMTP не настроен для выбранного почтового аккаунта.');
          const envelopeFrom = smtpEnvelopeSender(account);
          if (!EMAIL_PATTERN.test(envelopeFrom)) return apiError(res, 503, 'Для SMTP не настроен адрес авторизованного ящика.');
          let result;
          try {
            result = await transport.sendMail({
              from: { name: actor.name, address: fromAlias },
              replyTo: fromAlias,
              envelope: { from: envelopeFrom, to },
              to,
              subject,
              text: deliveredBody,
              html: deliveredHtml,
              attachments: outgoingAttachments.map((file) => ({
                filename: file.filename,
                content: file.content,
                contentType: file.contentType,
              })),
              inReplyTo: replyThread?.external_thread_id?.startsWith('<') ? replyThread.external_thread_id : undefined,
            });
          } catch (error) {
            logger.error({
              err: error,
              smtp_code: cleanText(error?.code, 40),
              smtp_response_code: Number(error?.responseCode || 0) || null,
              from_alias: fromAlias,
              envelope_from: envelopeFrom,
            }, 'Symbolika mail SMTP send failed');
            return apiError(res, 502, smtpErrorMessage(error, fromAlias));
          }
          messageId = result?.messageId || messageId;
          delivered = true;
        }

        let threadId = replyThread?.id;
        if (!threadId) {
          const [created] = await database('symbolika_mail_threads').insert({
            folder_id: storageFolder.id,
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
        const savedAttachments = await persistAttachments({ attachments: outgoingAttachments });
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
          attachments: JSON.stringify(savedAttachments),
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
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (mailMode() !== 'imap') return res.json({ data: { mode: 'mock', synced: 0, message: 'Демо-режим: тестовые письма уже загружены.' } });
        const folders = (await folderRows(actor)).filter((folder) => folder.imap_name);
        if (!folders.length) return apiError(res, 503, 'У доступных почтовых аккаунтов не настроены папки IMAP.');
        const perFolder = Math.min(Math.max(Number(req.body?.limit || 60), 1), 200);
        const result = await synchronizeImapFolders(folders, { actor, limit: perFolder });
        return res.json({ data: {
          mode: 'imap',
          synced: result.synced,
          failed_accounts: result.failed_accounts,
          message: result.failed_accounts?.length
            ? `Синхронизация завершена, но не удалось подключиться: ${result.failed_accounts.join(', ')}.`
            : undefined,
        } });
      } catch (error) {
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
          .select(
            'e.id', 'e.full_name', 'e.email_signature', 'e.email_signature_settings', 'e.public_position', 'e.phone',
            'u.id as user_id', 'u.email', 'u.status as user_status',
          )
          .orderBy('e.full_name');
        employees.forEach((employee) => {
          employee.mail_enabled = Boolean(employee.user_id && employee.user_status === 'active');
          employee.email_signature = sanitizeSignatureHtml(employee.email_signature);
          employee.signature_settings = signatureSettings(employee, employee.email);
          employee.signature_defaults = signatureDefaults(employee, employee.email);
          employee.signature_preview = brandedSignatureHtml(employee, employee.email);
        });
        const folders = await folderRows(actor);
        const membersByFolder = await folderMembers(folders.map((folder) => folder.id));
        const accounts = await database('symbolika_mail_accounts').orderBy('name').orderBy('email');
        const accountAliases = await aliasesByAccount(accounts.map((account) => account.id));
        return res.json({
          data: {
            folders: folders.map((folder) => ({
              ...folder,
              members: membersByFolder.get(Number(folder.id)) || [],
            })),
            employees,
            accounts: accounts.map((account) => publicMailAccount(account, accountAliases.get(Number(account.id)) || [])),
            connection: {
              mode: mailMode(),
              active_accounts: accounts.filter((account) => account.is_active).length,
              configured_accounts: accounts.filter((account) => {
                const view = publicMailAccount(account);
                return account.is_active && view.imap_password_configured && view.smtp_password_configured;
              }).length,
            },
          },
        });
      } catch (error) {
        return next(error);
      }
    });

    router.post('/accounts', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Подключать почтовые аккаунты может только администратор или управляющий.');
        const email = cleanText(req.body?.email, 255).toLowerCase();
        const name = cleanText(req.body?.name, 255) || email;
        if (!EMAIL_PATTERN.test(email)) return apiError(res, 400, 'Укажите корректный адрес почтового аккаунта.');
        const useServer = Boolean(req.body?.use_server_credentials);
        const imapPassword = String(req.body?.imap_password || '');
        const smtpPassword = String(req.body?.smtp_password || imapPassword || '');
        if (!useServer && (!imapPassword || !smtpPassword)) return apiError(res, 400, 'Укажите пароли IMAP и SMTP.');
        let aliases;
        try { aliases = normalizeAccountAliases(req.body?.aliases, email); } catch (error) { return apiError(res, 400, error.message); }
        const employee = Number(req.body?.employee || 0) || null;
        let created;
        await database.transaction(async (trx) => {
          [created] = await trx('symbolika_mail_accounts').insert({
            name, email, employee,
            use_server_credentials: useServer,
            imap_host: useServer ? null : cleanText(req.body?.imap_host, 255),
            imap_port: Number(req.body?.imap_port || 993),
            imap_secure: req.body?.imap_secure !== false,
            imap_username: useServer ? null : cleanText(req.body?.imap_username || email, 255),
            imap_password_encrypted: useServer ? null : encryptCredential(imapPassword),
            smtp_host: useServer ? null : cleanText(req.body?.smtp_host, 255),
            smtp_port: Number(req.body?.smtp_port || 465),
            smtp_secure: req.body?.smtp_secure !== false,
            smtp_username: useServer ? null : cleanText(req.body?.smtp_username || email, 255),
            smtp_password_encrypted: useServer ? null : encryptCredential(smtpPassword),
            is_active: true,
            date_created: new Date(), date_updated: new Date(),
          }).returning('*');
          await replaceAccountAliases(trx, created.id, aliases);
          const folderSpecs = [
            ['inbox', 'Входящие', cleanText(req.body?.inbox_imap_name, 500) || 'INBOX', 10],
            ['sent', 'Отправленные', cleanText(req.body?.sent_imap_name, 500) || 'Sent', 900],
            ['archive', 'Архив', cleanText(req.body?.archive_imap_name, 500) || 'Archive', 950],
          ];
          for (const [folderType, folderName, imapName, sort] of folderSpecs) {
            await trx('symbolika_mail_folders').insert({
              slug: `account-${created.id}-${folderType}`,
              name: `${folderName} — ${email}`,
              imap_name: imapName,
              alias_email: email,
              mail_account: created.id,
              folder_type: folderType,
              employee,
              is_shared: false,
              is_system: true,
              is_active: true,
              sort: sort + Number(created.id) * 1000,
              date_created: new Date(), date_updated: new Date(),
            });
          }
          if (employee) {
            await trx('symbolika_mail_folders')
              .where('employee', employee)
              .whereNull('imap_name')
              .whereNot('mail_account', created.id)
              .whereNotExists(function hasThreads() {
                this.select(trx.raw('1')).from('symbolika_mail_threads as t').whereRaw('t.folder_id = symbolika_mail_folders.id');
              })
              .update({ is_active: false, date_updated: new Date() });
          }
        });
        return res.status(201).json({ data: publicMailAccount(created, aliases) });
      } catch (error) {
        if (error?.code === '23505') return apiError(res, 409, 'Такой почтовый аккаунт или псевдоним уже подключен.');
        return next(error);
      }
    });

    router.patch('/accounts/:id', async (req, res, next) => {
      try {
        const actor = await actorContext(req, res);
        if (!actor) return;
        if (!actor.is_admin) return apiError(res, 403, 'Изменять почтовые аккаунты может только администратор или управляющий.');
        const current = await database('symbolika_mail_accounts').where('id', Number(req.params.id)).first();
        if (!current) return apiError(res, 404, 'Почтовый аккаунт не найден.');
        const email = cleanText(req.body?.email ?? current.email, 255).toLowerCase();
        if (!EMAIL_PATTERN.test(email)) return apiError(res, 400, 'Укажите корректный адрес почтового аккаунта.');
        let aliases;
        try { aliases = normalizeAccountAliases(req.body?.aliases ?? [], email); } catch (error) { return apiError(res, 400, error.message); }
        const useServer = Object.prototype.hasOwnProperty.call(req.body || {}, 'use_server_credentials')
          ? Boolean(req.body.use_server_credentials) : Boolean(current.use_server_credentials);
        const update = {
          name: cleanText(req.body?.name ?? current.name, 255) || email,
          email,
          employee: Number(req.body?.employee || 0) || null,
          use_server_credentials: useServer,
          imap_host: useServer ? null : cleanText(req.body?.imap_host ?? current.imap_host, 255),
          imap_port: Number(req.body?.imap_port || current.imap_port || 993),
          imap_secure: req.body?.imap_secure === undefined ? Boolean(current.imap_secure) : Boolean(req.body.imap_secure),
          imap_username: useServer ? null : cleanText(req.body?.imap_username ?? current.imap_username ?? email, 255),
          smtp_host: useServer ? null : cleanText(req.body?.smtp_host ?? current.smtp_host, 255),
          smtp_port: Number(req.body?.smtp_port || current.smtp_port || 465),
          smtp_secure: req.body?.smtp_secure === undefined ? Boolean(current.smtp_secure) : Boolean(req.body.smtp_secure),
          smtp_username: useServer ? null : cleanText(req.body?.smtp_username ?? current.smtp_username ?? email, 255),
          is_active: req.body?.is_active === undefined ? Boolean(current.is_active) : Boolean(req.body.is_active),
          date_updated: new Date(),
        };
        if (useServer) {
          update.imap_password_encrypted = null;
          update.smtp_password_encrypted = null;
        } else {
          if (req.body?.imap_password) update.imap_password_encrypted = encryptCredential(req.body.imap_password);
          if (req.body?.smtp_password) update.smtp_password_encrypted = encryptCredential(req.body.smtp_password);
          if (req.body?.clear_imap_password) update.imap_password_encrypted = null;
          if (req.body?.clear_smtp_password) update.smtp_password_encrypted = null;
        }
        await database.transaction(async (trx) => {
          await trx('symbolika_mail_accounts').where('id', current.id).update(update);
          await replaceAccountAliases(trx, current.id, aliases);
          await trx('symbolika_mail_folders')
            .where('mail_account', current.id)
            .update({
              employee: update.employee,
              alias_email: trx.raw('CASE WHEN lower(alias_email) = lower(?) THEN ? ELSE alias_email END', [current.email, email]),
              date_updated: new Date(),
            });
        });
        const saved = await database('symbolika_mail_accounts').where('id', current.id).first();
        return res.json({ data: publicMailAccount(saved, aliases) });
      } catch (error) {
        if (error?.code === '23505') return apiError(res, 409, 'Такой почтовый аккаунт или псевдоним уже подключен.');
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
        if ('mail_account' in (req.body || {})) update.mail_account = Number(req.body.mail_account || 0) || null;
        if ('folder_type' in (req.body || {})) {
          const folderType = cleanText(req.body.folder_type, 30);
          update.folder_type = ['inbox', 'sent', 'archive', 'custom'].includes(folderType) ? folderType : 'custom';
        }
        if ('employee' in (req.body || {})) update.employee = Number(req.body.employee || 0) || null;
        if ('is_shared' in (req.body || {})) update.is_shared = Boolean(req.body.is_shared);
        if ('is_active' in (req.body || {})) update.is_active = Boolean(req.body.is_active);
        const targetAccount = update.mail_account ?? current.mail_account;
        try { await assertAccountSender(targetAccount, update.alias_email ?? current.alias_email); } catch (error) { return apiError(res, 400, error.message); }
        await database.transaction(async (trx) => {
          await trx('symbolika_mail_folders').where('id', current.id).update(update);
          if (Object.prototype.hasOwnProperty.call(req.body || {}, 'members')) {
            await syncFolderMembers(trx, current.id, update.employee ?? current.employee, req.body.members);
          }
        });
        const membersByFolder = await folderMembers([current.id]);
        return res.json({ data: { id: current.id, ...update, members: membersByFolder.get(Number(current.id)) || [] } });
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
        const accountId = Number(req.body?.mail_account || 0);
        if (!accountId) return apiError(res, 400, 'Выберите почтовый аккаунт.');
        let account;
        try { account = await assertAccountSender(accountId, aliasEmail); } catch (error) { return apiError(res, 400, error.message); }
        const baseSlug = cleanText(name, 120).toLowerCase()
          .replace(/[^a-zа-яё0-9]+/gi, '-')
          .replace(/^-+|-+$/g, '') || 'folder';
        let slug = baseSlug;
        let suffix = 2;
        while (await database('symbolika_mail_folders').where('slug', slug).first('id')) slug = `${baseSlug}-${suffix++}`;
        const maxSort = await database('symbolika_mail_folders').max('sort as value').first();
        let created;
        await database.transaction(async (trx) => {
          [created] = await trx('symbolika_mail_folders').insert({
            slug,
            name,
            imap_name: cleanText(req.body?.imap_name, 500) || null,
            alias_email: aliasEmail || account.email,
            mail_account: accountId,
            folder_type: 'custom',
            employee: Number(req.body?.employee || 0) || null,
            is_shared: Boolean(req.body?.is_shared),
            is_system: false,
            is_active: true,
            sort: Number(maxSort?.value || 100) + 10,
            date_created: new Date(),
            date_updated: new Date(),
          }).returning('*');
          await syncFolderMembers(trx, created.id, created.employee, req.body?.members);
        });
        const membersByFolder = await folderMembers([created.id]);
        return res.status(201).json({ data: { ...created, members: membersByFolder.get(Number(created.id)) || [] } });
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

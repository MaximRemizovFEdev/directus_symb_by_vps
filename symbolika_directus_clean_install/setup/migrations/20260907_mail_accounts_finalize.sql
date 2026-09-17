BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

UPDATE symbolika_mail_folders
SET mail_account = (
      SELECT id FROM symbolika_mail_accounts WHERE lower(email) = 'start@symb62.ru' LIMIT 1
    ),
    folder_type = CASE slug
      WHEN 'inbox' THEN 'inbox'
      WHEN 'sent' THEN 'sent'
      WHEN 'archive' THEN 'archive'
      ELSE folder_type
    END,
    date_updated = now()
WHERE mail_account IS NULL;

COMMIT;

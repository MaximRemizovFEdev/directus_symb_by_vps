BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS symbolika_mail_accounts (
  id bigserial PRIMARY KEY,
  name varchar(255) NOT NULL,
  email varchar(255) NOT NULL,
  employee integer REFERENCES employees(id) ON DELETE SET NULL,
  use_server_credentials boolean NOT NULL DEFAULT false,
  imap_host varchar(255),
  imap_port integer NOT NULL DEFAULT 993,
  imap_secure boolean NOT NULL DEFAULT true,
  imap_username varchar(255),
  imap_password_encrypted text,
  smtp_host varchar(255),
  smtp_port integer NOT NULL DEFAULT 465,
  smtp_secure boolean NOT NULL DEFAULT true,
  smtp_username varchar(255),
  smtp_password_encrypted text,
  is_active boolean NOT NULL DEFAULT true,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS symbolika_mail_accounts_email_uidx
  ON symbolika_mail_accounts (lower(email));

CREATE TABLE IF NOT EXISTS symbolika_mail_aliases (
  id bigserial PRIMARY KEY,
  mail_account bigint NOT NULL REFERENCES symbolika_mail_accounts(id) ON DELETE CASCADE,
  email varchar(255) NOT NULL,
  name varchar(255),
  is_active boolean NOT NULL DEFAULT true,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (mail_account, email)
);

CREATE UNIQUE INDEX IF NOT EXISTS symbolika_mail_aliases_email_uidx
  ON symbolika_mail_aliases (lower(email));

ALTER TABLE symbolika_mail_folders
  ADD COLUMN IF NOT EXISTS mail_account bigint REFERENCES symbolika_mail_accounts(id) ON DELETE RESTRICT;
ALTER TABLE symbolika_mail_folders
  ADD COLUMN IF NOT EXISTS folder_type varchar(30) NOT NULL DEFAULT 'custom';

INSERT INTO symbolika_mail_accounts (
  name, email, use_server_credentials, is_active
)
SELECT 'Основная почта', 'start@symb62.ru', true, true
WHERE NOT EXISTS (
  SELECT 1 FROM symbolika_mail_accounts WHERE lower(email) = 'start@symb62.ru'
);

UPDATE symbolika_mail_accounts
SET use_server_credentials = true,
    is_active = true,
    date_updated = now()
WHERE lower(email) = 'start@symb62.ru';

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

INSERT INTO symbolika_mail_aliases (mail_account, email, name, is_active)
SELECT DISTINCT
  account.id,
  lower(folder.alias_email),
  folder.name,
  true
FROM symbolika_mail_folders folder
JOIN symbolika_mail_accounts account ON lower(account.email) = 'start@symb62.ru'
WHERE folder.alias_email IS NOT NULL
  AND folder.alias_email <> ''
  AND lower(folder.alias_email) <> lower(account.email)
ON CONFLICT DO NOTHING;

CREATE INDEX IF NOT EXISTS symbolika_mail_folders_account_idx
  ON symbolika_mail_folders(mail_account, folder_type, is_active);
CREATE INDEX IF NOT EXISTS symbolika_mail_aliases_account_idx
  ON symbolika_mail_aliases(mail_account, is_active);

COMMIT;

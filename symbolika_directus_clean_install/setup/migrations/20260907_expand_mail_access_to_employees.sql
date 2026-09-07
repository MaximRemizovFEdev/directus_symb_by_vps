BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS symbolika_mail_folder_members (
  id bigserial PRIMARY KEY,
  folder_id bigint NOT NULL REFERENCES symbolika_mail_folders(id) ON DELETE CASCADE,
  employee integer NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  can_read boolean NOT NULL DEFAULT true,
  can_reply boolean NOT NULL DEFAULT false,
  can_send boolean NOT NULL DEFAULT false,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  UNIQUE (folder_id, employee)
);

CREATE INDEX IF NOT EXISTS symbolika_mail_folder_members_employee_idx
  ON symbolika_mail_folder_members(employee, folder_id);

-- Preserve the access which administrators, managing staff and managers had
-- through the old global is_shared flag. Future access is managed explicitly.
INSERT INTO symbolika_mail_folder_members (folder_id, employee, can_read, can_reply, can_send)
SELECT f.id, e.id, true, true, true
FROM symbolika_mail_folders f
CROSS JOIN employees e
JOIN directus_users u ON u.id = e.directus_user AND u.status = 'active'
JOIN directus_roles r ON r.id = u.role
WHERE f.is_active = true
  AND f.is_shared = true
  AND COALESCE(e.is_active, true) = true
  AND r.name IN ('Administrator', 'Управляющий', 'Менеджер')
ON CONFLICT (folder_id, employee) DO NOTHING;

-- Give every active employee with an active Directus account a private local
-- folder. IMAP folder and sender alias stay empty until an administrator maps
-- the actual corporate mailbox, so guessed folders are never synchronized.
INSERT INTO symbolika_mail_folders (
  slug, name, imap_name, alias_email, employee, is_shared, is_system, is_active, sort
)
SELECT
  'employee-' || e.id,
  COALESCE(NULLIF(e.full_name, ''), 'Сотрудник'),
  NULL,
  NULL,
  e.id,
  false,
  false,
  true,
  100 + e.id
FROM employees e
JOIN directus_users u ON u.id = e.directus_user AND u.status = 'active'
WHERE COALESCE(e.is_active, true) = true
  AND NOT EXISTS (
    SELECT 1 FROM symbolika_mail_folders current_folder
    WHERE current_folder.employee = e.id
  )
ON CONFLICT (slug) DO NOTHING;

COMMIT;

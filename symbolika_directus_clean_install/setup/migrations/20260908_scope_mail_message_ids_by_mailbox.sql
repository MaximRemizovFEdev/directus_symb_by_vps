BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- One physical email has the same RFC Message-ID in the sender's Sent folder
-- and in every recipient's Inbox. A global unique index caused a message that
-- had already been saved for one connected account to disappear from another.
DROP INDEX IF EXISTS symbolika_mail_messages_message_id_uidx;
DROP INDEX IF EXISTS symbolika_mail_messages_thread_message_id_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS symbolika_mail_messages_thread_message_id_uidx
  ON symbolika_mail_messages(thread_id, message_id);

COMMIT;

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Procurement is a self-contained workspace. It must not create, update or
-- require duplicate records in the general task tracker.
DROP TRIGGER IF EXISTS procurement_purchase_task_sync ON procurement_requests;
DROP TRIGGER IF EXISTS procurement_status_sync_from_task ON symbolika_tasks;

CREATE OR REPLACE FUNCTION ensure_procurement_batch_task(batch_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_procurement_purchase_task(request_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN;
END;
$$;

-- Keep procurement timestamps and the blank receipt flag, but do not drive
-- any task statuses and do not create payment or pickup tasks.
CREATE OR REPLACE FUNCTION sync_procurement_received_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'received' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE orders_items
    SET blank_ordered = true
    WHERE id = NEW.order_item
      AND NEW.request_type = 'blank';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_procurement_status_workflow_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received')
     AND NEW.ordered_at IS NULL THEN
    UPDATE procurement_requests
    SET ordered_at = now(),
        date_updated = now()
    WHERE id = NEW.id;
  END IF;

  IF NEW.status = 'received' THEN
    IF NEW.received_at IS NULL THEN
      UPDATE procurement_requests
      SET received_at = now(),
          date_updated = now()
      WHERE id = NEW.id;
    END IF;

    UPDATE orders_items
    SET blank_ordered = true
    WHERE id = NEW.order_item
      AND NEW.request_type = 'blank';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sync_procurement_batch_status_workflow_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  UPDATE procurement_requests
  SET status = NEW.status,
      ordered_at = CASE
        WHEN NEW.status IN ('ordered', 'ready_for_pickup', 'in_transit', 'received') THEN COALESCE(ordered_at, now())
        ELSE ordered_at
      END,
      received_at = CASE
        WHEN NEW.status = 'received' THEN COALESCE(received_at, now())
        ELSE received_at
      END,
      date_updated = now()
  WHERE procurement_batch = NEW.id
    AND status IS DISTINCT FROM NEW.status;

  RETURN NEW;
END;
$$;

-- The automation dashboard must no longer report a procurement request as
-- broken merely because it intentionally has no task.
CREATE OR REPLACE FUNCTION symbolika_skip_procurement_task_issue()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.issue_type IN ('procurement_without_task', 'completed_task_open_procurement') THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS symbolika_skip_procurement_task_issue_insert ON symbolika_automation_issues;
CREATE TRIGGER symbolika_skip_procurement_task_issue_insert
BEFORE INSERT ON symbolika_automation_issues
FOR EACH ROW
EXECUTE FUNCTION symbolika_skip_procurement_task_issue();

SELECT refresh_symbolika_automation_issues();

COMMIT;

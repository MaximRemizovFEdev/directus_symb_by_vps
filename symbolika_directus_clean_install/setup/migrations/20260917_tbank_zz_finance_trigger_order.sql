BEGIN;

-- PostgreSQL executes triggers of the same timing alphabetically. These
-- finalizers must run after the legacy financial triggers, otherwise the
-- legacy item calculation overwrites the acquiring fee deduction.
DROP TRIGGER IF EXISTS symbolika_apply_item_finance_totals ON orders_items;
DROP TRIGGER IF EXISTS zz_symbolika_apply_item_finance_totals ON orders_items;
CREATE TRIGGER zz_symbolika_apply_item_finance_totals
BEFORE INSERT OR UPDATE OF order_sum, total_cost, manager_commission_sum, tax_sum, acquiring_fee_sum, profit_sum, margin_percent
ON orders_items
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_item_finance_totals();

DROP TRIGGER IF EXISTS symbolika_apply_order_finance_totals ON orders;
DROP TRIGGER IF EXISTS zz_symbolika_apply_order_finance_totals ON orders;
CREATE TRIGGER zz_symbolika_apply_order_finance_totals
BEFORE INSERT OR UPDATE OF order_sum, items_total_cost, items_manager_commission_sum, items_tax_sum, acquiring_fee_sum, profit_sum, margin_percent
ON orders
FOR EACH ROW
EXECUTE FUNCTION symbolika_apply_order_finance_totals();

-- Re-save the calculated fee to pass affected rows through the final trigger.
UPDATE orders_items
   SET acquiring_fee_sum = acquiring_fee_sum
 WHERE acquiring_fee_sum <> 0;

UPDATE orders
   SET acquiring_fee_sum = acquiring_fee_sum
 WHERE acquiring_fee_sum <> 0;

COMMIT;

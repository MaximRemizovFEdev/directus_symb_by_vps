BEGIN;

CREATE TABLE IF NOT EXISTS symbolika_tbank_payments (
  id bigserial PRIMARY KEY,
  order_id integer NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  payment_id varchar(100) NOT NULL UNIQUE,
  payment_url text,
  amount numeric(14,2) NOT NULL,
  status varchar(40) NOT NULL DEFAULT 'NEW',
  order_payment_id integer UNIQUE REFERENCES order_payments(id) ON DELETE SET NULL,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS symbolika_tbank_payments_order_idx
  ON symbolika_tbank_payments(order_id, date_created DESC);

COMMIT;

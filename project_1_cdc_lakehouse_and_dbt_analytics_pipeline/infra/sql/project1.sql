-- project1.sql: init schema for CDC demo

CREATE TABLE IF NOT EXISTS public.users (
  user_id     BIGINT PRIMARY KEY,
  email       TEXT,
  status      TEXT,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.orders (
  order_id     BIGINT PRIMARY KEY,
  user_id      BIGINT NOT NULL REFERENCES public.users(user_id),
  order_ts     TIMESTAMPTZ,
  status       TEXT,
  total_amount NUMERIC(18,2),
  updated_at   TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.payments (
  payment_id     BIGINT PRIMARY KEY,
  order_id       BIGINT NOT NULL REFERENCES public.orders(order_id),
  amount         NUMERIC(18,2),
  status         TEXT,
  failure_reason TEXT,
  updated_at     TIMESTAMPTZ
);

DROP SCHEMA IF EXISTS lithepg_demo CASCADE;
CREATE SCHEMA lithepg_demo;

CREATE TABLE lithepg_demo.customers (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  plan text NOT NULL CHECK (plan IN ('free', 'pro', 'enterprise')),
  health_score integer NOT NULL CHECK (health_score BETWEEN 0 AND 100),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lithepg_demo.orders (
  id bigserial PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES lithepg_demo.customers(id),
  status text NOT NULL CHECK (status IN ('draft', 'paid', 'shipped', 'refunded')),
  total_cents integer NOT NULL CHECK (total_cents >= 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lithepg_demo.audit_events (
  id bigserial PRIMARY KEY,
  actor text NOT NULL,
  action text NOT NULL,
  target_table text NOT NULL,
  target_id text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  happened_at timestamptz NOT NULL DEFAULT now()
);

CREATE VIEW lithepg_demo.customer_revenue AS
SELECT
  c.id AS customer_id,
  c.name,
  c.plan,
  c.health_score,
  count(o.id) AS order_count,
  coalesce(sum(o.total_cents), 0) AS revenue_cents,
  max(o.created_at) AS last_order_at
FROM lithepg_demo.customers c
LEFT JOIN lithepg_demo.orders o ON o.customer_id = c.id
GROUP BY c.id, c.name, c.plan, c.health_score;

INSERT INTO lithepg_demo.customers (id, name, plan, health_score, created_at) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Acme Health', 'enterprise', 91, now() - interval '31 days'),
  ('22222222-2222-2222-2222-222222222222', 'Northwind Labs', 'pro', 76, now() - interval '18 days'),
  ('33333333-3333-3333-3333-333333333333', 'Luna Coffee', 'free', 44, now() - interval '7 days'),
  ('44444444-4444-4444-4444-444444444444', 'Sol Analytics', 'pro', 83, now() - interval '3 days');

INSERT INTO lithepg_demo.orders (customer_id, status, total_cents, metadata, created_at) VALUES
  ('11111111-1111-1111-1111-111111111111', 'paid', 129900, '{"region":"us-east","channel":"sales-led","priority":"high"}', now() - interval '6 days'),
  ('11111111-1111-1111-1111-111111111111', 'shipped', 249900, '{"region":"us-east","channel":"renewal","priority":"high"}', now() - interval '1 day'),
  ('22222222-2222-2222-2222-222222222222', 'paid', 49900, '{"region":"us-west","channel":"self-serve"}', now() - interval '4 days'),
  ('33333333-3333-3333-3333-333333333333', 'draft', 1900, '{"region":"caribbean","coupon":"starter"}', now() - interval '2 days'),
  ('44444444-4444-4444-4444-444444444444', 'refunded', 9900, '{"region":"eu","reason":"duplicate"}', now() - interval '12 hours'),
  ('44444444-4444-4444-4444-444444444444', 'paid', 29900, '{"region":"eu","channel":"self-serve"}', now() - interval '2 hours');

INSERT INTO lithepg_demo.audit_events (actor, action, target_table, target_id, details, happened_at) VALUES
  ('omar', 'seeded', 'customers', '11111111-1111-1111-1111-111111111111', '{"source":"dogfood"}', now() - interval '45 minutes'),
  ('system', 'invoice.paid', 'orders', '1', '{"provider":"stripe","latency_ms":84}', now() - interval '30 minutes'),
  ('boris', 'schema.refresh', 'customer_revenue', 'view', '{"client":"LithePG","mode":"visual-dogfood"}', now() - interval '10 minutes');

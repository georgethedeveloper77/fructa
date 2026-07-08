-- 0032_push_log.sql
-- Audit trail for every server-sent push: admin manual broadcasts (send-push),
-- the weekly digest, and (optionally) pipeline pushes. Written by the
-- service-role edge functions only; the admin reads it via its server client.
-- RLS is on with no anon/authenticated policy, so it never leaks to the app.

create table if not exists public.push_log (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null,
  target     text,                                   -- deep-link target: fund/<id> | markets | portfolio | alerts
  segment    text not null default 'all',            -- 'all' or '<tagKey>=<value>'
  sent_count int  not null default 0,                -- OneSignal recipients estimate
  status     text not null default 'sent' check (status in ('sent','error')),
  error      text,
  created_at timestamptz not null default now()
);

create index if not exists push_log_created_idx on public.push_log (created_at desc);

alter table public.push_log enable row level security;
-- Intentionally no policies: only the service-role edge functions + admin
-- server client (which uses the service role) reach this table.

comment on table public.push_log is
  'Audit of server-sent OneSignal pushes (admin broadcasts, weekly digest). Service-role only.';

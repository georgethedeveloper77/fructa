-- 0065_push_log_delivery.sql
-- push_log could not tell a real send from a send that reached nobody.
--
-- OneSignal answers HTTP 200 with a body of {"errors":["All included players
-- are not subscribed"]} and no notification id when a tag filter matches zero
-- devices. The old code read res.ok, saw true, and wrote status 'sent' with
-- sent_count 0. Every zero-delivery push therefore looked like a success in the
-- audit view, which is why "sometimes they arrive" was impossible to debug.
--
-- This adds the third status the system actually has, plus the provenance and
-- the OneSignal id needed to chase a single notification end to end.

alter table public.push_log
  add column if not exists source        text not null default 'admin',
  add column if not exists onesignal_id  text,
  add column if not exists subject_id    text;

-- The old constraint only knew 'sent' and 'error'.
alter table public.push_log drop constraint if exists push_log_status_check;

alter table public.push_log
  add constraint push_log_status_check
  check (status in ('sent', 'error', 'no_recipients'));

create index if not exists push_log_source_idx
  on public.push_log (source, created_at desc);

comment on column public.push_log.source is
  'Which function sent it: admin | rate_change | dividend | digest | market.';

comment on column public.push_log.onesignal_id is
  'OneSignal notification id. Null when the send never produced one, which is itself the tell.';

comment on column public.push_log.subject_id is
  'The fund/stock/sacco id the push was about, when it was about one.';

comment on column public.push_log.status is
  'no_recipients means OneSignal accepted the call and matched zero devices. That is a delivery failure, not a send, and it is the single most common failure in this system.';

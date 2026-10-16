-- 0081_wraps.sql
--
-- Stories, built on the server and kept.
--
-- Market stories (what moved, who led, how the market sits against the bill)
-- are the same for every user, so they are built once here, from approved
-- rates only, and kept for good: a day when something moved, every week,
-- month, quarter and year. The app reads the live ones from wraps.json in the
-- snapshots bucket, so a new user can browse weeks from before they joined.
--
-- Anything personal (holdings, statements, what a move means for you) is
-- never here. The app adds that layer on the phone.
--
-- Publishing is automatic. build-wraps runs every hour: it refreshes this
-- week's draft, publishes a day's stories when something crossed the
-- thresholds, publishes the week on Friday evening and sends the push, and
-- closes months, quarters and years as they end. Admin only steps in: edit a
-- story, hold a wrap, delete one, rebuild a period, tune the thresholds.
--
-- Why approved rates only: a scraped jump beyond the review tolerance waits in
-- rate_review and never reaches rate_history until approved, so reading
-- rate_history alone keeps an unapproved misread out of every story.

create table if not exists public.wraps (
  id            text primary key,              -- day-2026-10-16, week-2026-10-16, month-2026-09, quarter-2026-q3, year-2026
  period        text not null
                  check (period in ('day','week','month','quarter','year')),
  period_start  date not null,
  period_end    date not null,
  status        text not null default 'draft'
                  check (status in ('draft','live','held')),
  stories       jsonb not null default '[]'::jsonb,
  lead          text,                          -- the lead story's one line, for lists and the push
  edited        boolean not null default false, -- an operator changed the stories; rebuilds leave them alone
  built_at      timestamptz,
  published_at  timestamptz,
  pushed_at     timestamptz,
  updated_at    timestamptz not null default now()
);

create index if not exists wraps_period_end_idx
  on public.wraps (period, period_end desc);

alter table public.wraps enable row level security;

-- The app never queries this table directly (it reads wraps.json), but live
-- wraps are public facts about public rates, so reading them is harmless.
drop policy if exists wraps_public_read on public.wraps;
create policy wraps_public_read on public.wraps
  for select to anon, authenticated using (status = 'live');

comment on table public.wraps is
  'Market stories by period. Built and published by build-wraps; admin can edit, hold, delete or rebuild.';

-- ── Thresholds: what counts as a story ─────────────────────────────────────
-- Read by build-wraps on every run, so a change takes effect on the next run.
insert into public.app_config (key, value, description) values
  ('story.enabled',            'true'::jsonb, 'Build and publish wraps automatically'),
  ('story.daily_ratio',        '3'::jsonb,    'Daily: a move must be this many times the fund''s normal weekly move'),
  ('story.daily_min_move',     '0.25'::jsonb, 'Daily: smallest move, in points, that can be a story'),
  ('story.daily_max',          '3'::jsonb,    'Daily: most stories in a day'),
  ('story.weekly_max',         '8'::jsonb,    'Weekly and longer: most stories in a wrap'),
  ('story.repeat_weeks',       '3'::jsonb,    'Weeks before the same fund can lead the same story again'),
  ('story.breadth_min',        '8'::jsonb,    'Funds moving the same way that make a market-wide story'),
  ('story.weekly_publish_dow', '5'::jsonb,    'Weekly publish day, 0 Sunday to 6 Saturday, Nairobi time'),
  ('story.weekly_publish_hour','18'::jsonb,   'Weekly publish hour, Nairobi time'),
  ('story.weekly_push',        'true'::jsonb, 'Send the weekly push when the week publishes')
on conflict (key) do nothing;

-- ── Schedule ───────────────────────────────────────────────────────────────
-- Hourly, through the guarded invoker from 0048, so a missing vault secret
-- leaves a visible failure row. Every run is idempotent.
do $$
declare jid bigint;
begin
  for jid in select jobid from cron.job where command ilike '%build-wraps%' loop
    perform cron.unschedule(jid);
  end loop;
  -- The old Friday-morning digest is replaced by the weekly wrap push, which
  -- goes to the same digest_weekly tag with the week's real lead story.
  for jid in select jobid from cron.job where command ilike '%weekly-digest%' loop
    perform cron.unschedule(jid);
  end loop;
end $$;

select cron.schedule(
  'fructa-build-wraps',
  '7 * * * *',
  $$ select public.invoke_edge_function('build-wraps'); $$
);

-- Inspect:
--   select id, status, lead, built_at, published_at, pushed_at from public.wraps order by period_end desc limit 20;
--   select * from cron.job where jobname = 'fructa-build-wraps';

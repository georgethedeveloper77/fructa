-- 0073_fx_source.sql
--
-- The FX lane joins source_health, and source_health learns to carry a short
-- human note.
--
-- WHY A NOTE COLUMN. Open Exchange Rates caps the free plan at 1,000 requests a
-- month. Past that it stops answering and the daily rate silently freezes at
-- whatever it last was, which is the worst possible failure for this feature:
-- the currency card keeps rendering, keeps looking authoritative, and is
-- quietly stale. So the quota has to be visible in admin BEFORE it runs out.
--
-- OXR publishes usage.json for exactly this, and it is free and does not count
-- against the quota. But reading it needs the app_id, and the app_id lives in
-- Supabase function secrets. Giving the admin app its own copy would mean the
-- same secret in two places, rotated in two places, and eventually rotated in
-- one. So the aggregator reads usage.json on every run and writes the result
-- here as a string, and admin renders it. One secret, one home.
--
-- `note` is generic on purpose. Any source with something short worth saying
-- can use it: a quota, a plan tier, a deprecation date.

alter table public.source_health add column if not exists note text;

comment on column public.source_health.note is
  'Short operator-facing status from the last run, e.g. an API quota readout. Display only, never parsed.';

-- The FX sources. Both are seeded so a failure has somewhere to land on the
-- very first run rather than creating a row nobody expected.
--
-- openexchangerates  primary. Needs OXR_APP_ID in Supabase secrets.
-- open-er-api        keyless fallback. No account, no quota, no support.
--
-- Note what is NOT here: the old CBK page scrape. Its parse was a heuristic
-- that found the US DOLLAR row and took the first plausible looking number,
-- and the comment in cbk-fx.ts said as much. A number that arrives by guessing
-- is worse than no number, because it cannot be told apart from a real one.
-- CBK history still enters through the CSV backfill, which is exact.
insert into public.source_health (source)
values ('openexchangerates'), ('open-er-api')
on conflict (source) do nothing;

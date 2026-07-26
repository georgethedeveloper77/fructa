-- 0077_llm_spend.sql
--
-- A kill switch and a hard monthly cap on every LLM call the project makes.
--
--
-- WHY THIS EXISTS
--
-- Not because the extraction is expensive. It is not: a fact sheet costs about
-- six cents, most managers publish quarterly, and the whole corpus of roughly a
-- hundred funds comes to something like twenty five dollars a YEAR.
--
-- It exists because twenty five dollars a year and four hundred dollars a year
-- are separated by a single bug. A retry loop, a schedule that re-reads
-- unchanged PDFs, one forty-page annual report fed in by accident. The cost is
-- fine; the VARIANCE is not, and an app with no revenue cannot absorb a
-- surprise.
--
-- So the guard is a hard ceiling checked before every call, plus a switch that
-- stops everything, plus a ledger that makes the spend visible rather than
-- discovered on a statement.
--
-- Deliberately project-wide rather than fact-sheet-specific. The same API key
-- will be used for whatever comes next, and a second feature must draw from
-- the same budget rather than quietly open a second one.


create table if not exists public.llm_spend (
  id            bigserial primary key,

  -- What the call was for: 'factsheet', and whatever comes later. The cap is
  -- shared, so this is for attribution rather than for separate budgets: when
  -- a month runs hot, the question is which feature did it.
  purpose       text not null,

  model         text not null,
  input_tokens  int  not null default 0,
  output_tokens int  not null default 0,

  -- Cost in CENTS, integer. Not a float and not dollars.
  --
  -- Fractions of a cent accumulate, and a running total that drifts is a
  -- running total nobody trusts. Integer cents at these volumes cannot drift,
  -- and rounding each call UP means the ledger errs toward stopping early
  -- rather than toward overspending.
  cents         int  not null default 0,

  ok            boolean not null default true,
  error         text,
  ref           text,             -- fund id, import id, whatever identifies it
  created_at    timestamptz not null default now()
);

comment on table public.llm_spend is
  'One row per LLM call, successful or not. Failed calls are logged too: a '
  'retry loop that fails every time still costs money, and a ledger that only '
  'records successes is blind to exactly the failure mode worth catching.';

create index if not exists llm_spend_month_idx on public.llm_spend (created_at desc);
create index if not exists llm_spend_purpose_idx on public.llm_spend (purpose, created_at desc);


-- ── Month-to-date spend, the number the guard checks ───────────────────────

create or replace view public.llm_spend_mtd as
select
  coalesce(sum(cents), 0)::int          as cents,
  count(*)::int                          as calls,
  count(*) filter (where not ok)::int    as failed,
  date_trunc('month', now())             as since
from public.llm_spend
where created_at >= date_trunc('month', now());


-- ── The switch and the ceiling ─────────────────────────────────────────────
--
-- In app_config so both are editable in admin without a deploy, which matters:
-- the moment you want to stop spending is not the moment to be waiting on a
-- build.
--
-- The cap defaults to 500 cents, five dollars a month. That is roughly twice
-- what the whole quarterly corpus should ever cost in its heaviest month, so it
-- will never bind in normal use and will stop a runaway within about eighty
-- calls.

insert into public.app_config (key, value) values
  ('llm.enabled',
   '{"on":true,"note":"Master switch for every LLM call in the project. Off means calls are refused before the API is reached, not after."}'::jsonb),
  ('llm.monthly_cap_cents',
   '{"cents":500,"note":"Hard ceiling on month-to-date spend across all purposes. A call that would exceed it is refused."}'::jsonb)
on conflict (key) do nothing;


-- ── What this deliberately does NOT do ─────────────────────────────────────
--
-- It does not schedule anything. Phase 3 was going to be a weekly cron that
-- walked every source; it should not be, and this table is part of the reason.
-- A schedule spends money while nobody is watching, and the whole point of the
-- pre-filter and the review gate is that a human is in the loop anyway.
--
-- The version worth building instead costs nothing to run: a CHECK that fetches
-- each source, hashes the PDF, compares against last_seen_sha, and writes a
-- list of what changed. No model, no tokens. You open admin, see "four new
-- sheets", and extract the ones you want. The expensive step stays behind a
-- click, forever.
--
-- Verify:
--
--   select * from public.llm_spend_mtd;
--   select purpose, count(*), sum(cents) from public.llm_spend
--   where created_at >= date_trunc('month', now()) group by 1;

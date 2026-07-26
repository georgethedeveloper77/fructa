-- 0078_factsheet_recipes.sql
--
-- Phase 3, rebuilt around a constraint: the model is the LAST option, not the
-- first, and it never runs on a schedule.
--
--
-- THREE TIERS, AND ONLY THE LAST ONE COSTS ANYTHING
--
--   1. DISCOVERY. Fetch the PDF, hash it, compare to what we saw last time.
--      Free. Answers "has anything changed" without reading a word.
--
--   2. ANCHORS. Pull the text layer and read labelled values out of it using a
--      recipe stored per manager. Free. Works because a fact sheet is mostly a
--      label-value table: "Minimum Investment: KES 250,000" is trivially
--      machine-readable once you know the label to look for.
--
--   3. THE MODEL. Six cents, behind a click, never scheduled.
--
-- The recipe is what makes tier 2 possible, and the reason it is safe is not
-- that it is reliable. It is not: a manager redesigns a sheet and the anchors
-- miss. It is safe because it is VERIFIABLE. Anchor output goes through the
-- same validator as model output, so a stale recipe produces validation errors
-- rather than wrong numbers, and the fallback is a button rather than a
-- silently bad import.
--
-- A recipe is written once per manager, either by hand or by reading back a
-- successful model extraction, and then serves every sheet that manager
-- publishes until they change their layout. Madison publishes monthly: pay for
-- January, get February to December free.


-- ── The recipe ─────────────────────────────────────────────────────────────

alter table public.factsheet_sources
  add column if not exists recipe jsonb,
  add column if not exists recipe_learned_at timestamptz,
  add column if not exists recipe_fail_count int not null default 0;

comment on column public.factsheet_sources.recipe is
  'How to read this manager''s layout without a model. Shape:

   {
     "as_of":  { "pattern": "FACT SHEET\\\\s+([A-Za-z]+\\\\s+\\\\d{4})" },
     "basis":  { "value": "yield" },
     "net_of": { "value": "fees" },
     "rate":   { "after": "Effective yield:",        "kind": "percent" },
     "terms":  {
       "min_invest":     { "after": "Minimum Investment:", "kind": "money" },
       "lock_in_months": { "after": "Lock in Period",      "kind": "months" }
     },
     "exclude": ["targets a return of", "Annualized", "Benchmark"]
   }

   `exclude` is the part that cannot be inferred from layout and must be
   learned per manager: which labels on THIS sheet sit above a number that is
   not a return. Oak prints "targets a return of 20%"; Dry Associates prints a
   gross-before-bonus column; every sheet prints its benchmark. A recipe
   without an exclude list will fail validation, which is the intended
   outcome.';

comment on column public.factsheet_sources.recipe_fail_count is
  'Consecutive anchor runs that failed validation. Three in a row means the '
  'manager has redesigned and the recipe needs relearning; the app stops '
  'trying the free path and goes straight to offering the model.';


-- ── What discovery found, and what it cost (nothing) ───────────────────────

create table if not exists public.factsheet_checks (
  id          bigserial primary key,
  source_id   text references public.factsheet_sources (id) on delete cascade,
  url         text,
  http_status int,
  pdf_sha256  text,
  changed     boolean not null default false,
  detected_as_of date,
  pages       int,
  -- Which tier resolved it, so the ledger shows how often the free path won.
  outcome     text check (outcome in
    ('unchanged', 'new', 'anchored', 'needs_model', 'error', 'not_found')),
  note        text,
  created_at  timestamptz not null default now()
);

comment on table public.factsheet_checks is
  'One row per source per discovery run. Costs nothing to produce and exists to '
  'answer the only question that matters before spending: which sheets changed. '
  'Also the record of how often the anchor path succeeded, which is how you '
  'decide whether recipes are worth maintaining at all.';

create index if not exists factsheet_checks_source_idx
  on public.factsheet_checks (source_id, created_at desc);


-- ── Constructible URLs ─────────────────────────────────────────────────────
--
-- Some managers name fact sheets predictably enough that discovery can build
-- the URL for a month rather than scraping a listing page for it. Cytonn is the
-- clearest: chyf-fact-sheet-{mon}-{yy}.pdf, confirmed across five months and
-- three years.
--
-- Tokens: {mon} lowercase three-letter month, {yy} two-digit year, {yyyy} four,
-- {q} quarter number.

alter table public.factsheet_sources
  add column if not exists url_template text;

comment on column public.factsheet_sources.url_template is
  'Optional constructible URL, e.g. '
  'https://cytonn.com/uploads/downloads/chyf-fact-sheet-{mon}-{yy}.pdf. '
  'Discovery walks backwards from the current month until one returns a PDF, '
  'so a manager who is two months late is still found without a listing page.';

update public.factsheet_sources set
  url_template = 'https://cytonn.com/uploads/downloads/chyf-fact-sheet-{mon}-{yy}.pdf',
  cadence      = 'monthly'
where id = 'cytonn-chyf' and url_template is null;


-- ── The switch that keeps this honest ──────────────────────────────────────
--
-- Discovery may run on a schedule because it costs nothing. Extraction may not,
-- and this is belt and braces alongside llm.enabled: even with a budget left,
-- nothing automated may call the model.

insert into public.app_config (key, value) values
  ('factsheet.discovery_enabled',
   '{"on":true,"note":"Free. Fetches and hashes fact sheets to see what changed. No model, no cost."}'::jsonb),
  ('factsheet.auto_extract',
   '{"on":false,"note":"Leave OFF. When off, discovery only ever produces a LIST and a human clicks to spend. Turning this on lets a schedule call the model."}'::jsonb)
on conflict (key) do nothing;


-- ── After applying ─────────────────────────────────────────────────────────
--
--   select s.id, s.cadence, s.recipe is not null as has_recipe,
--          s.recipe_fail_count, s.last_checked_at, s.last_error
--   from   public.factsheet_sources s where s.active order by s.id;
--
--   select outcome, count(*) from public.factsheet_checks
--   where created_at > now() - interval '30 days' group by 1;
--
-- The second query is the one that decides whether tier 2 pays for itself. If
-- `anchored` dominates, recipes are worth maintaining. If `needs_model` does,
-- they are not, and the honest move is to delete the recipes and accept six
-- cents a sheet rather than maintain forty parsers that never fire.

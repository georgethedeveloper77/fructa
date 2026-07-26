-- 0076_factsheet_imports.sql
--
-- Phase 1 of the fact sheet pipeline: the staging table and the review gate.
-- No automation. Nothing in this migration fetches, parses or writes a fund.
--
--
-- WHY A GATE RATHER THAN A SCRAPER
--
-- Extracting numbers from these PDFs is the easy half. The hard half is that
-- the numbers are heterogeneous in MEANING, and a pipeline that grabs the
-- largest figure on the page would have published, in one week:
--
--   MansaX          18.96%  a quarter multiplied by four
--   Oak             20.00%  a target, captioned "not a guarantee"
--   Lofty Global    25.00%  a target, captioned "absolute gross return benchmark"
--   Dry Associates  16.18%  gross, before a bonus that removes a third of it
--   Old Mutual      13.40%  correct, and fifteen months old
--
-- Five funds, five wrong headlines, each defensible in isolation and each one
-- a lie on a screen. Every one of them was caught by a human reading the
-- caption ABOVE the number rather than the number.
--
-- So the schema below is built around one idea: a figure may not enter the app
-- without the words the manager printed next to it. `payload` carries a
-- `caption` per figure and the review UI shows it. A target cannot be laundered
-- into a return if the word "target" travels with it.


-- ── The staging table ──────────────────────────────────────────────────────

create table if not exists public.factsheet_imports (
  id           bigserial primary key,

  -- Nullable. An extraction can arrive before anyone knows which row it belongs
  -- to, and forcing a guess at insert time is how a Shariah fund's returns end
  -- up on its conventional sibling. The reviewer assigns it.
  fund_id      text references public.funds (id) on delete set null,

  source_url   text,
  source_label text not null,        -- 'MansaX Special Fund Q1 2026'

  -- The sheet's OWN date, not the date it was fetched.
  --
  -- This is the field that stops the Old Mutual mistake. A fact sheet is
  -- authoritative as at its own date and no later, so an import may only be
  -- applied when it is newer than what the fund already holds. Fetching an
  -- April 2025 PDF in July 2026 does not make its yield current.
  as_of        date not null,

  payload      jsonb not null,
  status       text not null default 'pending'
    check (status in ('pending', 'applied', 'rejected', 'superseded')),

  -- 0 to 1, from the extractor. Low confidence does not block anything; it
  -- sorts the queue, so the doubtful ones get read first rather than last.
  confidence   numeric,

  -- Dedupe. The same PDF re-fetched on a schedule must not queue twice.
  pdf_sha256   text,

  notes        text,                 -- reviewer's words, kept after applying
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz,
  reviewed_by  text
);

comment on table public.factsheet_imports is
  'One extracted fact sheet, staged for human review. NOTHING here reaches the '
  'app until a reviewer applies it: this table is the boundary between what a '
  'machine read off a PDF and what Fructa tells a person about their money.';

create unique index if not exists factsheet_imports_sha_idx
  on public.factsheet_imports (pdf_sha256) where pdf_sha256 is not null;

create index if not exists factsheet_imports_queue_idx
  on public.factsheet_imports (status, created_at desc);

create index if not exists factsheet_imports_fund_idx
  on public.factsheet_imports (fund_id, as_of desc);


-- ── The payload contract ───────────────────────────────────────────────────
--
-- Documented here rather than in a TypeScript type because this table outlives
-- any one extractor, and a reviewer reading a five year old row needs to know
-- what its shape meant.
--
-- {
--   "fund":    { "name": "...", "currency": "KES", "manager": "..." },
--
--   "basis":   { "value": "return",
--                "caption": "Q1 2026 net returns of 4.74%",
--                "reason": "quarterly realized return, not an annual yield" },
--
--   "net_of":  { "value": "fees",
--                "caption": "24-MONTH RETURN AFTER FEES" },
--
--   "terms":   { "min_invest":     { "value": 250000, "caption": "Minimum Investment: KES 250,000" },
--                "lock_in_months": { "value": 6,      "caption": "Initial Lock-in Period: 6 Months" },
--                "mgmt_fee":       { "value": 5.00,   "caption": "Financial Services Charges: 5% p.a. pro rated" } },
--
--   "periods": [ { "period_end": "2026-03-31", "period": "quarter",
--                  "net_pct": 4.74, "gross_pct": null,
--                  "caption": "Q1 2026 - 4.74%" } ],
--
--   "rates":   [ { "as_of": "2026-05-31", "rate": 11.61,
--                  "caption": "May-26 11.61%" } ],
--
--   "excluded": [ { "value": 18.96,
--                   "caption": "Q1 Annualized Net Return",
--                   "reason": "one quarter extrapolated to a year" },
--                 { "value": 20.00,
--                   "caption": "targets a return of 20% net of fees",
--                   "reason": "target, not a realized return" } ]
-- }
--
-- EVERY FIGURE CARRIES ITS CAPTION. Not for provenance, though it serves that
-- too: for review. A reviewer approving "4.74%" is guessing. A reviewer
-- approving "4.74%, captioned Q1 2026" is deciding.
--
-- `excluded` is REQUIRED, and an empty array is a claim rather than a default.
-- It is the extractor stating which numbers it saw and chose not to use, which
-- is the only way to tell "this sheet had no target" from "the extractor missed
-- the target". Every sheet reviewed so far has had at least one entry.


-- ── Where the PDFs come from (Phase 3 uses this; Phase 1 only reads it) ─────

create table if not exists public.factsheet_sources (
  id            text primary key,        -- 'sib-mansax', 'etica-uttf'
  company_id    text references public.companies (id) on delete cascade,

  -- A page that LISTS fact sheets, and/or a stable direct link. Most managers
  -- have one or the other; a few change the filename every quarter, which is
  -- why the listing page and a link pattern both exist.
  listing_url   text,
  direct_url    text,
  link_pattern  text,                    -- regex against hrefs on listing_url

  cadence       text check (cadence in ('monthly', 'quarterly', 'annual', 'irregular')),
  active        boolean not null default true,

  last_checked_at timestamptz,
  last_seen_sha   text,
  last_error      text,

  notes         text
);

comment on table public.factsheet_sources is
  'Per-manager fact sheet locations. Phase 3 walks this weekly, hashes what it '
  'finds and enqueues anything new into factsheet_imports. Phase 1 only needs '
  'the table to exist so sources can be recorded as they are discovered by hand.';


-- ── The guard that makes the gate mean something ───────────────────────────
--
-- An import may only be applied when it is at least as new as what the fund
-- already holds. Enforced in the writer rather than as a constraint, because
-- the reviewer must be able to see and reject a stale import rather than have
-- it silently fail to insert.
--
-- This view is what the review page reads to warn on one.

create or replace view public.factsheet_import_queue as
select
  i.id,
  i.fund_id,
  f.name          as fund_name,
  f.currency,
  f.basis         as current_basis,
  f.current_rate  as current_rate,
  f.net_of        as current_net_of,
  i.source_label,
  i.as_of,
  i.status,
  i.confidence,
  i.created_at,
  -- The proposed basis, lifted out of the payload so the queue can show a
  -- change of KIND without opening each row. A basis change is the single
  -- highest-consequence edit in this system and should be visible from a list.
  i.payload #>> '{basis,value}' as proposed_basis,
  -- True when the fund already holds something newer than this sheet.
  exists (
    select 1 from public.rate_history r
    where r.fund_id = i.fund_id and r.as_of > i.as_of
  ) as fund_has_newer_rate,
  -- True when this fund is hand-maintained and the pipeline should keep off it.
  f.source_type = 'manual' as fund_is_manual
from public.factsheet_imports i
left join public.funds f on f.id = i.fund_id;

comment on view public.factsheet_import_queue is
  'The review list. Carries the two warnings a reviewer must not have to go '
  'looking for: whether the fund already holds a newer figure than this sheet, '
  'and whether the fund is hand-maintained.';


-- ── Seed the sources already known from this thread ────────────────────────
--
-- Recorded now so Phase 3 has something real to walk rather than a table
-- someone has to populate from memory later.

insert into public.factsheet_sources (id, company_id, listing_url, cadence, notes)
select v.id, f.company_id, v.url, v.cadence, v.notes
from (values
  ('sib-mansax',     'standard-investment-trust-fund-sp-kes', 'https://www.sib.co.ke',             'quarterly', 'MansaX KES and USD in one sheet; Shariah pair published separately'),
  ('etica-uttf',     'etica-sp-kes',                          'https://www.eticacap.com',          'monthly',   'All Etica funds in one deck, one slide each'),
  ('faida-oak',      'faida-sp-kes',                          'https://www.oak.africa',            'quarterly', 'Sept 2025 sheet was the newest found; ask oak@fib.co.ke for current'),
  ('lofty-corban',   'lofty-corban-sp-kes',                   'https://www.loftycorban.com',       'quarterly', 'Six funds in one deck'),
  ('madison-im',     'madison-sp-kes',                        'https://www.madison.co.ke/investmentmanagers', 'monthly', 'One sheet per fund per month'),
  ('dry-associates', 'dry-associates-sp-kes',                 'https://www.dryassociates.com',     'monthly',   'Dense single page; two yields printed, header one is net'),
  ('african-alliance','african-alliance-kenya-sp-kes',        'https://www.africanallianceassetmanagement.com', 'monthly', 'Three pages; trailing block is fund AND benchmark per horizon'),
  ('cic-am',         'cic-sp-kes-global-balanced',            'https://ke.cicinsurancegroup.com',  'monthly',   'One sheet per fund'),
  ('old-mutual-k',   'old-mutual-sp-kes',                     'https://www.oldmutual.co.ke',       'quarterly', 'Booklet covering every fund; April 2025 was the newest found'),
  ('arvocap',        'arvocap-sp-kes',                        'https://www.arvocap.com',           'irregular', 'KIIDs only so far, which carry terms and no performance')
) as v(id, fund_ref, url, cadence, notes)
join public.funds f on f.id = v.fund_ref
on conflict (id) do nothing;


-- ── After applying ─────────────────────────────────────────────────────────
--
--   select * from public.factsheet_import_queue where status = 'pending';
--
-- Phase 1 is finished when a payload can be pasted into admin, reviewed against
-- the live row, and applied by a field-scoped writer that touches only the
-- columns the payload carries. The writer must refuse when fund_is_manual, and
-- warn but not refuse when fund_has_newer_rate, because a stale sheet can still
-- carry good static terms; that is exactly what happened with Old Mutual, where
-- the yield was useless and the minimum investment was a twentyfold correction.

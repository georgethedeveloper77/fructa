-- 0054_saccos.sql
-- SASRA-regulated SACCO societies.
--
-- Scope notes:
--   * `saccos` are co-operative societies. They are NOT `companies` (fund
--     managers / insurers) and NOT `stocks`. No FK between them.
--   * A SACCO carries TWO rates, not one, and they are paid on two different
--     pots of money:
--       - interest_on_deposits       paid on member savings (the large pot)
--       - dividend_on_share_capital  paid on member shares  (the small, capped pot)
--     The app ranks SACCOs on interest_on_deposits ONLY. The dividend is always
--     rendered as a separately labelled chip. Never surface a bare percentage.
--   * Deposits are not withdrawable while a member remains a member. Every
--     SACCO row published to the app carries a lock flag so it can sit beside a
--     money market yield honestly.
--   * No scraper. Rates come from AGM declarations and audited annual
--     statements, imported once a year (Jan to April). Institution figures come
--     from the SASRA Sacco Supervision Annual Report (published by 31 October).
--     The licence register is published by SASRA each February.
--   * Withholding tax on co-operative dividends and on co-operative deposit
--     interest is NOT encoded here and is NOT applied in the app. See
--     app_config key saccos.tax_confirmed.

-- ---------------------------------------------------------------------------
-- saccos
-- ---------------------------------------------------------------------------
create table if not exists public.saccos (
  id                      text primary key,            -- slug, e.g. 'tower-sacco'
  name                    text not null,               -- verbatim from the SASRA register
  display_name            text,                        -- short form for tiles, e.g. 'Tower Sacco'

  -- regulation
  licence_class           text not null default 'dt',  -- 'dt' | 'nwdt' | 'credit_only'
  sasra_licensed_until    date,
  tier                    integer,                     -- 1, 2 or 3, from the supervision report

  -- membership
  common_bond             text not null default 'unknown', -- 'open' | 'closed' | 'unknown'
  bond_note               text,                        -- e.g. 'University of Nairobi staff'

  -- location
  county                  text,
  physical_location       text,
  postal_address          text,
  branches                integer,

  -- contact
  website                 text,
  phone                   text,
  email                   text,

  -- brand
  logo_url                text,                        -- logos bucket, public
  brand_color             text,                        -- hex, nullable

  -- joining terms (from the SACCO's own published terms)
  registration_fee_kes    numeric(12,2),
  min_share_capital_kes   numeric(14,2),
  min_monthly_deposit_kes numeric(12,2),
  loan_multiple           numeric(4,1),                -- borrow up to Nx your deposits
  deposit_notice_days     integer,                     -- notice to get deposits back on exit
  has_fosa                boolean,                     -- runs a front office (withdrawable) counter

  -- institution figures (from the SASRA supervision report)
  total_assets_kes        numeric(18,2),
  deposits_kes            numeric(18,2),
  members                 integer,
  registered_year         integer,
  financials_as_of        date,                        -- the report year these figures belong to

  about                   text,                        -- one paragraph, plain text
  active                  boolean not null default true,
  sort_order              integer,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint saccos_licence_class_ck
    check (licence_class in ('dt', 'nwdt', 'credit_only')),
  constraint saccos_common_bond_ck
    check (common_bond in ('open', 'closed', 'unknown'))
);

create index if not exists saccos_active_idx  on public.saccos (active);
create index if not exists saccos_class_idx   on public.saccos (licence_class);
create index if not exists saccos_bond_idx    on public.saccos (common_bond);
create index if not exists saccos_county_idx  on public.saccos (county);

comment on table public.saccos is
  'SASRA-regulated SACCO societies. Seeded from the SASRA licence register. Rates live in sacco_rates.';
comment on column public.saccos.licence_class is
  'dt = deposit-taking (Schedule I). nwdt = non-deposit-taking, BOSA only (Schedule II). credit_only = restricted licence (Schedule III), must never be published to the app.';
comment on column public.saccos.common_bond is
  'open = anyone may join. closed = restricted to an employer or institution. unknown = not yet confirmed, treat as not joinable in the UI.';
comment on column public.saccos.loan_multiple is
  'How many times your deposits you may borrow. This is why deposits are locked.';
comment on column public.saccos.deposit_notice_days is
  'Notice period before deposits are refunded after a member resigns. Null means unconfirmed.';

-- ---------------------------------------------------------------------------
-- sacco_rates
-- One row per SACCO per financial year. Declared at the AGM.
-- ---------------------------------------------------------------------------
create table if not exists public.sacco_rates (
  id                        uuid primary key default gen_random_uuid(),
  sacco_id                  text not null references public.saccos (id) on delete cascade,
  financial_year            integer not null,          -- the year ENDED, e.g. 2025

  interest_on_deposits      numeric(6,3),              -- percent, e.g. 13.000
  dividend_on_share_capital numeric(6,3),              -- percent, e.g. 20.000

  declared_on               date,                      -- AGM date, if known
  source_url                text,
  source_doc                text,                      -- e.g. 'Audited financial statements FY2025'

  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint sacco_rates_unique
    unique (sacco_id, financial_year),
  constraint sacco_rates_present_ck
    check (interest_on_deposits is not null or dividend_on_share_capital is not null),
  constraint sacco_rates_range_ck
    check (
      (interest_on_deposits is null or (interest_on_deposits >= 0 and interest_on_deposits <= 100))
      and
      (dividend_on_share_capital is null or (dividend_on_share_capital >= 0 and dividend_on_share_capital <= 100))
    )
);

create index if not exists sacco_rates_sacco_year_idx
  on public.sacco_rates (sacco_id, financial_year desc);

comment on table public.sacco_rates is
  'Rates declared at the annual general meeting. One row per SACCO per financial year. interest_on_deposits is the ranked rate. dividend_on_share_capital is display only.';
comment on column public.sacco_rates.financial_year is
  'The financial year that ENDED. A rate declared at a March 2026 AGM for the year ended 31 December 2025 is financial_year = 2025.';

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- touch_updated_at() already exists from 0047_stocks.sql.
-- ---------------------------------------------------------------------------
drop trigger if exists saccos_touch on public.saccos;
create trigger saccos_touch
  before update on public.saccos
  for each row execute function public.touch_updated_at();

drop trigger if exists sacco_rates_touch on public.sacco_rates;
create trigger sacco_rates_touch
  before update on public.sacco_rates
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- The app reads the published snapshot, never these tables directly.
-- Admin and edge functions use the service role, which bypasses RLS.
-- So: enable RLS with no permissive policy = deny by default to anon.
-- ---------------------------------------------------------------------------
alter table public.saccos      enable row level security;
alter table public.sacco_rates enable row level security;

-- ---------------------------------------------------------------------------
-- Config gates
-- ---------------------------------------------------------------------------

-- Master switch. Stays false until at least one SACCO has a sourced rate.
insert into public.app_config (key, value)
values ('saccos.enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Whether SACCO rows may appear in the All league table alongside funds and
-- T-bills. Independent of saccos.enabled so the tab can ship before the merge.
insert into public.app_config (key, value)
values ('saccos.in_all_tab', 'false'::jsonb)
on conflict (key) do nothing;

-- Only SACCOs with common_bond = 'open' are shown by default. When false, the
-- app shows closed and unknown bonds too, marked as not joinable.
insert into public.app_config (key, value)
values ('saccos.open_bond_only_default', 'true'::jsonb)
on conflict (key) do nothing;

-- The honesty line. Rendered above the All list whenever a SACCO outranks a fund.
insert into public.app_config (key, value)
values (
  'saccos.access_disclaimer',
  '"A SACCO pays more, but your money is locked until you leave the SACCO. A money market fund pays less and returns your money in two working days."'::jsonb
)
on conflict (key) do nothing;

-- Gate on net-of-tax display. Withholding on co-operative dividends and on
-- co-operative deposit interest is not yet confirmed. While this is false the
-- app shows gross rates only and never a net-of-tax figure for a SACCO.
insert into public.app_config (key, value)
values ('saccos.tax_confirmed', 'false'::jsonb)
on conflict (key) do nothing;

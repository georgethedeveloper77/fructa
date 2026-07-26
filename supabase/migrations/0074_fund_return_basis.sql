-- 0074_fund_return_basis.sql
--
-- The fourth basis.
--
-- 0023 gave funds three ways of quoting a number: yield, nav, none. That was
-- correct for what the app held at the time. It is not enough for a special
-- fund, and the gap is not cosmetic.
--
-- A money market fund quotes an ANNUAL YIELD: forward looking, effective,
-- positive by construction, and legitimate to compound.
-- A bond or equity fund quotes a UNIT PRICE: return is price movement.
-- A special fund quotes NEITHER. MansaX prints 4.74% and Etica Special Multi
-- Asset prints 5.23%, and both are REALIZED RETURNS FOR A CLOSED QUARTER.
-- Backward looking. Can be negative. Does not annualise honestly.
--
-- Today those funds carry basis='none' and the app either shows nothing or,
-- worse, treats the number as a yield: deducting withholding tax from a figure
-- the manager already published net of tax, and compounding a single quarter
-- across a two year projection. Both of those are live on the Etica Special
-- Multi Asset page right now.
--
-- This migration adds basis='return' and the three facts the app needs before
-- it can render one honestly: what period the number covers, what has already
-- been deducted from it, and the series of past periods behind it.
--
-- NOTE ON NUMBERING: confirm 0074 is free with `supabase migration list`
-- before `db push`. Prefixes 0020, 0024, 0054, 0061, 0063 and 0064 are absent
-- from the repo, so the sequence is not dense and the next free number is not
-- necessarily the last one plus one.


-- ── 1. basis gains 'return' ────────────────────────────────────────────────
--
-- The constraint from 0023 is named by Postgres convention. Dropping by name
-- with `if exists` is safe if it was ever created inline or renamed by hand.

alter table public.funds drop constraint if exists funds_basis_check;

alter table public.funds
  add constraint funds_basis_check
  check (basis is null or basis in ('yield', 'nav', 'return', 'none'));

comment on column public.funds.basis is
  'How this fund quotes its headline number, and therefore what the app is '
  'allowed to do with it. yield = forward-looking effective annual yield, '
  'compoundable, sortable, taxable. nav = unit price, return is price movement, '
  'never compounded, never taxed. return = a realized return for a CLOSED '
  'period, backward-looking, may be negative, never annualised by the app. '
  'none = nothing publishable.';


-- ── 2. What has already been taken out of the number ───────────────────────
--
-- This is the field that stops the app taxing a number twice.
--
-- Etica's MMF disclaimer: "net of fees and gross of withholding tax". So the
-- app deducts 15% and shows a net figure. Correct.
-- Etica's Special Multi Asset disclaimer: "net yield (Net of all fees and
-- taxes)". The app deducts 15% again. Wrong, and it publishes a number the
-- manager never quoted.
--
-- The value names what is ALREADY DEDUCTED, so the rule in tax.dart reads
-- directly off the field: apply withholding tax only when net_of = 'fees'.

alter table public.funds
  add column if not exists net_of text
    check (net_of is null or net_of in ('nothing', 'fees', 'fees_and_tax'));

comment on column public.funds.net_of is
  'What is already deducted from the quoted number. nothing = raw gross, before '
  'fees and before tax. fees = net of fees, GROSS OF WITHHOLDING TAX, which is '
  'the Kenyan unit trust convention and the default for every MMF. '
  'fees_and_tax = net of both, so the app must NOT deduct tax again. Null is '
  'treated as ''fees'' for backwards compatibility, but set it explicitly on '
  'anything that is not an MMF.';

-- Every fund quoting a yield today is quoting the Kenyan convention: after the
-- manager's fee, before KRA's withholding tax. That is precisely what the app
-- already assumes, so this backfill changes no rendered number. It only makes
-- the assumption explicit so the exceptions can be recorded against it.
update public.funds
set    net_of = 'fees'
where  net_of is null
  and  basis = 'yield';


-- ── 3. What period the headline number covers ──────────────────────────────
--
-- A yield needs no period: it is per annum by definition. A realized return is
-- meaningless without one. 4.74% over a quarter and 4.74% over a year are not
-- the same fact, and a bare percentage on a tile cannot be told apart.

alter table public.funds
  add column if not exists return_period text
    check (return_period is null or return_period in
      ('month', 'quarter', 'half', 'year', 'ytd', 'since_inception'));

alter table public.funds
  add column if not exists return_as_of date;

comment on column public.funds.return_period is
  'The period the headline return covers, for basis=''return'' funds. Drives the '
  'hero label, so the app can never print a quarterly figure where an annual one '
  'is assumed. Null on yield and nav funds.';

comment on column public.funds.return_as_of is
  'End date of the period in return_period. Distinct from returns_as_of (0027), '
  'which stamps the trailing 1y/3y/5y block from a monthly fact sheet.';


-- ── 4. The fee is not always a management fee ──────────────────────────────
--
-- MansaX charges a 5% p.a. "financial services charge" plus 10% of anything
-- above a 25% hurdle. Storing 5.00 in mgmt_fee and labelling it "Management
-- fee" is wrong on the label and silent on the larger of the two charges. A
-- fund returning 30% in a year hands back half a point of that under the
-- performance charge, and today the app cannot say so.

alter table public.funds
  add column if not exists fee_kind     text
    check (fee_kind is null or fee_kind in ('mgmt', 'service', 'none')),
  add column if not exists perf_fee_pct numeric,
  add column if not exists hurdle_pct   numeric;

comment on column public.funds.fee_kind is
  'Label for the mgmt_fee figure. mgmt = management fee (default). '
  'service = financial services charge or equivalent, used where the manager '
  'does not call it a management fee. none = no recurring charge published.';
comment on column public.funds.perf_fee_pct is
  'Performance charge, % of the return above hurdle_pct. MansaX: 10.';
comment on column public.funds.hurdle_pct is
  'Annual return above which perf_fee_pct applies. MansaX KES: 25. USD: 15. '
  'Meaningless without perf_fee_pct, and the app hides both when either is null.';


-- ── 5. Share classes ───────────────────────────────────────────────────────
--
-- Etica Special Wealth is ONE fund with three classes: A locks 6 months at a
-- 2.25% fee for 13.38%, B locks 9 at 2.00% for 13.55%, C locks 12 at 1.75% for
-- 13.72%. Three lock-ins, three fees, three yields, one product.
--
-- Modelled as three rows sharing a group rather than as a jsonb blob on one
-- row, because every downstream consumer already works per row: rate_history
-- keys on fund_id, min_invest and lock_in_months and mgmt_fee are scalars, the
-- import lane matches on name. A blob would need all of them rewritten.
--
-- DO NOT REUSE funds.classes FOR THIS. That column is jsonb and it holds IRA
-- class codes for insurers (see INSURER_FIELDS in snapshot.ts). Same English
-- word, unrelated concept, and it is already published under a different shape.

alter table public.funds
  add column if not exists class_group text,
  add column if not exists class_label text;

comment on column public.funds.class_group is
  'Shared id across the share classes of one product. Null when a fund has no '
  'classes, which is almost all of them. The app renders a class selector only '
  'when two or more live rows share a value here.';
comment on column public.funds.class_label is
  'Short label for this class, e.g. A, B, C, Retail, Institutional.';

create index if not exists funds_class_group_idx
  on public.funds (class_group) where class_group is not null;

-- Ranking hazard, recorded here because it is a rule about data and not about
-- pixels: a class group must contribute ONE row to a leaderboard, not three.
-- Class C always wins a yield sort, purely because it locks capital for a year.
-- Listing all three triple-counts one product and pushes two genuine
-- competitors off the table.


-- ── 6. Holdings and geography ──────────────────────────────────────────────
--
-- Every special and equity fact sheet publishes a top-ten and most publish a
-- geographic split. Neither fits funds.composition, which is the 8-class CMA
-- taxonomy in absolute shillings, and neither is derivable from anything held
-- today.
--
-- holdings is an ARRAY because rank is part of the fact: the sheet says these
-- are the ten largest, in order. geography is an OBJECT with a fixed key set,
-- shaped like credit_quality (0070), because the regions do not rank.

alter table public.funds
  add column if not exists holdings  jsonb,
  add column if not exists geography jsonb;

comment on column public.funds.holdings is
  'Top holdings, ordered largest first, as [{"name":"Fixed Income Instruments",'
  '"pct":13.73}]. Percent of the portfolio, not shillings. Managers state these '
  'are subject to change, and the app says so wherever it renders them.';
comment on column public.funds.geography is
  'Share of the portfolio by region, percentages summing to ~100. Keys: '
  'americas, europe, africa, mideast_asia, oceania. Shaped like credit_quality.';


-- ── 7. The period-return series ────────────────────────────────────────────
--
-- The actual missing piece, and it is a table rather than a column.
--
-- rate_history holds yields. nav_history (0070) holds prices. 0027 holds flat
-- trailing scalars and says so in its own header: "the app renders current
-- trailing figures, never a returns time-series". So there is nowhere to put
-- the eight quarterly bars every special fund fact sheet leads with, and
-- nowhere to put the seven calendar years MansaX prints gross and net.
--
-- Not folded into rate_history for the same reason nav_history was not: a
-- realized quarterly return and an annual yield are different objects that
-- happen to both be percentages. One is compoundable and taxable and cannot be
-- negative; the other is none of those. A single table would need a column
-- saying which kind each row was, which is the same as two tables with worse
-- constraints.

create table if not exists public.return_history (
  fund_id    text not null references public.funds (id) on delete cascade,
  period_end date not null,
  period     text not null
    check (period in ('month', 'quarter', 'half', 'year', 'ytd')),
  net_pct    numeric not null,
  gross_pct  numeric,
  net_of     text not null
    check (net_of in ('nothing', 'fees', 'fees_and_tax')),
  source     text,
  primary key (fund_id, period_end, period)
);

comment on table public.return_history is
  'Realized return for one CLOSED period of one fund. Mirrors rate_history '
  '(yields) and nav_history (prices). A fund publishes several period kinds off '
  'the same sheet, e.g. a quarter ending 31 Mar and a year ending 31 Dec, so '
  'period is part of the key rather than a property of the row.';

comment on column public.return_history.net_pct is
  'The return, %. DELIBERATELY UNCONSTRAINED IN SIGN. A negative quarter is the '
  'normal case for a multi-asset fund and refusing it, the way nav_history '
  'refuses a zero price, would silently drop exactly the periods a user most '
  'needs to see. MansaX Q4 2024 was 3.78% against a 6.05% quarter two later.';
comment on column public.return_history.gross_pct is
  'The same period before fees, when the sheet prints both. MansaX publishes '
  'gross and net per calendar year, and the gap between them is the fee doing '
  'its work: 25.74 gross against 20.74 net in 2025 is the 5% charge, visible.';
comment on column public.return_history.net_of is
  'Per row, not inherited from the fund. A manager can publish quarters net of '
  'fees and an annual figure net of fees and tax on the same page.';

create index if not exists return_history_fund_period_idx
  on public.return_history (fund_id, period, period_end desc);

-- Left EMPTY on purpose. There is nothing honest to seed it from: 0027's
-- return_1y and return_ytd are trailing annualised figures from a monthly
-- sheet, which is a different object from a closed period return, and copying
-- them in would put a number in the series that no fact sheet ever printed.
-- The series starts when the first factsheet SQL writes to it.


-- ── 8. What this migration deliberately does NOT do ────────────────────────
--
-- It does not flip any fund to basis='return'. 0023 parked every special fund
-- on 'none', and a blanket update would switch on a page for funds that have no
-- period data behind it yet, which trades a blank screen for a wrong one.
--
-- basis is set per fund by the factsheet SQL that also writes its first
-- return_history rows, its return_period and its net_of, in one transaction, so
-- a fund never sits in a state where the app has been told how to read a number
-- it does not have.
--
-- The board of what is still parked:
--
--   select fund_type, basis, count(*) as funds,
--          count(current_rate)    as have_rate,
--          count(price_per_unit)  as have_price,
--          count(return_period)   as have_period,
--          count(net_of)          as have_net_of
--   from   public.funds
--   where  kind = 'fund'
--   group  by 1, 2
--   order  by 1, 2;
--
-- And the funds most likely to be sitting on a misread number right now: a
-- special fund still on 'yield' is being taxed and compounded as though its
-- number were an annual rate.
--
--   select id, name, currency, basis, net_of, current_rate, return_period
--   from   public.funds
--   where  kind = 'fund'
--     and  fund_type = 'special'
--   order  by basis nulls first, id;

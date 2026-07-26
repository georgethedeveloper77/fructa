-- oak_special_return_basis.sql
--
-- OAK Special Fund KES, `faida-sp-kes`, Faida Investment Bank.
-- Source: OAK Special Fund Fact Sheet, September 2025.
-- Run after 0074 and 0075. Rebuild snapshot afterwards.
--
--
-- THE FOURTH MIS-BASED FUND
--
-- The row says basis='yield', current_rate=4.72. The sheet publishes no yield
-- at all: it publishes quarterly ABSOLUTE RETURNS since inception, monthly
-- returns for 2025, and a growth simulation. 4.72 corresponds to nothing
-- printed on it. So the app has been taxing that figure, compounding it two
-- years forward, and ranking a fund that returned 29% in 2024 against money
-- market funds paying 13%.
--
--
-- THREE THINGS ON THIS SHEET THAT MUST NOT BE STORED
--
-- 1. "OAK Special Fund targets a return of 20% net of fees." A TARGET. The
--    sheet says in the next line that it is not a guarantee. It is not a
--    return, it never happened, and there is no column for it because the app
--    has no honest place to put a number a manager hopes for.
--
-- 2. The ANNUALIZED column beside every quarter: 18.64%, 19.52%, 16.44%. Each
--    is one quarter multiplied out to a year. Q1 2025 returned 4.66%, and
--    18.64% is that same 4.66% wearing a bigger number. Only the absolute
--    column is a fact.
--
-- 3. "KES 1M invested 1st January 2025 would have yielded KES 156,765.38 by end
--    of September 2025." That is +15.68%, while the same sheet's year-to-date
--    absolute is 13.65% and its own three 2025 quarters compound to 14.28%.
--    Three figures for one period, all on one page. The quarters are the
--    primary record and they are what goes in; see the flag at the foot of this
--    file, because one of the three is wrong and only Faida can say which.


-- ── Pre-flight ──────────────────────────────────────────────────────────────
--
--   select id, name, basis, current_rate, min_invest, mgmt_fee, source_type,
--          company_id
--   from   public.funds where id = 'faida-sp-kes';
--
--   select as_of, rate, source from public.rate_history
--   where  fund_id = 'faida-sp-kes' order by as_of;


begin;

update public.funds set
  basis          = 'return',
  return_period  = 'quarter',
  return_as_of   = date '2025-09-30',
  net_of         = 'fees',
  current_rate   = null,
  fee_kind       = 'mgmt',
  mgmt_fee       = 6.00,          -- 6% p.a. pro-rated
  redemption_fee = 0,             -- "Withdrawal Fees: 0"
  min_invest     = 500000,
  top_up_min     = 50000,
  lock_in_months = 6,
  inception_date = date '2024-02-01',
  aum_native     = 8650000000,    -- KES 8.65B
  objective      = 'A special fund with a diverse trading model, allocating across global currencies, precious metals, commodities, international equities, ETFs and sovereign bonds alongside local government securities and NSE instruments.',
  source_type    = 'manual'
where id = 'faida-sp-kes';

-- Every completed quarter since inception, absolute.
--
-- Q1 2024 is a stub: the fund opened in February, so 15.40% is roughly six
-- weeks of trading rather than a quarter. Stored because omitting it would
-- start the record in April and hide the fund's strongest period, but it is the
-- reason the bar chart opens with a spike.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('faida-sp-kes', date '2024-03-31', 'quarter', 15.40, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2024-06-30', 'quarter',  6.78, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2024-09-30', 'quarter',  3.15, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2024-12-31', 'quarter',  4.05, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2025-03-31', 'quarter',  4.66, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2025-06-30', 'quarter',  4.88, 'fees', 'oak-factsheet-2025-09'),
  ('faida-sp-kes', date '2025-09-30', 'quarter',  4.11, 'fees', 'oak-factsheet-2025-09')
on conflict (fund_id, period_end, period) do nothing;

-- Year to date at the sheet date. Not part of the chart series: it overlaps the
-- three 2025 quarters it contains.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('faida-sp-kes', date '2025-09-30', 'ytd', 13.65, 'fees', 'oak-factsheet-2025-09')
on conflict (fund_id, period_end, period) do nothing;

-- The growth simulation: KES 1,000,000 from 20 Feb 2024 was worth 1,511,398.04
-- by 30 Sept 2025. That is +51.1398%, and it is the manager's own endpoint, so
-- the growth card uses it rather than compounding the quarters.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('faida-sp-kes', date '2025-09-30', 'since_inception', 51.1398, 'fees', 'oak-factsheet-2025-09')
on conflict (fund_id, period_end, period) do nothing;

-- ── The 2024 calendar year row is DELIBERATELY NOT INSERTED ────────────────
--
-- The sheet prints "2024 Absolute Return 29.38%". Its own four 2024 quarters
-- compound to 32.26%. Both cannot be right, and a calendar-year table sitting
-- on the same page as the bar chart it contradicts is worse than no table.
--
-- The likeliest explanation is that 29.38% runs from the 20 February inception
-- rather than from 1 January, which would make it a partial year mislabelled as
-- a full one. That is a question for Faida, not a gap to fill with a guess.

-- ── Monthly 2025 returns are also NOT inserted ─────────────────────────────
--
-- The sheet prints nine of them: 1.60, 1.76, 1.30, 1.66, 1.53, 1.69, 0.72,
-- 1.70, 1.69. Real figures, and they are left out on purpose.
--
-- FundReturns.dominantPeriod charts whichever period kind a fund publishes most
-- of. Nine months would beat seven quarters, so the chart would swap to a
-- nine-bar view covering 2025 alone and silently drop the fund's entire first
-- year, including the 15.40% opening quarter. Fewer, longer bars carry more of
-- this fund's history than more, shorter ones.
--
-- Insert them later only alongside a period-granularity switch on the chart.

update public.companies c set
  trustee   = coalesce(c.trustee,   'Co-operative Bank of Kenya'),
  custodian = coalesce(c.custodian, 'I&M Bank'),
  auditor   = coalesce(c.auditor,   'Njoroge Kuria & Associates'),
  phone     = coalesce(c.phone,     '+254719212349'),
  whatsapp  = coalesce(c.whatsapp,  '+254743552341'),
  email     = coalesce(c.email,     'oak@fib.co.ke'),
  website   = coalesce(c.website,   'https://www.oak.africa')
from public.funds f
where f.id = 'faida-sp-kes' and c.id = f.company_id;

-- The misfiled rate history, for the same reason as MansaX: left in place, the
-- next backfill promotes it into current_rate and the fund silently becomes a
-- yield fund again.
delete from public.rate_history where fund_id = 'faida-sp-kes';

commit;


-- ── Flags for George ───────────────────────────────────────────────────────
--
-- STALE. This sheet is dated September 2025 and it is now July 2026. Three
-- quarters are missing: Q4 2025, Q1 2026 and Q2 2026. Everything above is
-- accurate as at the sheet and out of date as a picture of the fund. Worth
-- asking oak@fib.co.ke for the current one before this goes in front of
-- anybody.
--
-- BENCHMARK unset. Oak quotes a blend: 30% 364-day T-bill, 30% NSE All Share,
-- 40% S&P 500. funds.benchmark_key only accepts a single key, so it stays null.
-- A blended benchmark needs its own text column, and Etica Special Multi Asset
-- has the same problem, so it is now two funds rather than one.
--
-- ASSET ALLOCATION not stored. The sheet gives sovereign bonds 58%, CFDs 11%,
-- cash 11%, NSE securities 11%, derivatives 7%, international equities 1%,
-- funds of funds 1%. There is nowhere honest to put it: funds.composition is
-- the CMA eight-class taxonomy in absolute shillings, and this is a manager's
-- own percentage split into categories that do not map onto it. Forcing it in
-- would corrupt the one field the market donut trusts.
--
-- OAK USD, `faida-sp-usd`, is untouched and still basis='nav' with no price. It
-- needs its own fact sheet.

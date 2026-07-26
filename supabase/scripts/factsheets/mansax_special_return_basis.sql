-- mansax_special_return_basis.sql
--
-- Run after 0074 and 0075. Then Rebuild snapshot.
--
-- Source: MansaX Special Fund Fact Sheet Q1 2026, and Intro to SIB & MansaX
-- Special Fund Q1 2026, both published by Standard Investment Bank.
--
--
-- WHY THE PAGE LOOKED LIKE A MONEY MARKET FUND
--
-- Because the row said it was one. `standard-investment-trust-fund-sp-kes`
-- carries basis='yield' and current_rate=4.74, and every surface in the app
-- reads those two fields and behaves correctly given them.
--
-- 4.74% is the Q1 2026 QUARTERLY net return. As an annual yield it is wrong in
-- three directions at once, and each one is visible on the screenshot:
--
--   THE HERO deducts 15% withholding tax to 4.03%. MansaX publishes its returns
--   after fees; the app invented a deduction and printed a figure the manager
--   has never quoted.
--
--   THE RANK reads "#8 of 9 KES special funds by net yield". The fund returned
--   18.96% annualised in Q1 and has averaged 19.67% over three years. It is
--   ranked second from last because a quarter is being compared against annual
--   yields. This is the most damaging of the three: it is not a cosmetic error,
--   it is the app actively recommending against the best performer in its
--   category.
--
--   THE PROJECTION compounds 4.74% a year and reports that KES 250,000 plus
--   240,000 of top-ups becomes 519,778 over two years. At what the fund has
--   actually done, the same money is worth far more. The app understates a real
--   fund by a wide margin and presents the understatement as arithmetic.
--
-- None of that is a rendering bug. Set basis correctly and all three stop.


-- ── Pre-flight ──────────────────────────────────────────────────────────────
--
-- Expect exactly two rows, and note the company_id: everything below resolves
-- the company through the fund rather than assuming a slug.
--
--   select id, name, currency, basis, current_rate, company_id,
--          min_invest, mgmt_fee, source_type
--   from   public.funds
--   where  id in ('standard-investment-trust-fund-sp-kes',
--                 'standard-investment-trust-fund-sp-usd');
--
-- And the rate history that has to go, which is where the 4.74 came from and
-- why the chart in the screenshot drew a flat line at 4.73:
--
--   select fund_id, as_of, rate, source
--   from   public.rate_history
--   where  fund_id like 'standard-investment-trust-fund-sp-%'
--   order  by fund_id, as_of;


begin;

-- ── 1. KES ─────────────────────────────────────────────────────────────────

update public.funds set
  basis          = 'return',
  return_period  = 'quarter',
  return_as_of   = date '2026-03-31',
  net_of         = 'fees',        -- "after fees" on every chart in the sheet
  current_rate   = null,          -- there is no annual yield here to hold
  fee_kind       = 'service',     -- a financial services charge, not a mgmt fee
  mgmt_fee       = 5.00,
  perf_fee_pct   = 10,
  hurdle_pct     = 25,
  redemption_fee = 0,
  min_invest     = 250000,
  top_up_min     = 100000,
  lock_in_months = 6,
  inception_date = date '2019-01-01',
  aum_native     = 132180000000,  -- KES 132.18 Bn as at 31 Mar 2026
  withdraw_note  = '2 to 3 working days after the 6 month lock-in',
  objective      = 'Multi-asset strategy fund with a long and short trading model, investing in local and global markets with the primary objective of capital growth.',
  -- Stop the scraper putting a rate back. A fund that publishes no yield has
  -- nothing for a yield scraper to find, and anything it did find would be one
  -- of these quarterly figures misread again.
  source_type    = 'manual'
where id = 'standard-investment-trust-fund-sp-kes';

-- Eight completed quarters, exactly as the 24-month chart prints them.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-kes', date '2024-06-30', 'quarter', 4.99, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2024-09-30', 'quarter', 5.14, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2024-12-31', 'quarter', 3.78, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2025-03-31', 'quarter', 4.89, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2025-06-30', 'quarter', 6.05, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2025-09-30', 'quarter', 5.09, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2025-12-31', 'quarter', 4.71, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2026-03-31', 'quarter', 4.74, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

-- Seven calendar years, gross AND net. The gap between the two columns is the
-- 5% charge made visible: 25.74 gross against 20.74 net in 2025 is what the fee
-- actually costs, stated in the same units as the return it comes out of.
insert into public.return_history (fund_id, period_end, period, net_pct, gross_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-kes', date '2019-12-31', 'year', 19.01, 24.01, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2020-12-31', 'year', 18.75, 23.75, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2021-12-31', 'year', 15.45, 20.45, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2022-12-31', 'year', 15.59, 20.59, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2023-12-31', 'year', 18.01, 23.01, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2024-12-31', 'year', 19.53, 24.53, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-kes', date '2025-12-31', 'year', 20.74, 25.74, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

-- The manager's own endpoint: KES 1,000,000 invested 1 Jan 2019 was worth
-- 3,594,335 after fees by 31 Mar 2026. That is +259.4335%.
--
-- Stored so the growth card uses SIB's published figure rather than compounding
-- the quarters above, which lands near 3,365,000. Neither number is a mistake:
-- the published line is a real account track, while the percentages are each
-- rounded to two places and the rounding compounds along with the returns. The
-- one the manager lived is the one to show.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-kes', date '2026-03-31', 'since_inception', 259.4335, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

update public.funds set
  holdings = '[
    {"name":"Fixed income instruments","pct":13.73},
    {"name":"Interest rate derivatives","pct":4.87},
    {"name":"WTI crude oil futures","pct":2.21},
    {"name":"Family Bank Limited","pct":1.52},
    {"name":"Exxon Mobil Corporation","pct":1.46},
    {"name":"Lockheed Martin Corporation","pct":1.39},
    {"name":"BAE Systems plc","pct":1.34},
    {"name":"Monday.com Ltd","pct":1.28},
    {"name":"Cash and cash equivalents","pct":1.25},
    {"name":"Nasdaq 100","pct":1.20}]'::jsonb,
  geography = '{"americas":52.85,"africa":24.69,"europe":17.13,"mideast_asia":3.81,"oceania":1.52}'::jsonb
where id = 'standard-investment-trust-fund-sp-kes';


-- ── 2. USD ─────────────────────────────────────────────────────────────────
--
-- A separate row, not a currency toggle on the KES fund. Same strategy, but a
-- different minimum, a different hurdle, different holdings and a different
-- geographic split, so they are two funds a person chooses between exactly as
-- they choose between a KES and a USD money market fund.

update public.funds set
  basis          = 'return',
  return_period  = 'quarter',
  return_as_of   = date '2026-03-31',
  net_of         = 'fees',
  current_rate   = null,
  fee_kind       = 'service',
  mgmt_fee       = 5.00,
  perf_fee_pct   = 10,
  hurdle_pct     = 15,            -- lower hurdle than the KES fund
  redemption_fee = 0,
  min_invest     = 2500,
  top_up_min     = 1000,
  lock_in_months = 6,
  inception_date = date '2022-10-01',
  aum_native     = 134170000,     -- USD 134.17 Mn as at 31 Mar 2026
  withdraw_note  = '2 to 3 working days after the 6 month lock-in',
  objective      = 'Multi-asset strategy fund with a long and short trading model, investing in local and global markets with the primary objective of capital growth.',
  source_type    = 'manual'
where id = 'standard-investment-trust-fund-sp-usd';

insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-usd', date '2024-06-30', 'quarter', 2.93, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2024-09-30', 'quarter', 3.12, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2024-12-31', 'quarter', 2.97, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2025-03-31', 'quarter', 3.14, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2025-06-30', 'quarter', 3.47, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2025-09-30', 'quarter', 3.52, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2025-12-31', 'quarter', 3.24, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2026-03-31', 'quarter', 2.88, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

-- 2022 is a stub year: the fund opened in the fourth quarter, and the sheet
-- marks it with an asterisk meaning the figure is annualised from a part year.
-- Stored anyway, because omitting it would leave the table starting in 2023 and
-- imply the fund had no first year at all.
insert into public.return_history (fund_id, period_end, period, net_pct, gross_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-usd', date '2022-12-31', 'year', 10.08, 15.08, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2023-12-31', 'year', 12.10, 17.10, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2024-12-31', 'year', 12.50, 17.50, 'fees', 'sib-factsheet-q1-2026'),
  ('standard-investment-trust-fund-sp-usd', date '2025-12-31', 'year', 13.37, 18.37, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

-- USD 10,000 from 9 Nov 2022 was worth 14,949.02 after fees by 31 Mar 2026.
insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
values
  ('standard-investment-trust-fund-sp-usd', date '2026-03-31', 'since_inception', 49.4902, 'fees', 'sib-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

update public.funds set
  holdings = '[
    {"name":"Fixed income instruments","pct":14.53},
    {"name":"Interest rate derivatives","pct":5.01},
    {"name":"WTI crude oil futures","pct":2.20},
    {"name":"Exxon Mobil Corporation","pct":1.40},
    {"name":"Kinder Morgan Inc","pct":1.37},
    {"name":"BAE Systems plc","pct":1.35},
    {"name":"Cash and cash equivalents","pct":1.33},
    {"name":"Lockheed Martin Corporation","pct":1.29},
    {"name":"Nike Inc","pct":1.24},
    {"name":"S&P 500","pct":1.18}]'::jsonb,
  geography = '{"americas":55.90,"europe":27.06,"africa":11.24,"mideast_asia":3.98,"oceania":1.82}'::jsonb
where id = 'standard-investment-trust-fund-sp-usd';


-- ── 3. Delete the misfiled rate history ────────────────────────────────────
--
-- THIS IS THE STEP THAT MAKES THE REST STICK, and skipping it silently undoes
-- everything above.
--
-- The 4.74 in current_rate came from rate_history, and the flat line the chart
-- drew between Mar and Jul 2026 is those rows. They are quarterly returns filed
-- as annual yields. Left in place, the next run of
-- akiba_backfill_current_rate.sql promotes the freshest one straight back into
-- current_rate, and the fund silently returns to being a yield fund with a
-- projection and a tax deduction.
--
-- Deleted rather than migrated: every figure in them is already in
-- return_history above, from the fact sheet, with its period and its net-ness
-- recorded. A rate_history row cannot carry either.

delete from public.rate_history
where fund_id in ('standard-investment-trust-fund-sp-kes',
                  'standard-investment-trust-fund-sp-usd');


-- ── 4. Custody and contact, guarded ────────────────────────────────────────

update public.companies c set
  trustee   = coalesce(c.trustee,   'Kingsland Court Trustees'),
  custodian = coalesce(c.custodian, 'I&M Bank'),
  auditor   = coalesce(c.auditor,   'Chartafai LLP'),
  phone     = coalesce(c.phone,     '+254777333000'),
  email     = coalesce(c.email,     'clientservices@sib.co.ke'),
  website   = coalesce(c.website,   'https://www.sib.co.ke')
from public.funds f
where f.id = 'standard-investment-trust-fund-sp-kes'
  and c.id = f.company_id;

commit;


-- ── The two Shariah funds are NOT touched ──────────────────────────────────
--
--   standard-investment-trust-fund-sp-kes-mansa-x   basis 'nav'
--   standard-investment-trust-fund-sp-usd-mansa-x   basis 'nav'
--
-- Mansa-X Shariah is a different product with its own mandate and its own
-- returns, and none of the figures above belong to it. Both currently sit on
-- basis='nav' with no unit price, so after this they will render the NAV empty
-- state, which says no price has been published rather than inventing one.
--
-- They need their own fact sheet. When it arrives they almost certainly move to
-- basis='return' the same way these two just did.


-- ── The wider sweep ────────────────────────────────────────────────────────
--
-- MansaX is the third fund found carrying a basis it does not have, after the
-- Etica special fund and whatever the null-basis backfill caught. That is a
-- pattern rather than three coincidences, so this is the query worth running
-- before assuming anything else is right.
--
-- A special, equity or balanced fund on basis='yield' is being taxed and
-- compounded as though its number were an annual rate:
--
--   select id, name, currency, fund_type, basis, net_of, current_rate,
--          return_period, source_type
--   from   public.funds
--   where  kind = 'fund'
--     and  fund_type in ('special','equity','balanced')
--     and  basis = 'yield'
--   order  by current_rate desc nulls last;
--
-- And the reverse: anything on 'nav' or 'return' still holding a rate, which is
-- the state that lets a backfill flip it back.
--
--   select f.id, f.name, f.basis, f.current_rate, count(r.*) as rate_rows
--   from   public.funds f
--   left   join public.rate_history r on r.fund_id = f.id
--   where  f.kind = 'fund' and f.basis in ('nav','return')
--   group  by f.id, f.name, f.basis, f.current_rate
--   having f.current_rate is not null or count(r.*) > 0;

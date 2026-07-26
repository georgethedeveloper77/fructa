-- specials_factsheet_batch_2026_07.sql
--
-- Eight funds from nine fact sheets. Run after 0074 and 0075, then Rebuild
-- snapshot.
--
-- THE SHEETS SPLIT THREE WAYS, and the split is the reason this file is not
-- one repeated block:
--
--   YIELD, and the row was merely stale. African Alliance, Dry Associates,
--   Madison, Lofty-Corban Private Debt. All four genuinely quote an effective
--   annual yield. basis stays; the number is corrected.
--
--   RETURN, and the row was wrong. Lofty-Corban Global Asset, CIC Global
--   Balanced. Both quote period returns and both sat on basis='nav' with
--   nothing to show.
--
--   NO PERFORMANCE AT ALL. Old Mutual (a 15-month-old sheet) and the two
--   Arvocap KIIDs (which have an empty Past Performance section by design).
--   Terms only, and NOT a single performance figure written from any of them.
--
--
-- FOUR NUMBERS ON THESE SHEETS THAT ARE NOT RETURNS
--
--   Lofty-Corban Private Debt: "targets an absolute return of 16%".
--   Lofty-Corban Global Asset: "targets an absolute gross return benchmark
--     of 25%".
--   Dry Associates: 16.18% "gross yield before bonuses", beside a 12.47% net.
--   Old Mutual Special Fixed Income: 13.4% effective yield, as at APRIL 2025.
--
-- The first two are targets and say so in the next clause. The third is a
-- figure before the fee that halves it. The fourth is fifteen months old and
-- the database already holds something newer. None are written.


begin;

-- ═══ 1. AFRICAN ALLIANCE KENYA SPECIAL FUND ════════════════════════════════
-- Sheet: June 2026, issued July 2026. Stays basis='yield': the sheet's own
-- headline is "Net Effective Annual Rate 7.34%", which is exactly the object
-- an MMF quotes. The row held 7.61, from somewhere older.
--
-- This sheet is the only one in the batch that fills the 0027 trailing block
-- properly: it prints fund AND benchmark per horizon, so the comparison is
-- on-basis rather than against today's spot rate.

update public.funds set
  basis          = 'yield',
  net_of         = 'fees',
  current_rate   = 7.34,
  fee_kind       = 'mgmt',
  mgmt_fee       = 2.00,          -- inclusive of VAT, per the sheet
  min_invest     = 1000000,
  top_up_min     = 500000,
  inception_date = date '2018-08-01',
  aum_native     = 127185100.61,  -- fund size, not total assets
  return_1y = 7.58,  bench_1y = 7.94,
  return_3y = 10.35, bench_3y = 11.47,
  return_5y = 10.15, bench_5y = 10.26,
  returns_as_of  = date '2026-06-30',
  objective      = 'Long-term returns through capital appreciation and income, pursuing an alternative strategy across private equity, venture capital, infrastructure, renewable energy and ESG-linked assets.'
where id = 'african-alliance-kenya-sp-kes';

insert into public.rate_history (fund_id, as_of, rate, source) values
  ('african-alliance-kenya-sp-kes', date '2026-06-30', 7.34, 'aa-factsheet-2026-06')
on conflict do nothing;

-- Instrument split from the sheet: government fixed income 62.0%, fixed
-- deposits 25.7%, corporate fixed income 12.2%, cash 0.1%. NOT written, for the
-- same reason Oak's was not: funds.composition is the CMA eight-class taxonomy
-- in absolute shillings and this is a manager's own percentage split. Third
-- fund now blocked on the same missing column.


-- ═══ 2. DRY ASSOCIATES SPECIAL HIGH YIELD FUND (KES) ═══════════════════════
-- Sheet: July 2026, yield as at 30.06.2026.
--
-- Two yields on one page and only one is the fund's. 16.18% is captioned "gross
-- yield before bonuses"; the performance bonus is 50% of everything above the
-- hurdle, so roughly a third of that headline never reaches an investor. The
-- header figure, 12.47% NET, is the one a holder receives, and it is what goes
-- in. The row held 12.94.

update public.funds set
  basis          = 'yield',
  net_of         = 'fees',        -- net of fees; 15% WHT still applies
  current_rate   = 12.47,
  fee_kind       = 'mgmt',
  expense_ratio  = 3.00,          -- "3.00% p.a. plus performance bonus"
  mgmt_fee       = 0.25,          -- the administrative fee, the only flat one
  perf_fee_pct   = 50,
  min_invest     = 1000000,
  top_up_min     = 250000,
  lock_in_months = 6,
  inception_date = date '2025-01-01',
  aum_native     = 578188000,
  withdraw_note  = 'Accessible within 10 business days; 30 day reserve redemption',
  objective      = 'Income over the medium to long term from a diversified portfolio of fixed income securities with weighted average duration under sixty months.'
where id = 'dry-associates-sp-kes';

insert into public.rate_history (fund_id, as_of, rate, source) values
  ('dry-associates-sp-kes', date '2026-06-30', 12.47, 'dry-factsheet-2026-07')
on conflict do nothing;

-- hurdle_pct left NULL deliberately. The hurdle is "91-day T-bill plus 0.50%",
-- a floating rate, and hurdle_pct is numeric. Writing today's T-bill into it
-- would freeze a moving target and be wrong within a fortnight. The schema
-- assumed a fixed hurdle because MansaX has one; this fund does not.
--
-- redemption_fee also NULL: it is 3%, 2% or 1% depending on whether you exit
-- within one, two or three years. One number cannot say that.


-- ═══ 3. MADISON WEALTH SPECIAL FUND ════════════════════════════════════════
-- Sheets: March 2026 and May 2026, both supplied. Between them they give five
-- consecutive monthly yields, which is the most valuable thing in this batch:
-- an actual rate series rather than a single point.
--
-- The sheet states the convention outright, in a footnote under its own chart:
-- "MWSF return is an effective annual yield, net of fees and gross of
-- withholding tax". That is net_of='fees', confirmed by the manager rather than
-- assumed by us.

update public.funds set
  basis          = 'yield',
  net_of         = 'fees',
  current_rate   = 11.61,         -- May 2026, the newest of the five
  fee_kind       = 'mgmt',
  mgmt_fee       = 2.00,
  min_invest     = 1000000,
  top_up_min     = 1000000,
  lock_in_months = 6,
  inception_date = date '2022-06-15',
  aum_native     = 9690000000,    -- KES 9.69bn, May sheet
  objective      = 'Enhance return while securing steady capital growth through a diversified portfolio of high yielding securities in local and international markets.'
where id = 'madison-sp-kes';

insert into public.rate_history (fund_id, as_of, rate, source) values
  ('madison-sp-kes', date '2026-01-31', 12.02, 'madison-factsheet-2026-03'),
  ('madison-sp-kes', date '2026-02-28', 11.91, 'madison-factsheet-2026-03'),
  ('madison-sp-kes', date '2026-03-31', 11.72, 'madison-factsheet-2026-03'),
  ('madison-sp-kes', date '2026-04-30', 11.54, 'madison-factsheet-2026-05'),
  ('madison-sp-kes', date '2026-05-31', 11.61, 'madison-factsheet-2026-05')
on conflict do nothing;

-- The "Periodic Returns" panel gives realized figures too: FY'25 13.64%,
-- Q1'2026 3.00%, and single months around 0.97%. Real, and not written. This is
-- a yield fund, so company_page renders period returns only when
-- showsPeriodReturn is true; the rows would sit in the database unreachable.
-- They become useful the day a yield fund is allowed to show a realized-history
-- section beneath its rate chart, which is a UI decision that has not been made.
--
-- The May sheet's asset allocation sums to 102.48%: fixed deposits 25.78,
-- corporate debt 27.08, government securities 49.62. The March sheet sums to
-- exactly 100.00. One of the May figures is mistyped, so neither is stored.


-- ═══ 4. LOFTY-CORBAN PRIVATE DEBT SPECIAL FUND ═════════════════════════════
-- Sheet: Q1 2026. Resolves an open question from an earlier session: this fund
-- IS a yield fund. The chart is captioned "Average Annualized Daily Yield" and
-- the scheme disclaimer says "The Effective Annual yield is net of fees and
-- gross of withholding tax". The row held 15.17; the sheet's latest is 14.23.

update public.funds set
  basis          = 'yield',
  net_of         = 'fees',
  current_rate   = 14.23,         -- March 2026
  fee_kind       = 'mgmt',
  mgmt_fee       = 3.00,
  min_invest     = 1000000,
  top_up_min     = 500000,
  lock_in_months = 6,
  inception_date = date '2025-12-15',
  aum_native     = 423880000,
  objective      = 'Regular income while preserving capital, investing in short and long term corporate debt, alternative and other fixed income securities.'
where id = 'lofty-corban-sp-kes';

insert into public.rate_history (fund_id, as_of, rate, source) values
  ('lofty-corban-sp-kes', date '2026-01-31', 14.20, 'lc-factsheet-q1-2026'),
  ('lofty-corban-sp-kes', date '2026-02-28', 14.28, 'lc-factsheet-q1-2026'),
  ('lofty-corban-sp-kes', date '2026-03-31', 14.23, 'lc-factsheet-q1-2026')
on conflict do nothing;

-- The 16% "return benchmark" is a target and the sheet says so: "This is,
-- however, a target return and not a performance indication."


-- ═══ 5. LOFTY-CORBAN GLOBAL ASSET SPECIAL FUND ═════════════════════════════
-- Sheet: Q1 2026. Was basis='nav' with no price, so it rendered nothing.
--
-- THE FIRST NEGATIVE PERIOD IN THE DATABASE. March 2026 returned -0.73%
-- against a +2.20% benchmark. Every design decision made for negative returns
-- has been theoretical until now: return_history.net_pct carries no sign
-- constraint, PeriodReturnsBar puts its baseline at zero so a losing month
-- draws downward instead of clamping to a stub, and the tile colours the figure
-- with c.delta. This fund is the one that proves them.
--
-- net_of='nothing': the chart is captioned "Gross of Fees", and the fee is 5%.
-- So -0.73% is BEFORE a charge that will make it worse, and the app must not
-- present it as what a holder received.

update public.funds set
  basis          = 'return',
  return_period  = 'month',
  return_as_of   = date '2026-03-31',
  net_of         = 'nothing',
  current_rate   = null,
  fee_kind       = 'mgmt',
  mgmt_fee       = 5.00,
  min_invest     = 100000,
  top_up_min     = 50000,
  lock_in_months = 6,
  inception_date = date '2026-01-13',
  aum_native     = 24800000,
  source_type    = 'manual',
  objective      = 'Long term capital growth and income through global diversification across equities, fixed income and alternative investments.'
where id = 'lofty-corban-sp-kes-global-assets';

insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source) values
  ('lofty-corban-sp-kes-global-assets', date '2026-03-31', 'month', -0.73, 'nothing', 'lc-factsheet-q1-2026'),
  ('lofty-corban-sp-kes-global-assets', date '2026-03-31', 'quarter', 2.17, 'nothing', 'lc-factsheet-q1-2026')
on conflict (fund_id, period_end, period) do nothing;

delete from public.rate_history where fund_id = 'lofty-corban-sp-kes-global-assets';

-- The 25% "absolute gross return benchmark" is a target. Not written.


-- ═══ 6. CIC GLOBAL BALANCED SPECIAL FUND ═══════════════════════════════════
-- Sheet: January 2026.
--
-- THE ROW HAS THE WRONG CURRENCY. It says KES. The sheet quotes a USD 1,000
-- minimum, a USD 100 top-up, a USD 10 withdrawal and USD 1.4 Million under
-- management, and benchmarks against SOFR and MSCI ACWI. It is a dollar fund.
--
-- This is the same failure as the Nabo fund found in an earlier session, and it
-- is worse than a mislabelled basis: currency drives the sub-filter chips, the
-- minimum-investment display and every peer cohort the fund is ranked inside.
-- A dollar fund sitting in the shilling cohort is compared against instruments
-- it shares no market with.

update public.funds set
  currency       = 'USD',
  basis          = 'return',
  return_period  = 'month',
  return_as_of   = date '2026-01-31',
  net_of         = 'fees',
  current_rate   = null,
  fee_kind       = 'mgmt',
  mgmt_fee       = 2.50,
  min_invest     = 1000,
  top_up_min     = 100,
  lock_in_months = 6,
  inception_date = date '2025-07-01',
  aum_native     = 1400000,
  source_type    = 'manual',
  objective      = 'Long-term capital appreciation across market cycles through a diversified global portfolio of equities, fixed income, money market instruments and eligible ETFs.'
where id = 'cic-sp-kes-global-balanced';

insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source) values
  ('cic-sp-kes-global-balanced', date '2026-01-31', 'month', 1.68, 'fees', 'cic-factsheet-2026-01'),
  ('cic-sp-kes-global-balanced', date '2026-01-31', 'since_inception', 5.47, 'fees', 'cic-factsheet-2026-01')
on conflict (fund_id, period_end, period) do nothing;

update public.funds set
  geography = '{"americas":47.5,"other":52.5}'::jsonb
where id = 'cic-sp-kes-global-balanced';

delete from public.rate_history where fund_id = 'cic-sp-kes-global-balanced';

-- The id still reads "-kes". Cosmetic and left alone: funds.currency is
-- authoritative, the slug is not, and renaming a primary key would orphan
-- follows, holdings and push tags for anyone already tracking it.


-- ═══ 7. OLD MUTUAL SPECIAL FIXED INCOME ════════════════════════════════════
-- Sheet: APRIL 2025. Fifteen months old.
--
-- NO RATE IS WRITTEN FROM THIS SHEET, and that is the entire point of this
-- section. The sheet says 13.4%; the row holds 11.37, which came from a scraper
-- and is almost certainly newer. Writing the sheet's figure would move the fund
-- from a current number to a stale one and call it an update. A fact sheet is
-- only authoritative as at its own date.
--
-- What IS written is the static terms, which do not go stale, and one of them
-- is a real correction: the row says the minimum is KES 1,000,000. The sheet
-- says KES 50,000. That is a twentyfold overstatement of what it costs to enter
-- this fund, and it would have priced the fund out of consideration for exactly
-- the savers it suits.

update public.funds set
  net_of         = 'fees',
  fee_kind       = 'mgmt',
  mgmt_fee       = 2.00,          -- 2% p.a. + VAT
  min_invest     = 50000,
  top_up_min     = 5000,
  inception_date = date '2024-07-01',
  benchmark_key  = 'tbill_182',   -- "Average 182-day T-bill"
  objective      = 'High income yields through fixed interest and floating rate securities locally and internationally, in KES and USD.'
where id = 'old-mutual-sp-kes';

update public.companies c set
  trustee   = coalesce(c.trustee,   'KCB Bank Kenya Limited'),
  custodian = coalesce(c.custodian, 'KCB Bank Kenya Limited'),
  auditor   = coalesce(c.auditor,   'PricewaterhouseCoopers'),
  phone     = coalesce(c.phone,     '+254711065100'),
  email     = coalesce(c.email,     'clientservices@oldmutual.co.ke'),
  website   = coalesce(c.website,   'https://www.oldmutual.co.ke')
from public.funds f
where f.id = 'old-mutual-sp-kes' and c.id = f.company_id;


-- ═══ 8. ARVOCAP, TWO KIIDs ═════════════════════════════════════════════════
-- These are not fact sheets. A Key Investor Information Document is a
-- regulatory disclosure of terms and risk, and both of these have a PAST
-- PERFORMANCE heading with nothing underneath it. That blank is not an
-- oversight; the funds had no track record when the documents were dated
-- 1 February 2024, and Arvocap has not reissued them.
--
-- So: terms only, no basis change, no performance. Both funds keep basis='nav'
-- and keep rendering the NAV empty state, which is the truthful description of
-- a fund whose own manager publishes no numbers.

update public.funds set
  fee_kind      = 'mgmt',
  mgmt_fee      = 2.00,
  expense_ratio = 2.00,
  perf_fee_pct  = 20,             -- 20% of total annual net return
  objective     = 'A high level of profitability from a value portfolio maintained in adherence to Sharia regulations.'
where id = 'arvocap-sp-kes-mabruk-sharia';

update public.funds set
  fee_kind      = 'mgmt',
  mgmt_fee      = 2.00,
  expense_ratio = 2.00,
  perf_fee_pct  = 20,
  objective     = 'Robust returns from a value portfolio in adherence to Sharia regulations, focused on globally listed equities meeting Shariah qualification.'
where id = 'arvocap-sp-kes-global-sharia';

update public.companies c set
  custodian = coalesce(c.custodian, 'NCBA Bank Kenya PLC'),
  phone     = coalesce(c.phone,     '+254701300200'),
  email     = coalesce(c.email,     'invest@arvocap.com'),
  website   = coalesce(c.website,   'https://www.arvocap.com')
from public.funds f
where f.id = 'arvocap-sp-kes-mabruk-sharia' and c.id = f.company_id;

commit;


-- ═══ FLAGS ═════════════════════════════════════════════════════════════════
--
-- ARVOCAP GLOBAL SHARIA CURRENCY. The KIID is titled "Arvocap Sharia Global
-- Equity Special Fund" and states "The currency of the fund is in USD". The row
-- `arvocap-sp-kes-global-sharia` is named "Arvocap Global Sharia Special Fund"
-- and says KES. Either they are two different funds or the row has the CIC
-- problem. Not changed, because unlike CIC the names do not match either, and
-- guessing at a currency is worse than leaving one wrong.
--
-- LOFTY-CORBAN SPECIAL MONEY MARKET FUND, `lofty-corban-sp-kes-special`, rate
-- 8.92. It does NOT appear in the Q1 2026 fact sheet, which covers six funds
-- and not this one. An earlier session suspected it was discontinued after
-- Q4 2024; its absence here is the second piece of evidence. Worth setting
-- status='hidden' rather than continuing to publish a rate for a fund that may
-- no longer accept money.
--
-- NON-SPECIAL FUNDS IN THIS BATCH, all with current data and none touched:
--   Old Mutual MMF KES 12.2%, Dollar MMF 5.3%, Balanced 19.8%, Bond 14.2%,
--     Equity (1-year 18.9%) - all as at April 2025, so all stale.
--   Lofty-Corban KSHS MMF, ten quarters from Q4 2023 to Q1 2026 ending 10.17%.
--   Lofty-Corban USD MMF, ten quarters ending 5.04%.
--   Lofty-Corban KSHS Fixed Income Bond and KSHS Equity, both gross of fees.
-- The two Lofty-Corban money market series are current and would give those
-- funds ten-point rate charts. Worth a follow-up file.
--
-- STILL MISSING, per your list: CIC Wealth, KCB Wealth, NCBA x2, Britam Special
-- Fixed Income, Kuza x2, Capital A x2, Mansa-X Shariah x2, Oak USD.
--
-- SCHEMA GAP, now blocking four funds rather than two: a manager's own asset
-- allocation has nowhere to live. African Alliance, Oak, Madison and CIC all
-- publish one and none of them fit funds.composition.

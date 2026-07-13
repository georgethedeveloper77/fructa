-- 0054_stock_dividends_complete.sql
--
-- The COMPLETE dividend record for the latest completed financial year of every
-- NSE company that pays one. This supersedes 0052, which carried only the
-- finals printed on the NSE daily price list.
--
-- ── WHY 0052 WAS NOT ENOUGH ────────────────────────────────────────────────
-- The daily list's Corporate Actions block is a window of PENDING actions. It
-- shows a final and never the interim that came months earlier. Yield computed
-- from it alone understates, badly:
--
--   KCB   final 3.00  ->  true FY2025 total 7.00   (interim 2.00 + specials 3.00)
--   SCBK  final 23.00 ->  true FY2025 total 31.00  (interim 8.00)
--   SCOM  final 1.15  ->  true FY2026 total 2.00   (interim 0.85)
--   BAT   final 60.00 ->  true FY2025 total 70.00  (interim 10.00)
--   EABL  final 5.50  ->  true FY2025 total 8.00   (interim 2.50)
--
-- KCB's dividend yield would have rendered at less than half its real value.
--
-- ── FINANCIAL YEAR ENDS ────────────────────────────────────────────────────
-- These are NOT all December. Getting the year end wrong pairs an interim with
-- the wrong final and produces a total that belongs to no real year:
--
--   31 March     SCOM, WTK, KAPC
--   30 June      EABL, KEGN, KPLC
--   31 July      CARB
--   31 December  everything else
--
-- EABL is the trap. Its year ended 30 June 2025 (interim 2.50 + final 5.50 =
-- 8.00). Pairing the 4.00 interim declared in January 2026 with the FY2025
-- final would invent a 9.50 dividend that no company ever declared.
--
-- ── ONLY COMPLETED YEARS ARE STORED ────────────────────────────────────────
-- snapshot.ts computes dps_latest from the NEWEST financial year present. So an
-- in-progress year in this table would BECOME the latest, and its half of a
-- dividend would be published as though it were the whole thing. EABL's FY2026
-- interim (4.00, paid April 2026) and Kenya Power's FY2026 interim (0.30, paid
-- March 2026) are therefore DELIBERATELY NOT STORED: including them would make
-- dps_latest read 4.00 for EABL instead of 8.00, which is the very
-- understatement this migration exists to fix.
--
-- To surface in-progress dividends later, `stock_dividends` needs a
-- `year_complete boolean` column and snapshot.ts needs to compute dps_latest
-- from the newest COMPLETE year. That is a schema change, not a data change,
-- and it is not being smuggled in here.
--
-- ── THE `special` ROW ──────────────────────────────────────────────────────
-- The unique key is (stock_id, financial_year, kind), so a year can hold one
-- interim, one final and one special. KCB declared TWO specials in FY2025 (2.00
-- with the interim, 1.00 with the final, both tied to the NBK sale). They are
-- summed into a single 3.00 special row. The TOTAL is exact; the special row's
-- payment date is the later of the two. Flagged so nobody reads that date as
-- the date the whole 3.00 landed.
--
-- ── CONFIDENCE ─────────────────────────────────────────────────────────────
-- Amounts below come from company results announcements and the NSE daily list.
-- Where a DATE could not be confirmed from a current, named source it is NULL,
-- never guessed. A null date renders as "date not announced". An invented date
-- is a promise the company has not made.
--
-- NOT PAYING, and deliberately absent so no yield is computed for them:
--   BRIT  no dividend since 2019
--   HFCK  no FY2025 dividend found
--   KQ, SASN, UMME, SLAM, NMG, CTUM  none confirmed

-- Clear the price-list-only rows so the complete set replaces them cleanly
-- rather than half-merging with them.
delete from public.stock_dividends
 where source_url like '%10-JUL-26.pdf';

insert into public.stock_dividends
  (stock_id, financial_year, kind, dps_kes, declared_on, book_closure, payment_date, source_url)
select s.id, v.fy, v.kind, v.dps, v.declared, v.books, v.pay, v.src
from (values
  -- ── Safaricom. FY ends 31 March. FY2026 total 2.00 ──
  ('SCOM', 2026, 'interim',  0.85, date '2026-02-05', date '2026-02-26', date '2026-03-31', 'https://www.safaricom.co.ke/investor-relations'),
  ('SCOM', 2026, 'final',    1.15, date '2026-05-07', date '2026-08-04', date '2026-09-04', 'https://www.safaricom.co.ke/investor-relations'),

  -- ── EABL. FY ends 30 June. FY2025 (to 30 Jun 2025) total 8.00 ──
  ('EABL', 2025, 'interim',  2.50, null,              null,              null,              'https://www.eabl.com/investors'),
  ('EABL', 2025, 'final',    5.50, date '2025-07-31', date '2025-09-16', date '2025-10-28', 'https://www.eabl.com/investors'),

  -- ── BAT Kenya. FY2025 total 70.00 ──
  ('BAT',  2025, 'interim', 10.00, date '2025-08-13', date '2025-08-29', date '2025-09-26', 'https://www.batkenya.com/investors'),
  ('BAT',  2025, 'final',   60.00, null,              date '2026-05-08', date '2026-06-12', 'https://www.batkenya.com/investors'),

  -- ── Banks ──
  -- KCB FY2025 total 7.00. See the note on the special row above.
  ('KCB',  2025, 'interim',  2.00, date '2025-08-13', date '2025-09-03', date '2025-11-11', 'https://kcbgroup.com/investor-relations/'),
  ('KCB',  2025, 'special',  3.00, null,              null,              date '2026-05-22', 'https://kcbgroup.com/investor-relations/'),
  ('KCB',  2025, 'final',    2.00, null,              date '2026-04-02', date '2026-05-22', 'https://kcbgroup.com/investor-relations/'),

  -- Standard Chartered CUT its dividend 31 percent (45.00 -> 31.00) at a 95.5
  -- percent payout ratio. Anything assuming continuity from FY2024 overstates.
  ('SCBK', 2025, 'interim',  8.00, date '2025-08-20', date '2025-09-11', date '2025-10-07', 'https://www.sc.com/ke/investor-relations/'),
  ('SCBK', 2025, 'final',   23.00, null,              null,              null,              'https://www.sc.com/ke/investor-relations/'),

  ('SBIC', 2025, 'interim',  3.80, date '2025-08-07', date '2025-09-02', date '2025-09-29', 'https://www.stanbicbank.co.ke/kenya/personal/about-us/investor-relations'),
  ('SBIC', 2025, 'final',   18.55, date '2026-03-12', date '2026-05-15', null,              'https://www.stanbicbank.co.ke/kenya/personal/about-us/investor-relations'),

  ('NCBA', 2025, 'interim',  2.50, null,              null,              date '2025-10-02', 'https://ke.ncbagroup.com/investor-relations/'),
  ('NCBA', 2025, 'final',    4.60, null,              date '2026-04-30', date '2026-05-26', 'https://ke.ncbagroup.com/investor-relations/'),

  -- Co-op's first ever interim. Total 2.50, the biggest rise among the big banks.
  ('COOP', 2025, 'interim',  1.00, null,              date '2025-11-26', date '2025-12-04', 'https://www.co-opbank.co.ke/investor-relations/'),
  ('COOP', 2025, 'final',    1.50, date '2026-03-19', date '2026-05-04', date '2026-06-05', 'https://www.co-opbank.co.ke/investor-relations/'),

  ('IMH',  2025, 'interim',  1.50, null,              null,              date '2026-01-14', 'https://www.imbankgroup.com/ke/investor-relations/'),
  ('IMH',  2025, 'final',    2.25, null,              date '2026-04-16', date '2026-05-21', 'https://www.imbankgroup.com/ke/investor-relations/'),

  ('ABSA', 2025, 'interim',  0.20, date '2025-08-12', date '2025-09-19', date '2025-10-15', 'https://www.absabank.co.ke/investor-relations/'),
  ('ABSA', 2025, 'final',    1.85, null,              date '2026-04-30', date '2026-05-19', 'https://www.absabank.co.ke/investor-relations/'),

  -- Equity and DTB pay a SINGLE annual dividend. No interim. For these two the
  -- final really is the total, so the price list was never wrong about them.
  ('EQTY', 2025, 'final',    5.75, null,              date '2026-05-22', date '2026-06-30', 'https://equitygroupholdings.com/ke/investor-relations/'),
  ('DTK',  2025, 'final',    9.00, null,              date '2026-05-22', date '2026-06-26', 'https://dtbk.dtbafrica.com/investor-relations'),

  -- Family Bank, listed by introduction 23 June 2026. FY2025 proposed 1.20.
  -- Dates unconfirmed, so they are null.
  ('FMLY', 2025, 'final',    1.20, null,              null,              null,              'https://familybank.co.ke/investor-relations'),

  -- ── Insurers ──
  ('JUB',  2025, 'interim',  2.00, null,              null,              null,              'https://jubileeinsurance.com/ke/investor-relations/'),
  ('JUB',  2025, 'final',   13.00, date '2026-04-10', date '2026-06-11', date '2026-07-24', 'https://jubileeinsurance.com/ke/investor-relations/'),
  ('CIC',  2025, 'final',    0.13, null,              date '2026-04-23', date '2026-06-09', 'https://cic.co.ke/investor-relations/'),
  ('KNRE', 2025, 'final',    0.15, date '2026-03-27', date '2026-06-19', date '2026-07-31', 'https://kenyare.co.ke/investor-relations'),
  ('LBTY', 2025, 'final',    0.50, date '2026-03-11', date '2026-06-26', date '2026-08-30', 'https://www.libertylife.co.ke/investor-relations'),

  -- ── Energy and utilities. KEGN and KPLC end 30 June. ──
  ('KEGN', 2025, 'final',    0.90, null,              date '2025-11-27', date '2026-02-12', 'https://www.kengen.co.ke/investor-relations/'),
  ('KPLC', 2025, 'interim',  0.20, null,              null,              null,              'https://kplc.co.ke/category/view/56/investor-relations'),
  ('KPLC', 2025, 'final',    0.80, date '2025-10-07', date '2025-12-02', date '2026-01-30', 'https://kplc.co.ke/category/view/56/investor-relations'),

  ('TOTL', 2025, 'final',    3.45, date '2026-04-30', date '2026-06-25', date '2026-07-31', 'https://totalenergies.co.ke/investors'),

  -- ── Industrials, agriculture, other ──
  ('CRWN', 2025, 'final',    3.00, date '2026-05-25', date '2026-06-26', date '2026-08-31', 'https://crownpaints.co.ke/investor-relations/'),
  ('BOC',  2025, 'final',   10.35, date '2026-04-16', date '2026-05-31', date '2026-07-21', 'https://www.boc.co.ke/investors'),
  ('CARB', 2025, 'final',    2.00, date '2025-11-03', null,              null,              'https://carbacid.co.ke/investor-relations/'),
  ('KUKZ', 2025, 'final',   16.00, date '2026-03-25', date '2026-05-29', date '2026-06-15', 'https://www.kakuzi.co.ke/investor-relations/'),
  ('TPSE', 2025, 'final',    0.35, date '2026-04-30', date '2026-06-26', date '2026-07-30', 'https://www.serenahotels.com/investor-relations'),
  ('NSE',  2025, 'final',    0.73, date '2026-03-27', date '2026-05-21', date '2026-07-31', 'https://www.nse.co.ke/investor-relations/'),
  ('NSE',  2025, 'special',  0.27, date '2026-03-27', date '2026-05-21', date '2026-07-31', 'https://www.nse.co.ke/investor-relations/'),
  ('PORT', 2025, 'final',    1.25, date '2026-06-22', null,              null,              'https://eapcc.co.ke/investor-relations/'),

  -- Williamson and Kapchorua end 31 MARCH, so this is FY2026, not FY2025.
  -- 0052 labelled these 2025. That was wrong and is corrected here.
  ('WTK',  2026, 'final',   15.00, date '2026-06-26', date '2026-07-31', null,              'https://www.williamsontea.com/investors'),
  ('KAPC', 2026, 'final',   30.00, date '2026-06-26', date '2026-07-31', null,              'https://www.kapchorua.com/investors')
) as v(ticker, fy, kind, dps, declared, books, pay, src)
join public.stocks s on s.ticker = v.ticker
on conflict (stock_id, financial_year, kind) do update set
  dps_kes      = excluded.dps_kes,
  declared_on  = excluded.declared_on,
  book_closure = excluded.book_closure,
  payment_date = excluded.payment_date,
  source_url   = excluded.source_url,
  updated_at   = now();

-- Every ticker above must exist in `stocks` or the join drops its dividend in
-- silence. Count the rows and fail loudly if any went missing.
do $$
declare n integer;
begin
  select count(*) into n from public.stock_dividends;
  if n <> 43 then
    raise exception
      'expected 43 dividend rows, have %. A ticker in the list is missing from `stocks`.', n;
  end if;
end;
$$;

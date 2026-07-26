-- etica_special_multi_asset_return_basis.sql
--
-- Corrects the fund in the screenshot. Run AFTER 0074.
--
-- The page was never rendering the wrong thing. company_page.dart gates every
-- yield surface on `fund.showsYield`, and _ProjectionSectionState.build opens
-- with `if (!fund.showsYield || rate == null) return const SizedBox.shrink()`.
-- The withholding-tax triad, the rate chart, the real-return bar and the
-- projection are all inside that same branch.
--
-- So the app showed a gross yield, deducted tax from it and compounded it over
-- two years because THE ROW SAID IT WAS A YIELD. basis = 'yield' and
-- current_rate = 20.36 on a fund whose fact sheet publishes neither. Every
-- wrong number on that screen follows correctly from those two fields.
--
-- Source: Etica Unit Trust Funds Fact Sheet, 30 June 2026, sheet 05.
--
--   Periodic Net Return, Q2 2026   5.23%
--   Q1 2026                        5.02%
--   Year to date (2026)           10.51%
--   2026 Annualized               22.13%   <- the manager's own extrapolation
--   Fund inception            November 2025
--   Lock-in                     6 months
--   Compounding          Calendar quarterly
--   Disclaimer: "The yield quoted is net yield (Net of all fees and taxes)"
--
-- 20.36% appears nowhere on that sheet. Neither does any figure the app could
-- have derived honestly: the fund has existed for eight months and has two
-- completed quarters behind it.


-- ── Pre-flight. Run this alone first and read the output ────────────────────
--
-- Confirm exactly one row comes back and that its id is what you expect before
-- running the transaction below.
--
--   select id, name, manager, company_id, currency, fund_type, basis,
--          current_rate, net_of, return_period, mgmt_fee, min_invest,
--          lock_in_months, return_ytd, inception_date
--   from   public.funds
--   where  kind = 'fund'
--     and  name ilike '%etica%'
--     and  name ilike '%multi%asset%';


begin;

-- Pinned to a single row via a CTE rather than repeating the ilike in four
-- statements, so every write below touches the same fund or none of them. If
-- the pre-flight returned zero rows or more than one, this whole block is a
-- no-op or an error, never a partial edit.
create temporary table _f on commit drop as
select id
from   public.funds
where  kind = 'fund'
  and  name ilike '%etica%'
  and  name ilike '%multi%asset%';

-- Refuse to continue on anything other than exactly one match. Better to fail
-- loudly here than to quietly retype half the special funds at Etica.
do $$
declare n int;
begin
  select count(*) into n from _f;
  if n <> 1 then
    raise exception 'expected exactly 1 matching fund, found %', n;
  end if;
end $$;


-- ── 1. Tell the app what kind of number this fund publishes ────────────────
--
-- current_rate goes to NULL, deliberately and not to zero. There is no annual
-- yield here to hold. Leaving a stale 20.36 in the column while flipping basis
-- would leave the app one `?? currentRate` fallback away from printing it
-- again, and the admin Funds table reads current_rate directly, so a blank cell
-- there is now the honest state rather than a regression.

update public.funds f
set    basis         = 'return',
       return_period = 'quarter',
       return_as_of  = date '2026-06-30',
       net_of        = 'fees_and_tax',
       current_rate  = null,
       fee_kind      = 'mgmt',
       lock_in_months = coalesce(f.lock_in_months, 6),
       min_invest     = coalesce(f.min_invest, 250000),
       mgmt_fee       = coalesce(f.mgmt_fee, 5.00),
       inception_date = coalesce(f.inception_date, date '2025-11-01')
from   _f
where  f.id = _f.id;


-- ── 2. The period series ───────────────────────────────────────────────────
--
-- Two quarters and the year-to-date figure they compose. The YTD row shares a
-- period_end with the Q2 row, which is why `period` is part of the primary key
-- rather than a property of the row.
--
-- 22.13% is NOT written. It is 10.51% over half a year extended across the
-- other half, on a fund with no other half to observe. It belongs on the page
-- as a manager-attributed note, which is how the mockup renders it, and it must
-- never enter a series the app sorts, compounds or charts.

insert into public.return_history (fund_id, period_end, period, net_pct, net_of, source)
select _f.id, v.period_end, v.period, v.net_pct, 'fees_and_tax', 'etica-factsheet-2026-06-30'
from   _f,
       (values
         (date '2026-03-31', 'quarter',  5.02),
         (date '2026-06-30', 'quarter',  5.23),
         (date '2026-06-30', 'ytd',     10.51)
       ) as v(period_end, period, net_pct)
on conflict (fund_id, period_end, period) do nothing;


-- ── 3. Allocation, from the same sheet ─────────────────────────────────────
--
-- funds.composition is the 8-class CMA taxonomy in absolute shillings and this
-- is a percentage split of four categories from a manager's own sheet, so it
-- does not go there. Listed stocks map to `listed`, government securities to
-- `gok`, cash to `cash`; commercial paper has no CMA class of its own. Written
-- to geography? No. It is neither. Left for the composition lane to handle
-- properly rather than forced into the nearest-looking column.
--
--   Cash & call deposits  14%
--   Listed stocks         16%
--   Commercial papers     24%
--   Government securities 46%


-- ── 4. Custody, guarded so nothing already set is overwritten ──────────────

update public.companies c
set    trustee   = coalesce(c.trustee,   'Co-operative Bank Kenya Ltd'),
       custodian = coalesce(c.custodian, 'Equity Bank Kenya Ltd'),
       auditor   = coalesce(c.auditor,   'RSM Eastern Africa')
from   public.funds f, _f
where  f.id = _f.id
  and  c.id = f.company_id;

commit;


-- ── After applying ─────────────────────────────────────────────────────────
--
-- No backfill script is needed here, because akiba_backfill_current_rate.sql
-- promotes the freshest rate_history point into current_rate and this fund now
-- has no rate_history and no current_rate by design. Running it is harmless;
-- it simply will not match this row.
--
-- Rebuild the snapshot in admin. Until snapshot.ts publishes return_history the
-- app will read basis='return', fall through `showsYield` to the NAV branch,
-- and render a dash with no price. That is a truthful empty state and a strict
-- improvement on a fabricated 20.36%, but it is not the finished page.
--
-- Verify:
--
--   select f.id, f.basis, f.net_of, f.return_period, f.current_rate,
--          r.period, r.period_end, r.net_pct
--   from   public.funds f
--   left   join public.return_history r on r.fund_id = f.id
--   where  f.name ilike '%etica%' and f.name ilike '%multi%asset%'
--   order  by r.period_end, r.period;
--
-- And the wider sweep, because this fund is unlikely to be the only one
-- carrying a yield it does not have:
--
--   select id, name, currency, basis, net_of, current_rate, return_ytd
--   from   public.funds
--   where  kind = 'fund'
--     and  fund_type in ('special','equity','balanced')
--     and  basis = 'yield'
--   order  by current_rate desc nulls last;

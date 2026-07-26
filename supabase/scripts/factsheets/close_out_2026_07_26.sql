-- close_out_2026_07_26.sql
--
-- The last two things that are visibly wrong to a user today.
--
-- Everything else outstanding is absence: a fund with no data, a widget not yet
-- built. These two are PRESENCE of something false, which is a different
-- category, and the reason they go before any remaining feature work.


-- ═══ 1. IS OAK STILL WRONG? ════════════════════════════════════════════════
--
-- Run this first and read it. It answers the question rather than assuming.
--
--   select id, basis, current_rate, source_type,
--          (select count(*) from public.return_history r where r.fund_id = f.id) as periods
--   from   public.funds f where f.id = 'faida-sp-kes';
--
-- WRONG  basis='yield', current_rate=4.72, periods=0
--        4.72 is a quarterly figure being taxed and compounded across two
--        years on a live fund page. Run
--        scripts/factsheets/oak_special_return_basis.sql, which is idempotent
--        and safe to run twice.
--
-- RIGHT  basis='return', current_rate=null, periods=9
--        Nothing to do.


-- ═══ 2. THE FX PLACEHOLDER ═════════════════════════════════════════════════
--
-- fx_rates carries USD/KES at exactly 100 with a null source, one row per
-- weekday since early July. The real rate is about 129.5, confirmed by three
-- fund managers independently in this month's fact sheets.
--
-- Every dollar holding in every portfolio is understated by roughly 23%.
--
-- 100 with no source is not a bad fetch. It is a DEFAULT, written when the
-- fetch failed, and that is the actual defect: a gap shows up as missing and
-- gets fixed, while a placeholder shows up as an answer and does not.

begin;

delete from public.fx_rates
where pair = 'USD/KES' and rate = 100 and source is null;

-- Seven real month-end marks from the fact sheets in this thread. Each printed
-- by a fund manager in a document they signed.
--
-- NOT a backfill. Seven scattered points is not the thirteen consecutive
-- month-ends the currency card needs. They are here so the table holds
-- something true instead of something invented, and as a yardstick: if
-- backfill-fx.ts lands and disagrees with these by more than a shilling, the
-- import is wrong, not the sheets.
insert into public.fx_rates (pair, as_of, rate, source) values
  ('USD/KES', date '2023-07-31', 142.30, 'factsheet:cytonn-2023-08'),
  ('USD/KES', date '2023-08-31', 145.40, 'factsheet:cytonn-2023-08'),
  ('USD/KES', date '2025-04-30', 129.34, 'factsheet:old-mutual-2025-04'),
  ('USD/KES', date '2025-08-31', 129.20, 'factsheet:cytonn-2025-08'),
  ('USD/KES', date '2026-03-31', 129.93, 'factsheet:madison-2026-03'),
  ('USD/KES', date '2026-05-31', 129.55, 'factsheet:madison-2026-05'),
  ('USD/KES', date '2026-06-30', 129.50, 'factsheet:african-alliance-2026-06')
on conflict (pair, as_of) do update
  set rate = excluded.rate, source = excluded.source;

commit;


-- ═══ 3. STOP IT COMING BACK ════════════════════════════════════════════════
--
-- Deleting the rows fixes today. This fixes tomorrow, and it is the part worth
-- keeping: the aggregator runs daily and will write another placeholder on its
-- next failed fetch unless something refuses it.
--
-- Two constraints, both cheap:
--
--   A rate must carry a source. Provenance is not optional on a number the
--   portfolio maths multiplies by. An unattributed rate is exactly the shape
--   of a default.
--
--   USD/KES must be plausible. The shilling has traded between about 100 and
--   165 in living memory and 100.0000 flat is not a market rate, it is a
--   round number somebody reached for. This is deliberately wide: it is here
--   to catch a placeholder, not to second-guess the market.

alter table public.fx_rates
  drop constraint if exists fx_rates_source_required;
alter table public.fx_rates
  add constraint fx_rates_source_required check (source is not null and source <> '');

alter table public.fx_rates
  drop constraint if exists fx_rates_usdkes_plausible;
alter table public.fx_rates
  add constraint fx_rates_usdkes_plausible
  check (pair <> 'USD/KES' or (rate > 60 and rate < 400));

comment on constraint fx_rates_source_required on public.fx_rates is
  'A rate with no source is a default rather than a reading. Fifteen rows of '
  'USD/KES at exactly 100, all with a null source, sat in this table for three '
  'weeks understating every dollar holding by about a quarter.';


-- ═══ 4. THE WRITER ═════════════════════════════════════════════════════════
--
-- Not fixed here, because it is code rather than data.
--
-- supabase/functions/scrape-aggregator/index.ts calls fetchUsdKes() from
-- _shared/fx.ts and upserts whatever point comes back. Since the stored rows
-- have a null source, fx.ts is building a point with no provenance, which
-- means it is constructing one on a path that has no real reading to report.
--
-- The constraint above now makes that path fail loudly instead of writing 100,
-- and the aggregator already logs fx errors into scraper_runs, so the next run
-- will name the problem in the admin rather than hiding it in the data.
--
-- The real fix is one line in fx.ts: on failure, return no point at all.
--
--
-- ── Verify ─────────────────────────────────────────────────────────────────
--
--   select pair, count(*), min(rate), max(rate), min(as_of), max(as_of)
--   from   public.fx_rates group by pair;
--
-- Expect USD/KES: 7 rows, 129.20 to 145.40. Any 100 means the delete missed
-- something. The constraint should now make a new one impossible.
--
--   insert into public.fx_rates (pair, as_of, rate, source)
--   values ('USD/KES', current_date, 100, null);
--   -- expect: violates check constraint "fx_rates_source_required"

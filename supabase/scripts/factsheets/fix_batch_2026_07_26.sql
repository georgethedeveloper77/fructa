-- fix_batch_2026_07_26.sql
--
-- Four things, found by the verification query and the Config screenshots.
--
--
-- 1. OAK NEVER RAN. `faida-sp-kes` is still basis='yield', current_rate=4.72,
--    periods=0. Everything else from that session landed: Cytonn, CIC,
--    Lofty-Corban Global, Etica, MansaX. Oak alone did not, so it is still
--    taxing a quarterly return and compounding it two years forward.
--
--    Run oak_special_return_basis.sql. It is unchanged and still correct. This
--    file does not repeat it, because a second copy of the same migration is
--    how two versions of the truth start.
--
--
-- 2. ETICA IS STILL ON source_type='auto'.
--
--    My omission. MansaX, Oak, CIC and Lofty-Corban Global were all set to
--    manual so no scraper could write a rate back to a fund that quotes none.
--    Etica was not, and it has been sitting there since with the aggregator
--    free to put a number into current_rate and silently undo the basis fix.
--
--    That is not hypothetical: it is precisely how MansaX ended up with a
--    quarterly return in current_rate in the first place.

update public.funds set source_type = 'manual'
where id = 'etica-sp-kes' and basis = 'return';

-- And the general form, so this cannot be forgotten one fund at a time. A fund
-- that publishes no yield has nothing a yield scraper can legitimately find.
update public.funds set source_type = 'manual'
where kind = 'fund' and basis in ('return', 'nav') and source_type = 'auto';


-- ── 3. THE FX PLACEHOLDER ──────────────────────────────────────────────────
--
-- fx_rates holds fifteen rows of exactly 100 with source=null. The real rate is
-- about 129.5, and your own Config already knows it: market.usd_kes reads
-- 129.3, published 7 July.
--
-- So the app has TWO exchange rates and they disagree by 29%. Whichever surface
-- reads fx_rates is wrong by that much on every dollar holding, and it has been
-- since at least 3 July.
--
-- 100.0000 with a null source is not a rate that was fetched badly. It is a
-- DEFAULT that something writes when a fetch fails. That pattern is the actual
-- bug and it will repeat on another table: find where it is written and make it
-- write nothing. A gap shows up as missing; a placeholder shows up as an answer.
--
-- Most likely inside the aggregator, since the Scrapers page says the exchange
-- rate "Runs inside the MMF aggregator" and its quota reads "Never succeeded".

delete from public.fx_rates where pair = 'USD/KES' and rate = 100 and source is null;

-- Seven real month-end marks, read off the fact sheets in this thread. Primary
-- sources, each one printed by a fund manager in a document they signed.
--
-- NOT a backfill: seven scattered points is not the thirteen consecutive
-- month-ends the currency card needs. They are here so the table stops holding
-- a fiction, and as a yardstick for whatever backfill-fx.ts produces. If the
-- CBK CSV lands and disagrees with these by more than a shilling, something is
-- wrong with the import rather than with the sheets.

insert into public.fx_rates (pair, as_of, rate, source) values
  ('USD/KES', date '2023-07-31', 142.30, 'factsheet:cytonn-2023-08'),
  ('USD/KES', date '2023-08-31', 145.40, 'factsheet:cytonn-2023-08'),
  ('USD/KES', date '2025-04-30', 129.34, 'factsheet:old-mutual-2025-04'),
  ('USD/KES', date '2025-08-31', 129.20, 'factsheet:cytonn-2025-08'),
  ('USD/KES', date '2026-03-31', 129.93, 'factsheet:madison-2026-03'),
  ('USD/KES', date '2026-05-31', 129.55, 'factsheet:madison-2026-05'),
  ('USD/KES', date '2026-06-30', 129.50, 'factsheet:african-alliance-2026-06')
on conflict do nothing;


-- ── 4. THE CONFIG BOARD ────────────────────────────────────────────────────
--
-- Not written here, because these are decisions rather than corrections and the
-- Config page is the right place to make them. Listing them so they are not
-- lost:
--
--   benchmark.tbill_364 = 8.87%, flagged STALE. Seeded in 0023 from the 15 June
--   auction. The African Alliance June 2026 sheet puts the 91, 182 and 364 day
--   papers between 8.4% and 9.0%, so 8.87 is still about right, but the stamp
--   needs refreshing or the app is quoting a number it cannot vouch for.
--
--   market.aum_by_fund_type has 5 rows and market.asset_classes is unset. These
--   are the CMA Q1 2026 keys that would repoint the fund-type donut at the
--   authoritative AUM split. The data has been validated and waiting for a
--   while now.
--
--   search.placeholder and search.suggestions are unset and the editor is
--   showing "Copy can't be empty". Harmless: the app falls back to its baked-in
--   value. Worth setting or worth deleting the keys, but not worth a red field
--   sitting on the board indefinitely.
--
--   market.usd_kes = 129.3, last published 7 July. Correct, and it is the
--   reason to be sure about which surface reads which source. Once fx_rates is
--   backfilled properly, one of the two should stop existing.


-- ── Verify ─────────────────────────────────────────────────────────────────
--
--   select id, basis, current_rate, source_type,
--          (select count(*) from return_history r where r.fund_id = f.id) as periods
--   from   public.funds f
--   where  kind = 'fund' and fund_type = 'special' and basis in ('return','nav')
--   order  by source_type, id;
--
-- Every row should read source_type='manual'. Any 'auto' left is a fund the
-- scraper can still overwrite.
--
--   select pair, min(as_of), max(as_of), count(*), min(rate), max(rate)
--   from   public.fx_rates group by pair;
--
-- Expect seven rows between 129.20 and 145.40. A 100 anywhere means the
-- placeholder writer ran again and still needs finding.

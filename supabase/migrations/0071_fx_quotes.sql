-- 0071_fx_quotes.sql
-- fx_rates gains the two sides of the quote plus provenance.
--
-- 0010 stored a single `rate`, which is the CBK indicative mean. The currency
-- comparison needs the buy and sell legs as well, because the round trip
-- through a bank is a real cost and modelling it as a flat assumption is
-- weaker than measuring it. CBK publishes all three on the daily indicative
-- rates sheet, so the columns are free once the backfill runs.
--
-- Naming follows the bank's side of the trade, which is also CBK's:
--   bid = what a bank BUYS a dollar from you at   (below the mean)
--   ask = what a bank SELLS a dollar to you at    (above the mean)
-- A user converting KES into USD pays `ask`. Converting back, they get `bid`.
--
-- All three columns are nullable so the existing aggregator writer, which
-- only carries `rate`, keeps working untouched.

alter table public.fx_rates add column if not exists bid    numeric;
alter table public.fx_rates add column if not exists ask    numeric;
alter table public.fx_rates add column if not exists source text;

comment on column public.fx_rates.rate   is 'Indicative mean for the pair.';
comment on column public.fx_rates.bid    is 'Bank buys the base currency at this rate. Null when only a mean is known.';
comment on column public.fx_rates.ask    is 'Bank sells the base currency at this rate. Null when only a mean is known.';
comment on column public.fx_rates.source is 'cbk-daily | cbk-backfill | open-er-api. Null on rows written before this migration.';

-- The app reads "latest N points for one pair, newest first" on every snapshot
-- rebuild. The primary key is (pair, as_of) ascending, which the planner can
-- use but has to walk backwards; an explicit descending index keeps the
-- five-year series read cheap once the backfill lands a few thousand rows.
create index if not exists fx_rates_pair_asof_desc_idx
  on public.fx_rates (pair, as_of desc);

-- Guard against a bad parse writing a nonsense quote. The band matches the
-- `plausible()` check already in _shared/cbk-fx.ts, so a source that starts
-- returning percentages or cents fails loudly at the insert rather than
-- silently poisoning a chart.
alter table public.fx_rates
  drop constraint if exists fx_rates_rate_band;
alter table public.fx_rates
  add constraint fx_rates_rate_band
  check (rate > 0 and rate < 100000);

-- bid must not exceed ask when both are present. A crossed quote is always a
-- parse error, never a real market.
alter table public.fx_rates
  drop constraint if exists fx_rates_quote_ordered;
alter table public.fx_rates
  add constraint fx_rates_quote_ordered
  check (bid is null or ask is null or bid <= ask);

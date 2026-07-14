-- 0070_fund_nav.sql
--
-- The four non-MMF types (fixed income, equity, balanced, priced special) quote
-- a UNIT PRICE, not a yield. Three things are missing before any of them can be
-- rendered honestly.
--
--   1. There is no price series. funds.price_per_unit is a single scalar: ONE
--      point. You cannot draw a line through one point, so there is no chart, no
--      sparkline and no growth backtest. stock_history exists for the NSE and
--      rate_history exists for yields; funds have nothing.
--
--   2. There is no duration. Duration is THE number for a bond fund: it is the
--      whole reason a fund paying 5.1% income can post a NEGATIVE total return
--      while one paying 4.4% posts +12.6%. Without it the Fixed Income list
--      cannot explain its own sort order.
--
--   3. There is no credit quality. The share of a bond fund that is NOT
--      government paper is where the extra income comes from and where the
--      default risk lives. It is one number and it changes the decision.


-- ── 1. The price series ────────────────────────────────────────────────────
--
-- Deliberately NOT called price_kes, and this is not pedantry. stock_history
-- calls its column close_kes, which is harmless for the NSE because every
-- counter is priced in shillings, but funds are not: lofty-corban-fi-usd quotes
-- its NAV in dollars. A currency baked into a column NAME is the same defect as
-- a currency baked into a value string, which is what 0069 spent a whole
-- migration undoing. The unit is funds.currency, on the fund's own row.

create table if not exists nav_history (
  fund_id text not null references funds (id) on delete cascade,
  as_of   date not null,
  price   numeric not null check (price > 0),
  source  text,
  primary key (fund_id, as_of)
);

comment on table nav_history is
  'End-of-period NAV per unit for a basis=''nav'' fund. Mirrors rate_history '
  '(yields) and stock_history (NSE closes). Price is in the FUND''S OWN currency '
  '(see funds.currency), never converted.';

create index if not exists nav_history_fund_asof_idx
  on nav_history (fund_id, as_of desc);

-- A price of zero is not a low price, it is a missing one, and the check above
-- refuses it. Same rule as Stock.hasPrice: "a share that did not trade did not
-- trade at nothing."


-- ── 2. Bond-fund fields ────────────────────────────────────────────────────

alter table funds add column if not exists duration_years numeric;
alter table funds add column if not exists credit_quality jsonb;

comment on column funds.duration_years is
  'Modified duration, years. The rate sensitivity of a bond fund: rates up 1 '
  'point, unit price down roughly this many percent. Null for anything that is '
  'not a bond fund, and null is rendered as unknown, never as zero.';

comment on column funds.credit_quality is
  'Share of the portfolio by credit standing, as percentages summing to ~100. '
  'Keys: gov, aa, a, bbb, unrated. Shaped like funds.composition. A government '
  'cannot run out of shillings; a company can, and this is the line between them.';


-- ── 3. Seed the series from the scalar we already hold ─────────────────────
--
-- Every fund with a price and a date contributes its first point, so the series
-- starts from what is already known rather than from nothing. One point still
-- draws no line, but it means the second fact sheet completes a chart instead
-- of starting one.

insert into nav_history (fund_id, as_of, price, source)
select f.id, f.price_as_of::date, f.price_per_unit, 'seed'
from   funds f
where  f.kind = 'fund'
  and  f.basis = 'nav'
  and  f.price_per_unit is not null
  and  f.price_per_unit > 0
  and  f.price_as_of is not null
on conflict (fund_id, as_of) do nothing;


-- ── 4. The contradiction ───────────────────────────────────────────────────
--
-- lofty-corban-sp-kes-special carries basis='nav' AND current_rate=8.92 at the
-- same time. Those cannot both be true. Because Fund.showsYield is false for a
-- NAV fund, the app renders a DASH on a fund that has a real 8.92% yield and the
-- words "Money Market" in its name, while admin shows "no price" because no unit
-- price is set either. The number exists and nobody can see it.
--
-- Guarded, not blanket: it only touches rows that are actually in the
-- contradictory state (basis nav, a rate, and no price). A NAV fund with a real
-- unit price is left alone, because there the rate is the stale value and the
-- price is the truth, and this migration is not qualified to decide which.

update funds
set    basis = 'yield'
where  kind = 'fund'
  and  basis = 'nav'
  and  current_rate is not null
  and  current_rate > 0
  and  price_per_unit is null;


-- ── After applying ─────────────────────────────────────────────────────────
--
-- Any row still holding both a rate and a price is a genuine conflict a human
-- must resolve, so it is reported rather than guessed at:
--
--   select id, name, basis, current_rate, price_per_unit
--   from   funds
--   where  kind = 'fund'
--     and  basis = 'nav'
--     and  current_rate is not null
--     and  price_per_unit is not null;
--
-- And the sourcing board: what is still missing before the four new tabs can
-- render anything at all.
--
--   select fund_type, basis, count(*) as funds,
--          count(price_per_unit)  as have_price,
--          count(return_1y)       as have_1y,
--          count(bench_1y)        as have_bench,
--          count(duration_years)  as have_duration
--   from   funds
--   where  kind = 'fund'
--     and  fund_type in ('fixed_income','equity','balanced','special')
--   group  by 1, 2
--   order  by 1, 2;

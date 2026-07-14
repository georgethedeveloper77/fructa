-- 0064_fund_aum_native.sql
--
-- funds.aum is text, so it holds whatever anyone typed. Today it holds two
-- mutually incompatible representations of the same fact:
--
--   lofty-corban-mmf-kes  KES  'KES 3.80 billion'   prose, currency inside the string
--   lofty-corban-mmf-usd  USD  '1150000'            naked integer, unit declared by nothing
--
-- Neither can be sorted, summed, ranked or validated, and the two cannot be
-- compared with one another at all. Read naively as numbers, the KES fund looks
-- 3,304 times the size of the USD fund. It is roughly 26 times the size. The
-- entire error is the exchange rate.
--
-- The currency does not belong in the value. funds.currency already carries it.
-- Storing it twice, in two formats, with nothing keeping them in sync, is how a
-- KES figure ends up sitting on a dollar fund with nothing to catch it.
--
-- Denominated in the fund's OWN currency, never KES-converted. Converting at
-- write time would freeze an exchange rate into a stored column, and a dollar
-- fund's recorded size would then change every day the shilling moves without
-- the fund changing at all. Store the fact; convert at read time.

alter table funds add column if not exists aum_native numeric;

comment on column funds.aum_native is
  'Fund AUM in the fund''s own currency (see funds.currency). Never KES-converted: '
  'freezing an FX rate into a stored column makes a dollar fund''s size drift every '
  'day the shilling moves. Cross-currency comparison converts at read time.';


-- ── Backfill ───────────────────────────────────────────────────────────────
--
-- Parses the shapes actually found in the wild: an optional currency code, a
-- number with optional thousands separators, and an optional magnitude word or
-- suffix (billion / bn / b / million / m / thousand / k).
--
-- The safety rule, and the whole point of this migration: a row whose embedded
-- currency code CONTRADICTS funds.currency is NOT converted. It is left behind
-- for a human to look at.
--
-- That is deliberate, and it is the opposite of what the bulk importer does
-- today. ImportFundDetails.parseAmount runs `.replace(/kes/i, "")` on every
-- input, so pasting 'KES 5M' against a USD fund silently imports 5,000,000 as
-- DOLLARS. Guessing a unit is exactly the failure this migration exists to end,
-- so this will not guess either.

with parsed as (
  select
    f.id,
    f.currency,
    f.aum,
    upper((regexp_match(f.aum, '^\s*([A-Za-z]{3})[\s.]'))[1])                        as embedded_ccy,
    (regexp_match(f.aum, '([0-9][0-9,]*(?:\.[0-9]+)?)'))[1]                          as num_txt,
    lower(coalesce((regexp_match(f.aum, '(?:^|[^A-Za-z])(billion|million|thousand|bn|[bmk])\s*$', 'i'))[1], '')) as mag
  from funds f
  where f.kind = 'fund'
    and f.aum is not null
    and btrim(f.aum) <> ''
    and f.aum_native is null
),
scaled as (
  select
    id,
    currency,
    aum,
    embedded_ccy,
    replace(num_txt, ',', '')::numeric
      * case mag
          when 'billion'  then 1e9
          when 'bn'       then 1e9
          when 'b'        then 1e9
          when 'million'  then 1e6
          when 'm'        then 1e6
          when 'thousand' then 1e3
          when 'k'        then 1e3
          else 1
        end as value
  from parsed
  where num_txt is not null
    -- no embedded code, or one that AGREES with the fund's own currency
    and (embedded_ccy is null or embedded_ccy = currency)
)
update funds f
set    aum_native = s.value
from   scaled s
where  f.id = s.id
  and  s.value > 0;


-- ── The second AUM column ──────────────────────────────────────────────────
--
-- funds.aum_kes is a SECOND store of the same fact, written only by the bulk
-- importer (applyFundImport), and named for a currency it does not enforce. The
-- importer drops the raw parsed number straight into it whatever the fund is
-- denominated in, and stamps the text column via aumText(), which hardcodes
-- 'KES' unconditionally. So importing AUM against a dollar fund files dollars
-- under aum_kes and labels them 'KES 1M'.
--
-- Meanwhile previewFundImport diffs against aum_kes while updateFund writes aum,
-- so the two admin paths cannot see each other's work at all.
--
-- For a KES fund, aum_kes IS the native value. Take it.

update funds
set    aum_native = aum_kes
where  kind = 'fund'
  and  aum_native is null
  and  aum_kes is not null
  and  aum_kes > 0
  and  currency = 'KES';

-- For a NON-KES fund, a value in aum_kes is not converted. That number is either
-- the fund's own currency mislabelled (which is what the importer actually does)
-- or a genuine KES conversion (which is what the column name claims). Nothing in
-- the row distinguishes the two, and guessing a unit is the precise failure this
-- migration exists to end. It goes to a human.


-- ── What did not convert ───────────────────────────────────────────────────
--
-- Run this after applying. Every row it returns needs a human: no parseable
-- number, an embedded currency contradicting the fund's own, or a foreign-currency
-- fund carrying a value in the KES-named column. None of them is safe to guess.
--
--   select id, name, currency, aum, aum_kes
--   from   funds
--   where  kind = 'fund'
--     and  aum_native is null
--     and  (
--           (aum is not null and btrim(aum) <> '')
--        or  aum_kes is not null
--     );
--
-- Both old columns are left in place and untouched. Nothing reads either one:
-- they are absent from FUND_FIELDS in snapshot.ts and from the Fund model. Drop
-- them in a later migration once aum_native has been eyeballed, rather than
-- destroying the only copy of the source values in the same breath as the
-- conversion that reads them.

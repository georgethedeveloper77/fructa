-- 0075_return_history_since_inception.sql
--
-- One value, added to one check constraint, for a reason worth writing down.
--
-- The growth chart on a basis='return' fund draws what an amount invested at
-- inception is worth now. Two ways to get that number, and they disagree.
--
-- COMPOUNDED. Multiply the stored period returns together. MansaX KES publishes
-- calendar-year net returns of 19.01, 18.75, 15.45, 15.59, 18.01, 19.53 and
-- 20.74, plus 4.74 for Q1 2026. Compounded, a million becomes about 3,365,000.
--
-- PUBLISHED. The same fact sheet prints the endpoint directly: KES 3,594,335
-- after fees, by 31 March 2026.
--
-- The gap is about 230,000 shillings, roughly 7%, and it is not an error in
-- either figure. The published line is an actual monthly account track; the
-- annual percentages are each rounded to two places and then multiplied, and
-- rounding compounds along with the returns. The manager's own number is the
-- one that was lived; ours is the one that was inferred.
--
-- So compounding is the FALLBACK, used when a manager publishes no endpoint,
-- and it needs to be labelled as derived when it runs. When an endpoint IS
-- published it wins, and this is where it goes: a single row carrying the total
-- return over the fund's whole life, from which the app reconstructs the amount
-- against inception_date and a round nominal base.
--
-- Stored as a percentage rather than as a pair of amounts because 1,000,000 and
-- 3,594,335 are a presentation choice, not a fact about the fund. The fact is
-- +259.43%. A USD fund publishes the same fact against a 10,000 base, and
-- storing the base would mean every consumer had to know which one it was.
--
-- NOTE: `since_inception` was already legal in funds.return_period from 0074.
-- It was missing here, which is an inconsistency between a column and the table
-- it describes, and exactly the sort of thing that only surfaces as a
-- constraint violation months later with a fact sheet open and no idea why.

alter table public.return_history
  drop constraint if exists return_history_period_check;

alter table public.return_history
  add constraint return_history_period_check
  check (period in ('month', 'quarter', 'half', 'year', 'ytd', 'since_inception'));

comment on column public.return_history.period is
  'The kind of period this row measures. month | quarter | half | year | ytd are '
  'closed periods and compose a series. since_inception is a single cumulative '
  'total over the fund''s whole life, published by the manager, and is NOT part '
  'of the series: charting it beside quarters would put a 259% bar next to a '
  '4.74% one. It exists so the growth card can show the manager''s own endpoint '
  'rather than the app''s compounded approximation of it.';


-- ── The rule the app follows ───────────────────────────────────────────────
--
--   1. A since_inception row exists      -> use it, attribute it to the manager.
--   2. It does not                       -> compound the closed periods and say
--                                           so in the caption.
--   3. Fewer than four closed periods    -> no chart. Two points is not a trend,
--                                           it is two points.
--
-- And a trap for whoever writes the growth card. MansaX prints "the average
-- annual net return earned since the Fund's inception is 18.18%". That is the
-- ARITHMETIC MEAN of its calendar-year returns, not a growth rate. The compound
-- annual rate implied by 1,000,000 becoming 3,594,335 over 87 months is about
-- 19.3%. Both are defensible figures and they are different figures, so the app
-- computes and labels the compound rate from the stored total and never
-- republishes the mean as though money had grown at it.


-- ── Verify ─────────────────────────────────────────────────────────────────
--
--   insert into public.return_history
--     (fund_id, period_end, period, net_pct, net_of, source)
--   values
--     ('probe', current_date, 'since_inception', 259.43, 'fees', 'probe');
--   -- expect: insert or update on table "return_history" violates foreign key
--   -- constraint, NOT a check constraint violation on period.

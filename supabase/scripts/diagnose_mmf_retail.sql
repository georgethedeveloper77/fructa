-- Read-only. Run this FIRST. It changes nothing.
--
-- The Markets list hides any fund with retail = false. The code comment on that
-- filter says it exists to hide "tiny AUM, USD-only duplicates", so USD money
-- market funds were very likely switched off deliberately, back when a USD
-- share class was treated as noise rather than as its own instrument.
--
-- This shows the whole money market board with that flag exposed, so you can see
-- which funds the app is refusing to list and decide fund by fund. Anything with
-- in_app = false and a live rate is a fund you are publishing data for and then
-- hiding.

select
  currency,
  retail                                as in_app,
  status,
  current_rate,
  min_invest,
  name,
  manager,
  id
from   funds
where  fund_type = 'mmf'
  and  kind = 'fund'
order by
  currency,
  retail desc,
  current_rate desc nulls last;


-- Summary: how many money market funds per currency does the app actually list?
--
-- If listed = 0 for USD, the currency chip was appearing on the strength of
-- funds the list would never show. That is the bug in markets_controller, and it
-- is fixed in this delivery: after the fix, a currency with nothing to list gets
-- no chip. But the funds themselves still will not appear until the flag is
-- flipped, which is the half this file is for.

select
  currency,
  count(*)                                          as total,
  count(*) filter (where retail)                    as listed,
  count(*) filter (where not retail)                as hidden,
  count(*) filter (where not retail
                     and current_rate is not null
                     and status = 'live')           as hidden_but_live
from   funds
where  fund_type = 'mmf'
  and  kind = 'fund'
group by currency
order by currency;

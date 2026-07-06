-- backfill-retail-priced.sql
-- Show any *priced* KES fund in the app, not just MMFs. Your original retail
-- cut was MMF-only, so the Fixed Income / Special / Equity / Balanced funds you
-- just imported rates for are still retail=false and the app hides them.
--
-- This is additive: it only flips funds ON, never off, so the existing MMF /
-- T-bill / SACCO retail set is untouched. Run it in the SQL editor, then
-- Rebuild snapshot, then relaunch the app.
--
-- Scope: KES only (these boards are KES). Drop the currency line to include USD
-- funds too — the app's currency sub-filter will separate them.

update funds
set retail = true
where kind = 'fund'
  and status <> 'hidden'
  and current_rate is not null
  and fund_type in ('fixed_income', 'special', 'equity', 'balanced')
  and currency = 'KES'
  and retail is distinct from true;   -- no-op for rows already retail

-- See what's now in-app, by type:
--   select fund_type, count(*) filter (where retail) as in_app, count(*) as total
--   from funds where kind='fund' and status<>'hidden' group by fund_type order by fund_type;

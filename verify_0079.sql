-- Run in the Supabase SQL editor AFTER 0079 is pushed.
-- Each block is wrapped in begin/rollback so nothing persists.


-- ==================================================================
-- A. What anon can still read. All three counts must be non-zero if
--    the app uses these views. A zero here is the silent-breakage
--    case: the view resolves but RLS on a base table filtered
--    everything out.
-- ==================================================================

begin;
set local role anon;

select 'market_history_monthly' as source, count(*) as rows
  from public.market_history_monthly
union all
select 'insurer_reviews_public', count(*)
  from public.insurer_reviews_public
union all
select 'insurer_review_stats', count(*)
  from public.insurer_review_stats;

rollback;


-- ==================================================================
-- B. What anon must no longer reach. Each of these should fail with
--    permission denied. Run them one at a time.
-- ==================================================================

begin;
set local role anon;
select * from public.llm_spend_mtd;
rollback;

begin;
set local role anon;
select * from public.factsheet_import_queue;
rollback;

begin;
set local role anon;
select body from public.insurer_reviews;
rollback;

begin;
set local role anon;
delete from public.insurer_reviews_public;
rollback;


-- ==================================================================
-- C. Confirm every view now reports invoker semantics.
--    All five rows must read 'true'.
-- ==================================================================

select c.relname,
       coalesce(
         (select o.option_value
            from pg_options_to_table(c.reloptions) o
           where o.option_name = 'security_invoker'),
         'off'
       ) as security_invoker
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relkind = 'v'
   and c.relname in (
     'insurer_reviews_public',
     'insurer_review_stats',
     'market_history_monthly',
     'factsheet_import_queue',
     'llm_spend_mtd'
   )
 order by c.relname;

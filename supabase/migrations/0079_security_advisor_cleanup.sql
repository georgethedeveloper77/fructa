-- 0079_security_advisor_cleanup.sql
--
-- Clears the 5 Security Advisor errors (SECURITY DEFINER views) and the
-- Public Bucket Allows Listing warning.
--
-- The RLS-enabled-no-policy INFO items are deliberately left alone: RLS on
-- with zero policies is deny-all for anon and authenticated, service_role
-- bypasses it, and that is the correct state for every table in that list.
--
-- pg_net is deliberately left in public. It is not cleanly relocatable and
-- invoke_edge_function depends on it.


-- ------------------------------------------------------------------
-- 1. View grants
--
-- All five views carried the blanket anon/authenticated grant set,
-- including INSERT/UPDATE/DELETE/TRUNCATE. Combined with security_invoker
-- being off, that made insurer_reviews_public an anon-writable path
-- straight through the RLS on insurer_reviews. Strip everything, then
-- grant back only the reads the app needs.
-- ------------------------------------------------------------------

revoke all on public.factsheet_import_queue from anon, authenticated;
revoke all on public.llm_spend_mtd          from anon, authenticated;
revoke all on public.market_history_monthly from anon, authenticated;
revoke all on public.insurer_reviews_public from anon, authenticated;
revoke all on public.insurer_review_stats   from anon, authenticated;

-- Admin-only surfaces. service_role reads these and bypasses RLS.
-- No client role gets them back.

-- Client-readable surfaces.
grant select on public.market_history_monthly to anon, authenticated;
grant select on public.insurer_reviews_public to anon, authenticated;
grant select on public.insurer_review_stats   to anon, authenticated;


-- ------------------------------------------------------------------
-- 2. Blocked-author lookup
--
-- blocked_authors has RLS on and no policies, so a subquery against it
-- from an anon session sees zero rows and NOT EXISTS becomes vacuously
-- true, which would make blocked authors' reviews visible once the view
-- runs as invoker. A SECURITY DEFINER function keeps the lookup honest
-- without granting anon read on the table. Functions are not flagged by
-- the security_definer_view lint.
-- ------------------------------------------------------------------

create or replace function public.author_is_blocked(p_author uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.blocked_authors b
    where b.author_id = p_author
  );
$$;

revoke all on function public.author_is_blocked(uuid) from public;
grant execute on function public.author_is_blocked(uuid)
  to anon, authenticated, service_role;


-- ------------------------------------------------------------------
-- 3. Moderation gate moves into the table
--
-- Once insurer_reviews_public runs as invoker, anon needs column-level
-- SELECT on every column the view reads. Reading raw body would defeat
-- the body_status gate, so compute the gated value in the table and
-- keep body itself revoked.
-- ------------------------------------------------------------------

alter table public.insurer_reviews
  add column if not exists body_public text
  generated always as (
    case when body_status = 'approved' then body else null end
  ) stored;


-- ------------------------------------------------------------------
-- 4. Public read policy on the base table
--
-- reviews_read_own only matches auth.uid() = author_id, which yields
-- nothing for an anon session. Without this the invoker view returns
-- an empty set instead of erroring, which is the silent-breakage case.
-- ------------------------------------------------------------------

drop policy if exists reviews_public_read on public.insurer_reviews;

create policy reviews_public_read
  on public.insurer_reviews
  for select
  to anon, authenticated
  using (
    not hidden
    and not public.author_is_blocked(author_id)
  );


-- ------------------------------------------------------------------
-- 5. Column-level SELECT
--
-- body, body_status, reject_reason and moderated_at stay revoked from
-- client roles. INSERT/UPDATE/DELETE grants are untouched: the
-- reviews_*_own policies already gate them on auth.uid().
-- ------------------------------------------------------------------

revoke select on public.insurer_reviews from anon, authenticated;

grant select (
  id,
  insurer_id,
  rating,
  body_public,
  claims_holder,
  helpful_count,
  created_at,
  hidden,
  author_id
) on public.insurer_reviews to anon, authenticated;


-- ------------------------------------------------------------------
-- 6. Rebuild insurer_reviews_public on the gated column
--
-- Same column names, types and order, so create or replace is legal and
-- nothing downstream needs to change. The blocked-author filter stays in
-- the view body as well as in the policy, because service_role bypasses
-- RLS and the admin should not see blocked authors either.
-- ------------------------------------------------------------------

create or replace view public.insurer_reviews_public as
  select
    r.id,
    r.insurer_id,
    r.rating,
    r.body_public as body,
    r.claims_holder,
    r.helpful_count,
    r.created_at
  from public.insurer_reviews r
  where not r.hidden
    and not public.author_is_blocked(r.author_id);


-- ------------------------------------------------------------------
-- 7. Flip all five views to invoker semantics
-- ------------------------------------------------------------------

alter view public.insurer_reviews_public set (security_invoker = on);
alter view public.insurer_review_stats   set (security_invoker = on);
alter view public.market_history_monthly set (security_invoker = on);
alter view public.factsheet_import_queue set (security_invoker = on);
alter view public.llm_spend_mtd          set (security_invoker = on);


-- ------------------------------------------------------------------
-- 8. Stop anon enumerating the marketing bucket
--
-- The bucket stays public, so /object/public/marketing/... URLs keep
-- resolving without consulting RLS. Only list() is affected. The admin
-- uploads as authenticated (see the existing marketing insert/update/
-- delete policies), so it keeps its read.
-- ------------------------------------------------------------------

drop policy if exists "marketing public read" on storage.objects;

create policy "marketing authenticated read"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'marketing');

-- 0033_marketing_bucket.sql
-- Public-read storage bucket for landing / marketing assets:
-- hero-chart fallback image, the three feature screenshots, and the OG image.
-- Mirrors the logos bucket (0013). Admin uploads run through the authenticated
-- session; the service role bypasses RLS regardless.

insert into storage.buckets (id, name, public)
values ('marketing', 'marketing', true)
on conflict (id) do nothing;

-- Idempotent policy (re)creation so a partial prior state can't block the push.
drop policy if exists "marketing public read"          on storage.objects;
drop policy if exists "marketing authenticated insert" on storage.objects;
drop policy if exists "marketing authenticated update" on storage.objects;
drop policy if exists "marketing authenticated delete" on storage.objects;

create policy "marketing public read"
  on storage.objects for select
  using (bucket_id = 'marketing');

create policy "marketing authenticated insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'marketing');

create policy "marketing authenticated update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'marketing')
  with check (bucket_id = 'marketing');

create policy "marketing authenticated delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'marketing');

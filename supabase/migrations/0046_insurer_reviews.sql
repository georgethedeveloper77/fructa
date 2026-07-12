-- 0046_insurer_reviews.sql
--
-- User reviews of insurers. Insurers are rows in `funds` where kind='insurance',
-- so a review points at funds(id).
--
-- THE MODEL (George's call, and the right one):
--   the RATING publishes immediately. A star is a preference, and a preference
--   is not a statement of fact, so it carries little defamation risk.
--   the TEXT waits for a human. "They refuse to pay claims" IS a statement of
--   fact about a named, litigious company, and Kenya has no Section 230 safe
--   harbour: publish it and Fructa is a publisher.
--
-- So one row holds both, with independent visibility:
--   rating      -> counted in the average the moment it lands
--   body        -> hidden until body_status = 'approved'
--
-- Identity is Supabase ANONYMOUS auth: auth.uid() is a stable per-device UUID
-- with no name, email or phone attached. That satisfies Apple Guideline 1.2's
-- "block abusive users" requirement without Fructa holding personal data.

-- ---------------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------------
create table if not exists insurer_reviews (
  id            uuid primary key default gen_random_uuid(),
  insurer_id    text not null references funds(id) on delete cascade,
  author_id     uuid not null references auth.users(id) on delete cascade,

  -- Publishes immediately.
  rating        int  not null check (rating between 1 and 5),

  -- Waits for a human. Null body = a rating-only review, which is complete and
  -- valid, not a half-finished one.
  body          text check (body is null or char_length(btrim(body)) between 10 and 1200),
  body_status   text not null default 'none'
                check (body_status in ('none','pending','approved','rejected')),
  reject_reason text,
  moderated_at  timestamptz,

  -- Set by the app when the user holds this insurer in their portfolio. It is a
  -- CLIENT claim: holdings live on-device (Hive), so the server cannot verify
  -- it. Treated as a soft signal only. Never gate anything on it.
  claims_holder boolean not null default false,

  helpful_count int not null default 0,
  hidden        boolean not null default false, -- set by auto-hide or an admin

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- One review per person per insurer. Editing replaces, it does not stack.
  unique (insurer_id, author_id)
);

create index if not exists insurer_reviews_insurer_idx
  on insurer_reviews (insurer_id) where not hidden;
create index if not exists insurer_reviews_queue_idx
  on insurer_reviews (created_at) where body_status = 'pending';

-- body_status must track whether a body exists, and any EDIT to the body sends
-- it back to the queue. Without this, a user could submit innocuous text, get
-- approved, then edit it into an accusation.
create or replace function insurer_reviews_body_gate() returns trigger as $$
begin
  new.updated_at := now();

  if new.body is null or btrim(new.body) = '' then
    new.body := null;
    new.body_status := 'none';
    new.reject_reason := null;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.body_status := 'pending';
    return new;
  end if;

  -- UPDATE: text changed, or a rejected body was resubmitted -> back in the queue.
  if new.body is distinct from old.body then
    new.body_status := 'pending';
    new.reject_reason := null;
    new.moderated_at := null;
  end if;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_insurer_reviews_body_gate on insurer_reviews;
create trigger trg_insurer_reviews_body_gate
  before insert or update on insurer_reviews
  for each row execute function insurer_reviews_body_gate();

-- ---------------------------------------------------------------------------
-- Reports (Apple 1.2: users must be able to flag objectionable content)
-- ---------------------------------------------------------------------------
create table if not exists review_reports (
  id          uuid primary key default gen_random_uuid(),
  review_id   uuid not null references insurer_reviews(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason      text not null
              check (reason in ('spam','abuse','false','personal_info','other')),
  note        text check (note is null or char_length(note) <= 500),
  created_at  timestamptz not null default now(),
  unique (review_id, reporter_id)
);

-- Three distinct reporters hides the review pending admin review. Removing it
-- fast is the point: an approved body can still turn out to be defamatory, and
-- "we took it down within the hour" is a materially better legal position.
create or replace function review_reports_autohide() returns trigger as $$
declare n int;
begin
  select count(*) into n from review_reports where review_id = new.review_id;
  if n >= 3 then
    update insurer_reviews set hidden = true, updated_at = now()
    where id = new.review_id;
  end if;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_review_reports_autohide on review_reports;
create trigger trg_review_reports_autohide
  after insert on review_reports
  for each row execute function review_reports_autohide();

-- ---------------------------------------------------------------------------
-- Blocked authors (Apple 1.2: must be able to block abusive users)
-- ---------------------------------------------------------------------------
create table if not exists blocked_authors (
  author_id  uuid primary key references auth.users(id) on delete cascade,
  reason     text,
  blocked_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- The public view. This is the ONLY thing the app reads.
--
-- It is where the split lives: every non-hidden rating is present, but `body`
-- is nulled unless it cleared moderation. A pending or rejected body is
-- invisible to everyone except its author and the admin, while its star still
-- counts. Nothing downstream can accidentally leak an unapproved body, because
-- the column simply is not there.
-- ---------------------------------------------------------------------------
create or replace view insurer_reviews_public as
select
  r.id,
  r.insurer_id,
  r.rating,
  case when r.body_status = 'approved' then r.body else null end as body,
  r.claims_holder,
  r.helpful_count,
  r.created_at
from insurer_reviews r
where not r.hidden
  and not exists (select 1 from blocked_authors b where b.author_id = r.author_id);

-- Per-insurer aggregate. Counts EVERY visible rating, approved body or not,
-- which is exactly the point of auto-publishing ratings.
create or replace view insurer_review_stats as
select
  insurer_id,
  count(*)                                   as review_count,
  round(avg(rating)::numeric, 2)             as review_avg,
  count(*) filter (where rating = 5)         as r5,
  count(*) filter (where rating = 4)         as r4,
  count(*) filter (where rating = 3)         as r3,
  count(*) filter (where rating = 2)         as r2,
  count(*) filter (where rating = 1)         as r1,
  count(*) filter (where body is not null)   as with_text
from insurer_reviews_public
group by insurer_id;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table insurer_reviews enable row level security;
alter table review_reports  enable row level security;
alter table blocked_authors enable row level security;

-- Read: nobody selects the base table directly. The app reads the view, which
-- is owner-run and therefore bypasses RLS by design. An author may read their
-- own row (so they can see "your review is pending").
drop policy if exists reviews_read_own on insurer_reviews;
create policy reviews_read_own on insurer_reviews
  for select using (auth.uid() = author_id);

-- Write: authenticated (including anonymous) users, own row only, and never if
-- blocked. A blocked device can still read; it just cannot speak.
drop policy if exists reviews_insert_own on insurer_reviews;
create policy reviews_insert_own on insurer_reviews
  for insert with check (
    auth.uid() = author_id
    and not exists (select 1 from blocked_authors b where b.author_id = auth.uid())
  );

drop policy if exists reviews_update_own on insurer_reviews;
create policy reviews_update_own on insurer_reviews
  for update using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and not exists (select 1 from blocked_authors b where b.author_id = auth.uid())
  );

drop policy if exists reviews_delete_own on insurer_reviews;
create policy reviews_delete_own on insurer_reviews
  for delete using (auth.uid() = author_id);

-- Reports: anyone authenticated may file one, on someone else's review.
drop policy if exists reports_insert on review_reports;
create policy reports_insert on review_reports
  for insert with check (
    auth.uid() = reporter_id
    and not exists (
      select 1 from insurer_reviews r
      where r.id = review_id and r.author_id = auth.uid()
    )
  );

-- blocked_authors: service role only. No policy = no access for anon/authed.

grant select on insurer_reviews_public to anon, authenticated;
grant select on insurer_review_stats   to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
select 'reviews' as t, count(*) from insurer_reviews
union all
select 'pending bodies', count(*) from insurer_reviews where body_status = 'pending'
union all
select 'reports', count(*) from review_reports;

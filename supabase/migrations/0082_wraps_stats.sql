-- 0082_wraps_stats.sql
--
-- A few numbers about each wrap's period, for the archive's timeline and
-- calendar: the KES money market median at the end of the period, how far it
-- moved over the period, and whether the period had a big story. Written by
-- build-wraps beside the stories; null on wraps built before this existed
-- until they are rebuilt.

alter table public.wraps add column if not exists stats jsonb;

comment on column public.wraps.stats is
  '{ median, move, big }: KES MMF median at period end, its move over the period, and whether a story was unusually large.';

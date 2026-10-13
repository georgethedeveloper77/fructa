-- 0080_statement_reminders.sql
--
-- Statement check (Pro). Two pieces of server state, and only these two:
--
--   1. app_config rows the app reads through the snapshot:
--        statements.enabled   feature flag, off until the reader ships
--        statements.managers  per manager: key, name, match pattern,
--                             password hint, release day of month
--   2. A daily reminder push on each manager's release day.
--
-- Statements, statement passwords and balances never reach the server. The
-- app reads the PDF on the device; the only trace here is that a device asked
-- OneSignal to tag it `stmt_<manager_key> = 1` because its owner holds or has
-- checked that manager, which is how the reminder finds the right people.
--
-- Published-rate history needs no new table: rate_history already keeps one
-- row per (fund_id, as_of) and is never overwritten, and the app treats it as
-- a step series (a rate holds until the next print) to average the published
-- rate over any statement period.

-- ── 1. Config seeds (left untouched if an operator already set them) ────────
insert into public.app_config (key, value, description) values
  ('statements.enabled', 'false'::jsonb,
   'Statement check live in the app, and statement-day reminders allowed to send'),
  ('statements.managers',
   jsonb_build_object('managers', jsonb_build_array(
     jsonb_build_object(
       'key', 'lofty_corban',
       'name', 'Lofty-Corban',
       'match', 'lofty[\s-]*corban',
       'password_hint', 'Usually your member number',
       'release_day', 5
     )
   )),
   'Fund managers whose statements the app reads, with password hints and release days')
on conflict (key) do nothing;

-- ── 2. The reminder ─────────────────────────────────────────────────────────
-- Runs daily. For every manager whose release_day is today (Nairobi date) it
-- asks send-push for one notification to the stmt_<key> tag. Does nothing
-- while statements.enabled is false. Uses the same vault secrets and the same
-- missing-secret guard as invoke_edge_function (0048), so a broken vault
-- leaves a visible failure row instead of failing silently.
create or replace function public.send_statement_reminders()
returns integer
language plpgsql
security definer
set search_path = public, vault, net, pg_temp
as $$
declare
  v_enabled  boolean;
  v_url      text;
  v_secret   text;
  v_today    int := extract(day from (now() at time zone 'Africa/Nairobi'))::int;
  v_month    text := to_char(now() at time zone 'Africa/Nairobi' - interval '1 month', 'FMMonth');
  v_sent     int := 0;
  m          jsonb;
begin
  select coalesce((value)::text::boolean, false) into v_enabled
    from public.app_config where key = 'statements.enabled';
  if not coalesce(v_enabled, false) then
    return 0;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or btrim(v_url) = '' or v_secret is null or btrim(v_secret) = '' then
    perform public.log_cron_failure(
      'send-statement-reminders',
      'Vault secret project_url or cron_secret missing. No reminder was sent.'
    );
    raise warning 'send_statement_reminders: vault secret missing, nothing sent';
    return 0;
  end if;

  for m in
    select x
      from public.app_config c,
           jsonb_array_elements(c.value -> 'managers') as x
     where c.key = 'statements.managers'
       and (x ->> 'release_day') ~ '^\d+$'
       and (x ->> 'release_day')::int = v_today
       and coalesce(x ->> 'key', '') <> ''
  loop
    perform net.http_post(
      url     := rtrim(v_url, '/') || '/functions/v1/send-push',
      headers := jsonb_build_object(
                   'Content-Type',  'application/json',
                   'x-cron-secret', v_secret
                 ),
      body    := jsonb_build_object(
                   'title',   'Your ' || (m ->> 'name') || ' statement is due',
                   'body',    'Your ' || v_month || ' statement should be in your email. Check it in 30 seconds.',
                   'target',  'portfolio',
                   'segment', jsonb_build_object('tag', 'stmt_' || (m ->> 'key'), 'value', '1')
                 )
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

revoke all on function public.send_statement_reminders() from public, anon, authenticated;

-- 05:00 UTC = 08:00 EAT, daily. Drop any earlier copy so a re-run never
-- stacks two schedules.
create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare jid bigint;
begin
  select jobid into jid from cron.job where jobname = 'fructa-statement-reminders' limit 1;
  if jid is not null then
    perform cron.unschedule(jid);
  end if;
end $$;

select cron.schedule(
  'fructa-statement-reminders',
  '0 5 * * *',
  $$ select public.send_statement_reminders(); $$
);

-- Inspect:
--   select public.send_statement_reminders();   -- returns how many were sent
--   select * from cron.job where jobname = 'fructa-statement-reminders';
--   select * from public.push_log order by created_at desc limit 10;

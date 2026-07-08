-- 0004_cron.sql
-- Schedule the aggregator scraper daily at 03:00 UTC (= 06:00 EAT).
-- pg_cron fires the schedule; pg_net makes the HTTP call to the edge function.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Store these in Supabase Vault (Dashboard -> Project Settings -> Vault) so the
-- URL and secret aren't written into SQL:
--   project_url  = https://lxtyrtgyfrhxyjraroku.supabase.co
--   cron_secret  = <same value as the CRON_SECRET edge-function secret>

select cron.schedule(
  'fructa-scrape-aggregator',
  '0 3 * * *',                    -- 03:00 UTC = 06:00 EAT
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/scrape-aggregator',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Inspect / manage later:
--   select * from cron.job;
--   select * from cron.job_run_details order by start_time desc limit 20;
--   select cron.unschedule('fructa-scrape-aggregator');

# supabase — database + scrapers

The fructa rates API. Postgres tables (auto REST API) + Deno edge-function
scrapers, scheduled by pg_cron. Host-agnostic: runs entirely inside Supabase,
so it doesn't matter where the admin panel is hosted (Firebase, Vercel, …).

## Layout
- `migrations/` — `0003_scraper_runs.sql`, `0004_cron.sql`
  (the `funds` + `rate_history` schema is bootstrapped from `admin/sql/`)
- `functions/scrape-aggregator/` — backbone scraper (one source -> many funds)
- `functions/_shared/` — validation, service-role client, types

## Data source (read this first)
The scraper is source-agnostic; the URL is config, not code:
`AGGREGATOR_URL_KES` / `AGGREGATOR_URL_USD`. Point it only at a source whose
robots.txt and terms of service you've checked. Prefer first-party/official
data (CBK for T-bills & bonds; fund fact sheets for MMFs). Treat third-party
aggregators as bootstrap/cross-check, not a permanent dependency.

## Deploy
```
supabase link --project-ref lxtyrtgyfrhxyjraroku
supabase db push                              # applies migrations (incl. 0005 snapshots bucket)
supabase secrets set CRON_SECRET=... AGGREGATOR_URL_KES=... AGGREGATOR_URL_USD=...

# Functions gate on x-cron-secret, so disable Supabase's JWT check:
supabase functions deploy scrape-aggregator --no-verify-jwt
supabase functions deploy publish-snapshot  --no-verify-jwt
```

The app reads the published snapshot here (public, CDN-cached):
`<project>/storage/v1/object/public/snapshots/funds-snapshot.json`

## Run manually (dev)
```
curl -X POST "$SUPABASE_URL/functions/v1/scrape-aggregator" \
  -H "x-cron-secret: $CRON_SECRET"
```

## Verify parsing before trusting a source
```
curl -A "fructaBot/0.1" "<source-url>" > fixture.html
deno run --allow-read functions/scripts/test-adapter.ts fixture.html
```

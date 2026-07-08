# fructa-admin

The admin panel **and** management API for fructa, in one Next.js app on Vercel.

## Two API surfaces (important)
- **Supabase auto REST API** — the *Flutter app's* read API. The app hits
  `https://<project>.supabase.co/rest/v1/funds` directly with the anon key.
- **This Next.js app** — the *admin/scraper* API: admin CRUD (server actions)
  + the cron-triggered scrape routes. The app never routes through here.

## Layout
- `app/` — dashboard, funds table, fund detail, scrapers log
- `app/api/cron/scrape/[source]/` — cron-triggered scrapers (write to Supabase)
- `lib/supabase/` — anon (browser) + service-role (server) clients
- `lib/scrapers/` — registry, validation, and per-source scrapers (ke/ ...)
- `sql/` — one-time database setup

## Setup
1. `npm install`
2. Copy `.env.example` -> `.env.local`, fill in Supabase keys.
3. Run the SQL once in the Supabase SQL editor: `sql/0001_init.sql`, then `sql/0002_seed.sql`.
4. `npm run dev`

## Scrapers on the free tier
Vercel Hobby cron runs **once per day, UTC only**. `06:00 EAT = 03:00 UTC`,
so `vercel.json` schedules `0 3 * * *`. Vercel does not retry a failed run,
so the admin panel exposes a manual "re-run" that hits the same route.

Trigger a scrape manually (dev):
`curl -H "Authorization: Bearer $CRON_SECRET" http://localhost:3000/api/cron/scrape/ke-aggregator`


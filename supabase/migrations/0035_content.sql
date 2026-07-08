-- 0035_content.sql
-- Marketing content for the website: static legal/company pages and the blog.
-- Web-only (read by the Next app server-side); kept out of the app snapshot.

-- Static pages (privacy, terms, about, …). Markdown body.
create table if not exists pages (
  slug        text primary key,
  title       text not null,
  body        text not null default '',
  updated_at  timestamptz not null default now()
);

-- Blog posts.
create table if not exists posts (
  slug            text primary key,
  title           text not null,
  excerpt         text,
  body            text not null default '',
  cover_url       text,
  published       boolean not null default false,
  published_at    timestamptz,
  seo_title       text,
  seo_description text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table pages enable row level security;
alter table posts enable row level security;

-- Public read: pages always, posts only when published. Admin writes go through
-- the service role (server actions), which bypasses RLS.
drop policy if exists "pages public read" on pages;
drop policy if exists "posts public read" on posts;
create policy "pages public read" on pages for select using (true);
create policy "posts public read" on posts for select using (published = true);

-- Starter content so the sitemap routes resolve immediately (no 404s).
-- NOTE: placeholder legal copy — have it reviewed before launch.
insert into pages (slug, title, body) values
  ('privacy', 'Privacy Policy', $md$# Privacy Policy

_Last updated: 8 July 2026._

Fructa shows Kenyan investment rates and lets you track your own holdings. We are built around a simple principle: **your money is your business.**

## What stays on your device
Your holdings, amounts, and projections are stored **on your device**. We do not upload, see, or store your balances on our servers.

## What we collect
- Anonymous app analytics (screens opened, features used) to improve the product.
- Push notification tokens, if you opt in to alerts.

## What we never do
- Sell your data.
- Share your holdings with fund managers or third parties.

## Contact
Questions about privacy? Email hello@fructa.africa.
$md$),
  ('terms', 'Terms of Use', $md$# Terms of Use

_Last updated: 8 July 2026._

By using Fructa you agree to these terms.

## Not financial advice
Fructa aggregates publicly available rates and computes illustrative figures. **It is information, not financial advice.** Always do your own research and consult a licensed advisor before investing.

## Accuracy
We work to keep rates accurate and current, but figures come from third-party sources and may be delayed or wrong. Verify with the provider before acting.

## Your use
Use Fructa lawfully. Don't attempt to disrupt, scrape, or misuse the service.

## Contact
Email hello@fructa.africa.
$md$)
on conflict (slug) do nothing;

insert into posts (slug, title, excerpt, body, published, published_at, seo_title, seo_description) values
  ('welcome-to-fructa',
   'Welcome to Fructa',
   'Why we built a rates terminal for Kenyan money, and what it does.',
   $md$# Welcome to Fructa

Kenyans hunt for yields across WhatsApp groups, fund-manager PDFs, and spreadsheets. **Fructa puts every rate in one board** — money market funds, T-bills, bonds, SACCOs, and insurance — ranked, net of tax, and compared.

## What makes it different
- **Net of tax, not headline.** We show the yield after 15% withholding and the real return after inflation.
- **Your holdings on top.** Add what you hold and see it overlaid on the live market. It stays on your device.
- **Alerts that matter.** Know the moment a rate moves, before the WhatsApp group does.

Download the app and see where your money should be sitting.
$md$,
   true, now(),
   'Welcome to Fructa — the rates terminal for Kenyan money',
   'Why we built Fructa: every Kenyan investment rate in one board, net of tax, with your holdings on top.')
on conflict (slug) do nothing;

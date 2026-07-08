-- 0034_landing_config.sql
-- Seeds brand / SEO / store-link / landing-copy keys into app_config so the
-- public landing renders from config and the snapshot carries them. Values are
-- jsonb; text is stored as JSON strings. Managed from Admin > Settings. Images
-- hold the marketing-bucket public URL once uploaded (empty string = none).
insert into app_config (key, value, description) values
  ('brand.name', '"Fructa"', 'Brand name — nav, footer, metadata'),
  ('brand.footer_blurb',
   '"The rates terminal for Kenyan money. Rates are informational and not financial advice."',
   'Landing footer blurb'),
  ('brand.contact_email', '"hello@fructa.africa"', 'Public contact email'),

  ('seo.title', '"Fructa — the rates terminal for Kenyan money"', 'SEO / OpenGraph title'),
  ('seo.description',
   '"Money market funds, T-bills, bonds, SACCOs and insurance. Every live rate in Kenya, ranked and compared, with your own holdings on top."',
   'SEO / OpenGraph description'),
  ('seo.og_image', '""', 'OG image URL (marketing bucket); empty falls back to /og.png'),

  ('links.android_url', '""', 'Google Play listing URL'),
  ('links.ios_url', '""', 'App Store listing URL'),

  ('landing.hero_headline', '"Every Kenyan rate."', 'Hero headline, line 1'),
  ('landing.hero_accent', '"One terminal."', 'Hero headline, accent line'),
  ('landing.hero_subhead',
   '"Money market funds, T-bills, bonds, SACCOs and insurance — every live rate in Kenya, ranked and compared, with your own holdings on top."',
   'Hero subhead'),
  ('landing.hero_microtrust', '"144 funds tracked · updated at noon EAT, every weekday"',
   'Hero microtrust line'),
  ('landing.cta_headline', '"Stop hunting for yields."', 'Final CTA headline'),
  ('landing.cta_subhead', '"Download Fructa and see where your money should be sitting."',
   'Final CTA subhead'),
  ('landing.stats',
   '[{"n":"144","l":"funds tracked across the market"},{"n":"96.8%","l":"of industry AUM covered"},{"n":"Noon","l":"EAT refresh, every weekday"},{"n":"6","l":"asset classes in one board"}]',
   'Landing stat band — array of {n,l}'),

  ('landing.feature_rank_image', '""', 'Feature 1 screenshot URL (marketing bucket)'),
  ('landing.feature_portfolio_image', '""', 'Feature 2 screenshot URL (marketing bucket)'),
  ('landing.feature_alerts_image', '""', 'Feature 3 screenshot URL (marketing bucket)')
on conflict (key) do nothing;

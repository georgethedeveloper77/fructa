-- 0083_app_links.sql
--
-- What fructa.africa tells Android and iOS so a tapped fructa.africa link opens
-- the app when it is installed: the Play app-signing SHA-256 fingerprints and
-- the Apple Team ID. Kept in app_config so they are edited in admin Config,
-- not in code. Served by /.well-known/assetlinks.json and
-- /.well-known/apple-app-site-association.

insert into public.app_config (key, value, description) values
  ('applinks.android_package', '"com.mindberzerk.fructa"'::jsonb,
   'Android package name for App Links'),
  ('applinks.android_sha256', '[]'::jsonb,
   'Play Console > App integrity > App signing key SHA-256 fingerprints, as a list. Add the upload key too to test local release builds.'),
  ('applinks.ios_team_id', '""'::jsonb,
   'Apple Developer Team ID (10 characters) for Universal Links'),
  ('applinks.ios_bundle_id', '"com.mindberzerk.fructa"'::jsonb,
   'iOS bundle identifier for Universal Links'),
  ('applinks.paths', '["/funds/*", "/rates/*"]'::jsonb,
   'Paths that open in the app when it is installed')
on conflict (key) do nothing;

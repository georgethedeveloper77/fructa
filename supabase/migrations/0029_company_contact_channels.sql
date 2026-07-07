-- 0029_company_contact_channels.sql
-- WhatsApp + email contact channels, companion to the phone added in 0028.
--   whatsapp — official WhatsApp number (wa.me); separate from phone so it can
--              differ, and so the row shows only when set.
--   email    — official contact email (mailto:)
--
-- Shipped as a SEPARATE migration on purpose: 0028 was already recorded as
-- applied, and `supabase db push` tracks migrations by version — editing an
-- applied migration's body does NOT re-run it (push says "up to date"), which
-- is why the admin select 500'd with "column companies.whatsapp does not exist".
-- A new version forces the columns through. `if not exists` on all three keeps a
-- full replay safe regardless of what 0028 applied.
alter table companies
  add column if not exists phone text,
  add column if not exists whatsapp text,
  add column if not exists email text;

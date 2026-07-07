-- 0028_company_contact.sql
-- Company-level phone line (tel:). Distinct from agents (individual people in
-- the agents table) — this is the provider's own official number, admin-edited
-- on the Companies page and published in the snapshot for the fund-detail
-- Contact section. Nullable: the app hides the row when unset.
-- NOTE: WhatsApp + email were added later in 0029, NOT by editing this file —
-- an already-applied migration's body is never re-run by `supabase db push`.
alter table companies
  add column if not exists phone text;

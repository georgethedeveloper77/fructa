-- Phase 3 — on-device portfolio backup/restore, no login.
--
-- A backup is keyed by the SHA-256 hash of the user's recovery code. The raw
-- code never leaves the device except inside the two edge functions, and is
-- never stored — a DB leak reveals only hashes. Possession of the code is the
-- capability: it works on any device, which is what survives a "clear data" or
-- a move to a new phone.
--
-- All reads/writes go through the `portfolio-backup` / `portfolio-restore`
-- edge functions (service role, which bypasses RLS). RLS is enabled with NO
-- policies, so the anon/authenticated roles cannot touch this table directly.

create table if not exists portfolio_backups (
  code_hash    text primary key,           -- sha256(recovery_code), lowercase hex
  data         jsonb not null,             -- opaque portfolio blob from the app
  device_label text,                       -- optional, e.g. "Pixel 8" — for the restore sheet
  schema       int  not null default 1,    -- app-side blob version, for forward migration
  updated_at   timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

alter table portfolio_backups enable row level security;
-- Intentionally no policies: only the service-role edge functions reach this.

comment on table portfolio_backups is
  'Anonymous portfolio backups keyed by sha256(recovery_code). Access only via the portfolio-backup/portfolio-restore edge functions; the raw code is never stored.';

-- 0044_insurer_trust.sql
-- Regulatory + trust fields for insurers (rows in `funds` where kind='insurance').
--
-- WHY: per-insurer "claims paid %" is NOT published anywhere in Kenya. The
-- honest, sourced proxies are AKI's combined ratio (underwriting soundness) and
-- IRA's complaint counts (service quality). These columns hold real, citable
-- values only; anything unseeded stays null and its UI hides.
--
-- Sources, and their refresh cadence:
--   license_status / ira_class_codes / licensed_since  IRA licensed register (annual)
--   financial_rating / rating_agency / rating_outlook  GCR national scale (annual, drifts)
--   market_share_pct / combined_ratio                  AKI Insurance Market Report (annual)
--   complaints_count / complaints_resolved             IRA quarterly industry release
--   gwp_kes                                            AKI / IRA (annual)

alter table funds
  -- Regulatory standing (IRA). 'statutory_management' and 'closed' are hard
  -- "do not buy" flags: Trident, KUSCCO Mutual and Corporate were placed under
  -- statutory management effective 10 Mar 2026 and cannot write new business.
  add column if not exists license_status   text
    check (license_status in ('active','statutory_management','closed')),
  add column if not exists license_year     int,
  add column if not exists ira_class_codes  text[],

  -- Financial strength (GCR national scale, e.g. 'AA-(KE)').
  add column if not exists financial_rating text,
  add column if not exists rating_agency    text,
  add column if not exists rating_outlook   text,
  add column if not exists rating_as_of     date,

  -- Market standing (AKI annual report). combined_ratio < 100 means the insurer
  -- makes money underwriting; the honest public proxy for "can it pay claims".
  add column if not exists market_share_pct numeric,
  add column if not exists combined_ratio   numeric,
  add column if not exists gwp_kes          numeric,
  add column if not exists ratios_as_of     date,

  -- Service quality (IRA quarterly). IRA groups insurers with <=5 complaints
  -- into "Others", so a null here means "not separately reported", NOT zero.
  add column if not exists complaints_count    int,
  add column if not exists complaints_resolved int,
  add column if not exists complaints_period   text,

  -- Provenance: where this insurer's figures came from, shown in the UI.
  add column if not exists data_source text;

comment on column funds.license_status is
  'IRA standing: active | statutory_management | closed. Non-active blocks new business.';
comment on column funds.ira_class_codes is
  'IRA authorized class codes, e.g. {07,08,09,12}. 07=Motor Private, 08=Motor Commercial, 09=Personal Accident, 12=Medical.';
comment on column funds.combined_ratio is
  'AKI non-life combined ratio, %. Below 100 = underwriting profit. Proxy for claims-paying soundness; NOT a settlement rate.';
comment on column funds.complaints_count is
  'IRA complaints lodged in complaints_period. Null = not separately reported (IRA groups <=5 into Others), not zero.';

-- Existing insurers default to active; correct the exceptions in the seed.
update funds set license_status = 'active'
where kind = 'insurance' and license_status is null;

-- settle_pct (0039) is retained for back-compat but is NOT to be populated:
-- no public per-insurer claims-settlement figure exists for Kenya.
comment on column funds.settle_pct is
  'DEPRECATED. No public per-insurer claims-settlement % exists in Kenya. Use combined_ratio / complaints_count instead. Do not seed.';

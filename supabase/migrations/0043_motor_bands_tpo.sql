-- 0043_motor_bands_tpo.sql
-- Motor pricing beyond a single rate: banded comprehensive rates and a flat
-- Third Party Only (TPO) price. Both live on `funds` alongside the other
-- insurer columns (rows where kind='insurance'); null for every non-insurer.
--
-- motor_bands: ordered jsonb array of {min, max, rate}. `rate` is % of sum
--   insured; `min`/`max` are the sum-insured band bounds (max null = open top).
--   When present it supersedes the single `motor_rate` for premium maths.
-- motor_tpo:  flat annual Third Party Only premium, single private vehicle (KES).

alter table funds
  add column if not exists motor_bands jsonb,
  add column if not exists motor_tpo   numeric;

comment on column funds.motor_bands is
  'Insurer comprehensive rate bands: [{"min":n,"max":n|null,"rate":pct}], ordered low to high. Supersedes motor_rate when set.';
comment on column funds.motor_tpo is
  'Insurer flat Third Party Only annual premium, single private vehicle (KES).';

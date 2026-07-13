-- 0064_sacco_tax.sql
-- Withholding tax on SACCO earnings, and the gate that stops an untaxed SACCO
-- rate entering a net-of-tax league table.
--
-- WHY THIS EXISTS
--
-- The All tab ranks funds by their NET yield, after withholding tax. A SACCO's
-- declared deposit rate is GROSS. Merging the two without adjusting is not a
-- cosmetic inconsistency, it is a thumb on the scale: at current levels a gross
-- SACCO rate carries roughly 1.5 percentage points of unpaid tax against every
-- net fund yield it is ranked beside, which is more than the entire spread
-- between the best and worst money market fund in Kenya. The SACCO would take
-- the top row on a technicality, and the app would be lying with arithmetic.
--
-- WHY THE NUMBERS ARE NOT SET HERE
--
-- The public sources disagree. Several current tax advisories state the resident
-- withholding rate on SACCO dividends is 5% under the Third Schedule of the
-- Income Tax Act. Business Daily reports that the Finance Act 2018 doubled that
-- rate from five to ten percent and that KRA began collecting at the higher
-- rate. Interest on non-withdrawable deposits (the "rebate") is separately
-- reported at 5%, on thinner corroboration.
--
-- We are not resolving a live tax dispute by picking the number we like. These
-- keys ship EMPTY and `saccos.tax_confirmed` ships false. Until someone puts a
-- KRA source or the Income Tax Act Third Schedule behind them:
--
--   * the app shows SACCO rates GROSS, and says so
--   * no net-of-tax figure is computed for a SACCO anywhere
--   * SACCOs cannot enter the All league table, whatever `saccos.in_all_tab` says
--
-- That last one is the point. `saccos.in_all_tab` alone does nothing.

-- Withholding on interest paid on member deposits. The number that matters for
-- ranking, because deposit interest is what the app ranks SACCOs on.
insert into public.app_config (key, value)
values ('saccos.wht_deposits_pct', 'null'::jsonb)
on conflict (key) do nothing;

-- Withholding on the dividend paid on share capital. Display only: the app never
-- ranks on the dividend, so this affects the detail page and nothing else.
insert into public.app_config (key, value)
values ('saccos.wht_dividend_pct', 'null'::jsonb)
on conflict (key) do nothing;

comment on table public.app_config is
  'Remote config, published into the snapshot. saccos.tax_confirmed gates every net-of-tax SACCO figure AND the All-tab merge: a gross rate may not be ranked against net fund yields.';

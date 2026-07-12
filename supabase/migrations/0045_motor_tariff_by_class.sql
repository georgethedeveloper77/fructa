-- 0045_motor_tariff_by_class.sql
--
-- Motor pricing, restructured by vehicle class.
--
-- WHY: 0043 gave us `motor_bands` (a single band array) and `motor_tpo` (one
-- number). Both silently assume PRIVATE CARS. Kenyan motor tariffs are not one
-- table: private, commercial and PSV are separately rated, separately loss-making
-- (IRA 2023: motor private combined ratio 109.9, motor commercial 113.3), and an
-- insurer may write one class and refuse another. A flat column cannot say
-- "this insurer does not write PSV", which is exactly the fact a user needs.
--
-- SHAPE (jsonb). Every level is optional. Absent = NOT OFFERED / NOT PUBLISHED,
-- and the app must exclude, never assume zero:
--
--   {
--     "private": {
--       "comprehensive": {
--         "bands": [{"min":0,"max":1000000,"rate":6.0}, ...],  -- banded by sum insured
--         "rate": 3.0,                                          -- flat fallback if no bands
--         "min_premium": 37500                                  -- premium floor
--       },
--       "tpo": 7500                                             -- flat annual third-party-only
--     },
--     "commercial": { ... },
--     "psv":        { ... }
--   }
--
-- Resolution order the app uses, per class:
--   comprehensive -> bands (first band whose min<=value<=max) -> else flat rate
--                 -> then floor at min_premium
--   tpo           -> flat figure, vehicle value irrelevant
--
-- 0043's motor_bands / motor_tpo are retained but DEPRECATED: they are migrated
-- into motor_tariff.private below and must not be written to again.

alter table funds
  add column if not exists motor_tariff jsonb;

comment on column funds.motor_tariff is
  'Per-class motor tariff: {private|commercial|psv: {comprehensive: {bands[], rate, min_premium}, tpo}}. A missing class or missing tpo means NOT OFFERED or NOT PUBLISHED, never zero.';

-- Backfill: everything we currently hold describes private cars, so it lands
-- under "private". Done dynamically so this cannot fail if a 0043 column is
-- absent in some environment.
do $$
declare
  has_bands boolean;
  has_tpo   boolean;
  has_min   boolean;
begin
  select count(*) filter (where column_name = 'motor_bands') > 0,
         count(*) filter (where column_name = 'motor_tpo')   > 0,
         count(*) filter (where column_name = 'min_premium') > 0
    into has_bands, has_tpo, has_min
  from information_schema.columns
  where table_name = 'funds';

  execute format($f$
    update funds set motor_tariff = jsonb_strip_nulls(jsonb_build_object(
      'private', jsonb_strip_nulls(jsonb_build_object(
        'comprehensive', jsonb_strip_nulls(jsonb_build_object(
          'bands',       %s,
          'rate',        motor_rate,
          'min_premium', %s
        )),
        'tpo', %s
      ))
    ))
    where kind = 'insurance'
      and motor_tariff is null
      and motor_rate is not null
  $f$,
    case when has_bands then 'motor_bands' else 'null::jsonb' end,
    case when has_min   then 'min_premium' else 'null::numeric' end,
    case when has_tpo   then 'motor_tpo'   else 'null::numeric' end
  );
end $$;

-- An insurer with an empty comprehensive block and no tpo has no tariff at all.
update funds set motor_tariff = null
where kind = 'insurance'
  and motor_tariff = '{"private": {"comprehensive": {}}}'::jsonb;

select id, name, motor_tariff
from funds
where kind = 'insurance' and motor_tariff is not null
order by name;

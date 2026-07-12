-- seed_cic_motor.sql
-- Source: CIC General Insurance Ltd, Motor Private brochure V.08/2021.
-- Faithful load of the official tariff: banded comprehensive rates, TPO price,
-- minimum premium, and the free (included) extra benefits. Insurers live in
-- `funds` where kind='insurance'. Run after migration 0043.

-- STEP 1  confirm the CIC row id. The two CIC rows (cic-motor / cic-general)
-- still need consolidating; point STEP 2 at the surviving id. Recommended:
-- cic-general.
select id, name, motor_rate, min_premium, motor_bands, motor_tpo, phone, email
from funds
where kind = 'insurance' and id like 'cic%';

-- STEP 2  seed CIC General motor pricing + contact.
update funds set
  motor_bands = '[
    {"min":500000,"max":1500000,"rate":6},
    {"min":1500001,"max":2500000,"rate":4},
    {"min":2500001,"max":null,"rate":3}
  ]'::jsonb,
  motor_tpo   = 7500,
  min_premium = 37500,
  -- Single-rate fallback = the top band (3%). Keeps the app correct for the
  -- 3.45M default and all high-value cars before motor_bands is wired into the
  -- premium maths. Once bands are read in-app this line stops mattering.
  motor_rate  = 3,
  phone   = coalesce(phone,   '0703 099 120'),
  email   = coalesce(email,   'callc@cic.co.ke'),
  website = coalesce(website, 'www.cic.co.ke')
where id = 'cic-general';   -- swap to the confirmed CIC id if different

-- STEP 3 (optional)  free (included) extra benefits from the brochure.
-- `benefits` is an array column; use the form that matches its type.
-- jsonb:
-- update funds set benefits = '[
--   "Windscreen up to KES 30,000",
--   "Entertainment system up to KES 30,000",
--   "Third-party property up to KES 5M",
--   "Emergency medical up to KES 30,000",
--   "Towing & recovery up to KES 30,000",
--   "Authorized repairs up to KES 50,000",
--   "Riot & strike covered"
-- ]'::jsonb
-- where id = 'cic-general';
--
-- text[]:
-- update funds set benefits = ARRAY[
--   'Windscreen up to KES 30,000',
--   'Entertainment system up to KES 30,000',
--   'Third-party property up to KES 5M',
--   'Emergency medical up to KES 30,000',
--   'Towing & recovery up to KES 30,000',
--   'Authorized repairs up to KES 50,000',
--   'Riot & strike covered'
-- ]
-- where id = 'cic-general';

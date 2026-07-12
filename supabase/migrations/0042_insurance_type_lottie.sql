-- 0042_insurance_type_lottie.sql
-- Optional animated icon per insurance type. The material `icon` stays as the
-- instant fallback (shown while the animation loads, or when no url is set), so
-- this is purely additive and safe. Host the JSON in a public Storage bucket
-- and paste the URL, or point at any public Lottie URL.
alter table insurance_types add column if not exists lottie_url text;
comment on column insurance_types.lottie_url is 'Optional Lottie JSON url for an animated category icon; material icon is the fallback.';

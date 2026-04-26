create or replace function fix.keyFragment(key STRING) as (
  (key).regexp_replace(r'[\{\[]+','').nullif('').rtrim(':').split(':').array_last().replace('"','')
) OPTIONS (
  description = "Normalizes a key string by removing padding and structural artifacts."
);
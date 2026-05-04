create or replace function fix.jsonKeyFragment(key STRING) as (
  (key).translate('[{','').nullif('').regexp_extract(r'\:?"([^"]+)"\:?$')
) OPTIONS (
  description = "Normalizes a key string by removing padding and structural artifacts."
);
create or replace function fix.jsonTuples(jsn STRING) as (
  (jsn)
    .regexp_replace(r'""\:([^\{\}\[\]]*?)\,""\:([^\{\}\[\]]*?)',r'\1:\2')  -- move quoted keys/values into empty key position and mark insertion point
    .regexp_replace(r'([\{\,])\s*([^"\:\{\[\]\}\s]+)(\s*\:)',  r'\1"\2"\3') -- handle unquoted keys
    --.regexp_replace(r'^\{"":\{','{"_root":{') -- set root in case of unnamed top-level struct
    .replace('"":','"undefined":')
) OPTIONS (
  description = "Resolves empty:non-empty key/value sequences resulting from SQL-to-JSON conversion."
);
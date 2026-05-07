create or replace function fix.jsonTuples(jsn STRING) as (
  (jsn)
    .regexp_replace(r'""\:"?([^\{\}\[\]]*?)"?\,""\:([^\{\}\[\]]*?)',r'"\1":\2')  -- move (unq)quoted keys/values into empty key position and mark insertion point
    .replace('"":','"undefined":')
) OPTIONS (
  description = "Resolves empty:non-empty key/value sequences resulting from SQL-to-JSON conversion."
);
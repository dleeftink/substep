create or replace function get.nearestJSONKeyIndex(jsn STRING,idx INT) as (
  coalesce(
    NULLIF(INSTR(jsn, ',', -1 * (LENGTH(jsn) - idx + 2)), 0),
    NULLIF(INSTR(jsn, '[', -1 * (LENGTH(jsn) - idx + 3)), 0),
    NULLIF(INSTR(jsn, '{', -1 * (LENGTH(jsn) - idx + 2)), 0),
  0 )
) OPTIONS (
  description = "Locates a nearest key-like string based on structural boundaries preceding a JSON index."
);
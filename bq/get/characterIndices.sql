create or replace table function get.characterIndices(str STRING, rgx STRING) as ((
  select regexp_instr(str, rgx, 1, off + 1) AS idx, sub
  from unnest(regexp_extract_all(str, rgx)) AS sub WITH OFFSET AS off
))/* OPTIONS (
  description = "Extracts character indices based on a regex capturing group."
)*/;
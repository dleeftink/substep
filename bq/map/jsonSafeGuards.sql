CREATE OR REPLACE FUNCTION map.jsonSafeGuards(jsn STRING) AS ((

  -- 1. Replace escaped quotes with a unique marker (\x05) so they don't break the SPLIT
  -- 2. Split on the structural double quote (")
  -- 3. Content between quotes will always be at ODD offsets (1, 3, 5...)
  
  WITH chunks AS (
    SELECT 
      part, 
      off,
      MOD(off, 2) = 1 AS is_content
    FROM UNNEST(
      SPLIT(REPLACE(jsn, '\\"', '\x05'), '"')
    ) AS part WITH OFFSET off
  )
  
  -- 4. Re-assemble. If it's content, wrap it back in quotes and apply safeguards
  select array_to_string(
    array(SELECT 
      IF(is_content, 
        CONCAT('"', fix.jsonSafeGuards(part), '"'), 
      part),  
    FROM chunks)  
  ,'')

)) OPTIONS (
  description = "Sanitizes quoted JSON fields by escaping reserved delimiters."
);
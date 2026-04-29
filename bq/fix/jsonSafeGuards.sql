CREATE OR REPLACE FUNCTION fix.jsonSafeGuards(str STRING) AS (
  TRANSLATE(str, 
    '{}[]:,<>()#', 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B])
  )
) OPTIONS (
  description = "Escapes JSON delimiters using control characters or backslashes to prevent parsing collisions."
 );
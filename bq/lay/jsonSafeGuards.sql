CREATE OR REPLACE FUNCTION lay.jsonSafeGuards(str STRING) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B,0x05]),
    '{}[]:,<>()#"'
) OPTIONS (
  description = "Restores control-character markers back to their literal characters."
);
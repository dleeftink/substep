create or replace function fix.unsafeJSON(s STRING, esc BOOL) AS ((s)
  -- 1. JSON Structural Elements (Highest Priority)
  .REPLACE('{', IF(esc, '\x1C', '\\{')) -- FS: File Separator (Object Open)
  .REPLACE('}', IF(esc, '\x1D', '\\}')) -- GS: Group Separator (Object Close)
  .REPLACE('[', IF(esc, '\x02', '\\[')) -- STX: Start Text (Array Open)
  .REPLACE(']', IF(esc, '\x03', '\\]')) -- ETX: End Text (Array Close)
  .REPLACE(':', IF(esc, '\x1E', '\\:')) -- RS: Record Separator (KV Pair)
  .REPLACE(',', IF(esc, '\x1F', '\\,')) -- US: Unit Separator (List Item)

  -- 2. Secondary Wrappers (Lower Priority)
  .REPLACE('<', IF(esc, '\x01', '\\<')) -- SOH: Start Heading
  .REPLACE('>', IF(esc, '\x04', '\\>')) -- EOT: End Transmission
  .REPLACE('(', IF(esc, '\x11', '\\(')) -- DC1: Device Control 1
  .REPLACE(')', IF(esc, '\x13', '\\)')) -- DC3: Device Control 3

  -- 3. Escapes
  .REPLACE('#', IF(esc, '\x1B', '\\#')) -- ESC: Escape
) OPTIONS (
  description = "Escapes JSON delimiters using control characters or backslashes to prevent parsing collisions."
);

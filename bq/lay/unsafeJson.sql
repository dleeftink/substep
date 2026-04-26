create or replace function lay.unsafeJSON(str STRING) AS (
  (str)
  -- 1. JSON Structural Elements (Highest Priority)
  .REPLACE('\x1C','{') -- FS: File Separator (Object Open)
  .REPLACE('\x1D','}') -- GS: Group Separator (Object Close)
  .REPLACE('\x02','[') -- STX: Start Text (Array Open)
  .REPLACE('\x03',']') -- ETX: End Text (Array Close)
  .REPLACE('\x1E',':') -- RS: Record Separator (KV Pair)
  .REPLACE('\x1F',',') -- US: Unit Separator (List Item)
  
  -- 2. Secondary Wrappers (Lower Priority)
  .REPLACE('\x01','<') -- SOH: Start Heading
  .REPLACE('\x04','>') -- EOT: End Transmission
  .REPLACE('\x11','(') -- DC1: Device Control 1
  .REPLACE('\x13',')') -- DC3: Device Control 3
  
  -- 3. Escapes
  .REPLACE('\x1B','#') -- ESC: Escape
  .REPLACE('\x05','"') -- ENQ (Enquiry) - Quote/Query Marker
 
) OPTIONS (
  description = "Restores control-character markers back to their literal characters."
);
create or replace function get.safeJson(object ANY TYPE) as (
  (object).(get.stringifiedJsonFromStruct)().(map.unsafeJson)(true).(fix.emptyJsonKeys)() 
) OPTIONS (
  description = "Serializes a SQL struct to JSON and applies control-character escaping for structural safety."
);
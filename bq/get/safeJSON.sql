create or replace function get.safeJSON(object ANY TYPE) as (
  (object).(get.stringifiedJSONFromStruct)().(map.unsafeJSON)(true).(fix.emptyJSONKeys)() 
) OPTIONS (
  description = "Serializes a SQL struct to JSON and applies control-character escaping for structural safety."
);
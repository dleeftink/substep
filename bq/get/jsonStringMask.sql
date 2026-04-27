create or replace function get.jsonStringMask(object ANY TYPE) as (
  (object).(get.jsonStringFromStruct)().(map.jsonSafeGuards)(true).(fix.jsonTuples)()
) OPTIONS (
  description = "Serializes a SQL struct to JSON and applies control-character escaping for structural safety."
);
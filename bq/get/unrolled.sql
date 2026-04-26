create or replace function get.unrolled(jsn STRING, pairs array<struct<open STRING, close STRING>>, upto INT) as (
  (jsn).(fix.shallowItems)().(use.unroller)(pairs,upto)
) OPTIONS (
  description = "Returns an unrolled JSON string consisting of tuples or (nested) key/value pairs up to a chosen depth."
);
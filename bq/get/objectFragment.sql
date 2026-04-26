create or replace function get.objectFragment(jsn STRING, open INT, close INT) as (
  (jsn).substr(open,close-open+1).(lay.shallowItems)()
) OPTIONS (
  description = "Extracts a specific JSON object fragment and removes temporary structural boundaries."
);
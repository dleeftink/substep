create or replace function lay.shallowItems(jsn STRING) as (
  (jsn).replace('"#":{','').replace('},"#":#','')
) OPTIONS (
  description = "Removes temporary object boundaries from nested JSON items."
);
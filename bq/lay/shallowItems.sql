create or replace function lay.shallowItems(jsn STRING) as (
  (jsn).replace('"#":{','').replace('},"#":#','')
) OPTIONS (
  description = "Unescapes temporarily nested JSON key/value pairs."
);

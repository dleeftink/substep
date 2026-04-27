create or replace function get.jsonKeyFragment(jsn STRING,open INT, keypos INT) as (
  (jsn).substring(keypos+1,greatest(0,open-keypos-0)).ltrim(' ') 
) OPTIONS (
  description = "Extracts a JSON key segment based on open and closing positions."
);
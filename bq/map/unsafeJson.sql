create or replace function map.unsafeJson(jsn STRING, esc BOOL) AS ((
  select string_agg(if(
    (str).starts_with("\x0F"),
      (str).replace("\x0F",'').(fix.unsafeJson)(esc),str),'' order by idx  --> make sure you don't accidentally replace 'safe' \x0F byte markers...
  )  from (
    select (jsn).REPLACE('\\"', if(esc,'\x05','\\“')) -- replace double quote with curly quote “ if esc = false (for debugging)
      .regexp_replace(r'"([^"]*)"', 
        CONCAT(CODE_POINTS_TO_STRING([14, 15]), '"\\1"', CODE_POINTS_TO_STRING([14])) -- 14 = \x0E and 15 = \x0F
      ).split('\x0E') as arr
  ) get, get.arr str with offset idx
)) OPTIONS (
  description = "Sanitizes quoted JSON fields by escaping reserved delimiters."
);
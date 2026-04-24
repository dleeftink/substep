create or replace function map.unsafeJSON(jsn STRING, esc BOOL) AS ((
  select string_agg(if(
    (s).starts_with("\x0F"),
      (s).replace("\x0F",'').(fix.unsafeJSON)(esc),s),'' order by idx  --> make sure you don't accidentally replace 'safe' \x0F byte markers...
  )  from (
    select (jsn).REPLACE('\\"', if(esc,'\x05','\\“')) -- replace double quote with curly quote “ if esc = false (for debugging)
      .regexp_replace(r'"([^"]*)"', 
        CONCAT(CODE_POINTS_TO_STRING([14, 15]), '"\\1"', CODE_POINTS_TO_STRING([14])) -- 14 = \x0E and 15 = \x0F
      ).split('\x0E') as arr
  ) get, get.arr s with offset idx
)) OPTIONS (
  description = "Escapes reserved characters in quoted JSON fields for safe parsing."
);

with init as (

  select '{"id":1   ,   "data":[0,1,2,{"":[    " "  ,  "[]"]},7,{"test":"ok,ay"} ,, 3,,8 , {} ,, {}]},[  "," ],[   1,2,3,,",",   99 ],[{    "named" : {    "struct" :   true }}]' as str
  
),

proc as (
  select (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit) from (
    select str,(str).replace('\\"','\x05\\')
     
     .regexp_extract_all(
    
       ('(').concat(array_to_string([
          
          -- assumes escaped double quotes have been substituted (e.g. with '\x05\\' to maintain same length)
          r'"[^"]*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
          r'(?:"[^"]*"[\s\,]*)+',

          -- handle double quotes directly
          -- r'"(?:[^"\\]|\\.)*"\s*:\s*(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
          -- r'(?:"(?:[^"\\]|\\.)*"[\s\,]*)+',
          
          r'\s+',
          r'(?:[^\[\]\{\}\"]+[\s\,]*)+',
          r'[\[\]\{\}\,]',
          r'[^\[\]\{\}\:\"\,\s]+'
    
        ],'|'),')')
        
      )
      hits from init
  )

)

select * from proc
  
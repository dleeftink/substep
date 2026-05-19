with init as (

  select (minify).if((str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1'),str) str from (
    select '{"id":1   , \n  "data":[0,1,2,{"":[    " "  ,  "[]"]},7,{"test":"ok,ay"} ,, 3,,8 , {} ,, {}]},[  "," ],[   1,2,3,,",",   99 ],[{    "named" : {    "struct" :   true }}]' as str,
      false as minify 
  )

),

proc1 as (

  select str,(str).replace('\\"','\x05\\')
   
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- handle double quotes directly
        -- r'"(?:[^"\\]|\\.)*"\s*:\s*(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
        -- r'(?:"(?:[^"\\]|\\.)*"[\s\,]*)+',
        
        -- assumes escaped double quotes have been substituted (e.g. with '\x05\\' to maintain same length)
        r'"[^"]*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
        r'(?:"[^"]*"[\s\,]*)+',
        
        r'\s+',
        r'(?:[^\[\]\{\}\"]+[\s\,]*)+',
        r'[\[\]\{\}\,]',
        r'[^\[\]\{\}\:\"\,\s]+'
  
      ],'|'),')')
      
    ) as hits from init

),

proc2 as (

  select str,(str).replace('\\"','\x05\\')
   
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
        r'"[^"]*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
        
        -- 2. EXTRACT: Isolated or consecutive string values
        r'(?:"[^"]*"[\s\,]*)+',
        
        -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
        r'\s+',
        
        -- 4. CATCH: Any long sequence of text not containing structural JSON markers
        r'(?:[^\[\]\{\}\"]+[\s,]*)+',
        
        -- 5. CATCH: Individual structural boundaries
        r'[\[\]\{\}\,]',
        
        -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
        r'[^\[\]\{\}\:\"\,\s]+'
      ],'|'),')')
      
    ) as hits from init

),

check as (
  
  select 
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit) from proc1),
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit) from proc2),

)

select * from check

with init as (

  select str from (
    select (hits).to_json_string(true) str from  `stack-curves.tables.hits` 
    union all
    select (hits).to_json_string(true) str from  `stack-curves.tables.hits`   
  ) -- qualify true = max(true) over()
  -- where exists (select 1)
  limit 1

),

-- catch whitespace (pre-escape quotes)

wideEsc as (

  select str,(str).replace('\\"','\x05\\')
   .regexp_extract_all(

    r'('   
      -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
      r'"[^"]*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?'
      
      -- 2. EXTRACT: Isolated or consecutive string values
      r'|' r'(?:"[^"]*"[\s\,]*)+'
      
      -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
      r'|' r'\s+'
      
      -- 4. CATCH: Any long sequence of text not containing structural JSON markers
      r'|' r'(?:[^\[\]\{\}\"\:]+[\s,]*)+'
      
      -- 5. CATCH: Individual structural boundaries
      r'|' r'[\[\]\{\}\,]'
      
      -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
      r'|' r'[^\[\]\{\}\:\"\,\s]+'
    r')'

      
   ) as hits from init

),

-- catch whitespace (directly from string)

wideReg as (

  select str,(str) -- no quote escaping
   .regexp_extract_all(
  
    r'('
      -- 1. EXTRACT: Key/Value pairs (Assumes JSON escaped double quotes inside string fields)
      r'"(?:[^"\\]|\\.)*"\s*:\s*(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?'
      
      -- 2. EXTRACT: Isolated or consecutive string values
      r'|' r'(?:"(?:[^"\\]|\\.)*"[\s\,]*)+'
      
      -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
      r'|' r'\s+'
      
      -- 4. CATCH: Any long sequence of text not containing structural JSON markers
      r'|' r'(?:[^\[\]\{\}\"\:]+[\s,]*)+'
  
      -- 5. CATCH: Individual structural boundaries
      r'|' r'[\[\]\{\}\,]'
      
      -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
      r'|' r'[^\[\]\{\}\:\"\,\s]+'
    r')'
      
   ) as hits from init

),

-- compress whitespace (pre-escape quotes)

bareEsc as (

  select str,
  
  (str).replace('\\"','\x05\\')  
   .regexp_replace(r'("[^"]*")|\s', r'\1')
   .regexp_extract_all(
  
    r'(' 
      -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
      r'"[^"]*":(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])\,?'
      
      -- 2. EXTRACT: Isolated or consecutive string values
      r'|' r'(?:"[^"]*"\,?)+'
              
      -- 3. CATCH: Any long sequence of text not containing structural JSON markers
      r'|' r'(?:[^\[\]\{\}\"\:]+\,?)+'
      
      -- 4. CATCH: Individual structural boundaries
      r'|' r'[\[\]\{\}\,]'
      
      -- 5. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
      r'|' r'[^\[\]\{\}\:\"\,]+'
    r')'
      
    ) as hits from init

),

-- compress whitespace (directly from string)

bareReg as (

  select str,
  
  (str)  -- no quote escaping
   .regexp_replace(r'("(?:[^"\\]|\\.)*")|\s', r'\1') -- remove all structural spacing
   .regexp_extract_all(
  
    r'(' 
      -- 1. EXTRACT: Key/Value pairs (Assumes JSON escaped double quotes inside string fields)
      r'"(?:[^"\\]|\\.)*":(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null|[\[{])\,?'
          
      -- 2. EXTRACT: Isolated or consecutive string values
      r'|' r'(?:"(?:[^"\\]|\\.)*"\,?)+'
              
      -- 3. CATCH: Any long sequence of text not containing structural JSON markers
      r'|' r'(?:[^\[\]\{\}\"\:]+\,?)+'
      
      -- 4. CATCH: Individual structural boundaries
      r'|' r'[\[\]\{\}\,]'
      
      -- 5. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
      r'|' r'[^\[\]\{\}\:\"\,]+'  
    r')'
      
    ) as hits from init

),

check as (
  
  select (select str from init),
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit limit 32) from wideEsc),
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit limit 32) from wideReg),
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit limit 32) from bareEsc),
    (select as struct (str).length(),array(select as struct hit,sum((hit).length()) over() from unnest(hits) hit limit 32) from bareReg),

)

select * from check
with init as (

  select str from (
    select (hits).to_json_string() str from  `stack-curves.tables.hits` 
    union all
    select (hits).to_json_string() str from  `stack-curves.tables.hits`   
  ) -- qualify true = max(true) over()
  -- where exists (select 1)

),

-- wins general case

proc2 as (

  select str,(str).replace('\\"','\x05\\')
   
   -- .regexp_replace(r'("[^"]*")|\s', r'\1')
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
        r'"[^"]*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
        
        -- 2. EXTRACT: Isolated or consecutive string values
        r'(?:"[^"]*"[\s\,]*)+',
        
        -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
        r'\s+',
        
        -- 4. CATCH: Any long sequence of text not containing structural JSON markers
        r'(?:[^\[\]\{\}\"\:]+[\s,]*)+',
        
        -- 5. CATCH: Individual structural boundaries
        r'[\[\]\{\}\,]',
        
        -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
        r'[^\[\]\{\}\:\"\,\s]+'
      ],'|'),')')
      
   ) as hits from init

),

proc2b as (

  select str,(str) -- no quote escaping
   
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
        r'"(?:[^"\\]|\\.)*"\s*:\s*(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])(?:\s*,)?',
        
        -- 2. EXTRACT: Isolated or consecutive string values
        r'(?:"(?:[^"\\]|\\.)*"[\s\,]*)+',
        
        -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
        r'\s+',
        
        -- 4. CATCH: Any long sequence of text not containing structural JSON markers
        r'(?:[^\[\]\{\}\"\:]+[\s,]*)+',
        
        -- 5. CATCH: Individual structural boundaries
        r'[\[\]\{\}\,]',
        
        -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
        r'[^\[\]\{\}\:\"\,\s]+'
      ],'|'),')')
      
   ) as hits from init

),

-- always minified

proc3 as (

  select str,
  
  (str).replace('\\"','\x05\\')  
   --.regexp_replace(r'("[^"]*")|\s', r'\1')
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
        r'"[^"]*":(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])\,?',
        
        -- 2. EXTRACT: Isolated or consecutive string values
        r'(?:"[^"]*"\,?)+',
                
        -- 3. CATCH: Any long sequence of text not containing structural JSON markers
        r'(?:[^\[\]\{\}\"\:]+\,?)+',
        
        -- 4. CATCH: Individual structural boundaries
        r'[\[\]\{\}\,]',
        
        -- 5. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
        r'[^\[\]\{\}\:\"\,]+'
      ],'|'),')')
      
    ) as hits from init

),

-- wins in case of space stripping

proc3b as (

  select str,
  
  (str)  -- no quote escaping
   --.regexp_replace(r'("(?:[^"\\]|\\.)*")|\s', r'\1')
   .regexp_extract_all(
  
     ('(').concat(array_to_string([
        -- 1. EXTRACT: Key/Value pairs (Assumes \" has been swapped to maintain length)
        r'"(?:[^"\\]|\\.)*":(?:"[^"]*"|[-+\d.eE]+|true|false|null|[\[{])\,?',
        
        -- 2. EXTRACT: Isolated or consecutive string values
        r'(?:"(?:[^"\\]|\\.)*"\,?)+',
                
        -- 3. CATCH: Any long sequence of text not containing structural JSON markers
        r'(?:[^\[\]\{\}\"\:]+\,?)+',
        
        -- 4. CATCH: Individual structural boundaries
        r'[\[\]\{\}\,]',
        
        -- 5. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
        r'[^\[\]\{\}\:\"\,]+'
      ],'|'),')')
      
    ) as hits from init

)

select (hits)[safe_offset(cast(rand()*(array_length(hits)-1-0) as int))].right(1) from proc3b --3b

create or replace function tmp.layJsonFragmentPattern2a() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")(?:\s*,)?'
  -- 1. EXTRACT: Named objects/arrays
    '|' r'"(?:[^"\\]|\\.)*"\s*:\s*[\[\{]'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2b() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[\[\{]|(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

-- requires double quote substitution
create or replace function tmp.layJsonFragmentPattern2c() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"[^"]*"\s*:\s*(?:[-+\d.eE]+|true|false|null|"[^"]*")(?:\s*,)?'
  -- 1. EXTRACT: Named objects/arrays
    '|' r'"[^"]*"\s*:\s*[\[\{]'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"[^"]*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

-- requires double quote substitution --> most performant?
create or replace function tmp.layJsonFragmentPattern2d() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"[^"]*"\s*:\s*(?:"[^"]*"|[\[\{]|(?:[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"[^"]*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2e() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"[^"]*":(?:[\[\{]|(?:[-+\d.eE]+|true|false|null|"[^"]*")\,?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"[^"]*"\,*[^\:])+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:]+\,*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2f() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*":(?:[\[\{]|(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")\,?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"(?:[^"\\]|\\.)*"\,*[^\:])+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'\,?(?:[^\[\]\{\}\"\:\,]+\,*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2fb() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*":(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")\,?'
    '|' r'"(?:[^"\\]|\\.)*":[\[\{]'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"(?:[^"\\]|\\.)*"\,*[^\:])+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'\,?(?:[^\[\]\{\}\"\:\,]+\,*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. FALLBACK: Any leftover edge-case characters to ensure 100% losslessness
  --'|' r'[^\[\]\{\}\:\"\,\s]+' 
  -- 7. 
  ')'
);

with init as (
  --select '{"test":[{"a":1},{"b":2}]},{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]},7,{"test":"ok,ay"} ,, 3,,8 , {} ,, {}]},[  "," ],[1],[{    "named" : {    "struct" :   true }}]' as str
  select (hits).to_json_string(false) as str from `stack-curves.tables.hits` 
  -- qualify true = max(true) over()
  limit 1

),

proc as (

  -- select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2a()) hits from init
  
  --select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2d()) hits from init
  --select str,(str).replace('\\"','\x05\\')  .regexp_replace(r'("[^"]*")|\s', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2e()) hits from init
  select str,(str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2f()) hits from init
),

test as (

  -- trim not needed for patterns e/f/fb --> whitespace already removed destructively

  select as struct (str).length() len,
    array(select as struct (hit).rtrim('\t\n\r '),sum((hit).length()) over() 
    from unnest(hits) hit
    ) hits
  from proc

)

select len,hits[safe_offset(cast((array_length(hits)-1)*rand() as int))] from test

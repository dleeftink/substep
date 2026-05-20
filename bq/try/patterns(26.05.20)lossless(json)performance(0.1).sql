create or replace function tmp.layJsonFragmentPattern2a() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")(?:\s*,)?'
  -- 2. EXTRACT: Named objects/arrays
    '|' r'"(?:[^"\\]|\\.)*"\s*:\s*[\[\{]'
  -- 3. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*[^\:])+'
  -- 4. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 5. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 6. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 7. 
  ')'
);

-- current best for space aware matching (needs no post-processing \x05 replacement)
create or replace function tmp.layJsonFragmentPattern2b() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[\[\{]|(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2br() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[\[\{]|(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated string values
  --'|' r'"(?:[^"\\]|\\.)*"[\s\,]*'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*)+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence not containing structural JSON markers
    '|' r'[^\[\]\{\}\"]+[\s\,]*'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. 
  ')'
);

-- requires double quote substitution
create or replace function tmp.layJsonFragmentPattern2c() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and that JSON escaped double quotes have been substituted)
    '(' r'"[^"]*"\s*:\s*(?:[-+\d.eE]+|true|false|null|"[^"]*")(?:\s*,)?'
  -- 2. EXTRACT: Named objects/arrays
    '|' r'"[^"]*"\s*:\s*[\[\{]'
  -- 3. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"[^"]*"[\s\,]*[^\:])+'
  -- 4. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 5. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 6. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 7. 
  ')'
);

-- requires double quote substitution --> most performant?
create or replace function tmp.layJsonFragmentPattern2d() as (
  -- 1. EXTRACT: Named object/arrays and key/Value pairs with optional spacing (assumes spacing and that JSON escaped double quotes have been substituted)
    '(' r'"[^"]*"\s*:\s*(?:"[^"]*"|[\[\{]|(?:[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"[^"]*"[\s\,]*[^\:])+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:\s]+[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 7. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2e() as (
  -- 1. EXTRACT: Named object/arrays and key/Value pairs with optional spacing (assumes spacing removed and that JSON escaped double quotes have been substituted)
    '(' r'"[^"]*":(?:[\[\{]|(?:[-+\d.eE]+|true|false|null|"[^"]*")\,?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"[^"]*"\,*[^\:])+'
  -- 3. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'(?:[^\[\]\{\}\"\:]+\,*)+'
  -- 4. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 5. 
  ')'
);

create or replace function tmp.layJsonFragmentPattern2f() as (
  -- 1. EXTRACT: Named object/arrays and key/Value pairs (assumes spacing removed and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*":(?:[\[\{]|(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")\,?)'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"(?:[^"\\]|\\.)*"\,*[^\:])+'
  -- 3. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'\,?(?:[^\[\]\{\}\"\:\,]+\,*)+'
  -- 4. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 5. 
  ')'
);

-- current best for dense matching (needs no post-processing \x05 replacement)

create or replace function tmp.layJsonFragmentPattern2g() as (
  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing removed and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*":(?:[-+\d.eE]+|true|false|null|"(?:[^"\\]|\\.)*")\,?'
  -- 2. EXTRACT: Named objects/arrays
    '|' r'"(?:[^"\\]|\\.)*":[\[\{]'
  -- 3. EXTRACT: Isolated or consecutive string values
    '|' r'\,?(?:"(?:[^"\\]|\\.)*"\,*[^\:])+'
  -- 4. CATCH: Any long sequence of text not containing structural JSON markers
    '|' r'\,?(?:[^\[\]\{\}\"\:\,]+\,*)+'
  -- 5. CATCH: Individual structural boundaries
    '|' r'[\[\]\{\}\,]'
  -- 6. 
  ')'
);

with init as (
  --select '{"test":[{"a":1},{"b":2}]},{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]},7,{"test":"ok,ay"} ,, 3,,8 , {} ,, {}]},[  "," ],[1],[{    "named" : {    "struct" :   true }}]' as str
  select (hits).to_json_string(false) as str from `stack-curves.tables.hits` 
  -- qualify true = max(true) over()
  limit 1

),

proc as (

  -- assume whitespace -> keep
  -- select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2a()) hits from init
  -- select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2b()) hits from init
  -- select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2c()) hits from init
  select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2d()) hits from init

  -- assume whitespace -> drop
  -- select str,(str).replace('\\"','\x05\\')  .regexp_replace(r'("[^"]*")|\s', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2e()) hits from init
  -- select str,(str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2f()) hits from init
  -- select str,(str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2g()) hits from init

  -- assume whitespace -> none
  -- select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2e()) hits from init
  -- select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2f()) hits from init
  -- select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2g()) hits from init
),

test as (

  -- trim not needed for patterns e/f/g --> whitespace removed destructively or none assumed

  select as struct (str).length() len,
    array(select as struct (hit).rtrim('\t\n\r '),sum((hit).length()) over() 
    from unnest(hits) hit
    ) hits
  from proc

)

select len,hits[safe_offset(cast((array_length(hits)-1)*rand() as int))] from test

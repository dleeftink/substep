create or replace function tmp.layJsonPartials() as (

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
  -- 5. CATCH: Individual structural boundaries with trailing comma (note: may match orphan commas if they weren't already subsumed greedily)
    '|' r'[\[\{\}\]\,]\,?'
  -- 6. 
    ')'
  
);


with init as (

    select (hits).to_json_string(wide) as str,wide from (
      select (hits) from `stack-curves.tables.hits` -- limit 1
      union all
      select (hits) from `stack-curves.tables.hits` -- limit 1
    ),unnest([false]) as wide qualify true = max(true) over()
    limit 1
  
),

line as (

  select '{"test":[{"a":1},{"b":2}],"transaction":null,"nested":{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]}]},"arr":[{},7,],"second":[{"test":"ok,ay"} ,, 3,,8 , {} ,, {}],"arr2":[[  "," ],[1]],"arr3":[{    "named" : {    "struct" :   true }}]}' as str, true as wide

),

proc as (
  
    select str,
      (str)--.regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1')
      .regexp_extract_all(tmp.layJsonPartials())
      as hits,wide
  
    from line
  
  --select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2d()) hits from init
  --select str,(str).replace('\\"','\x05\\').regexp_replace(r'("[^"]*")|\s', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2e()) hits from init
  --select str,(str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2g()) hits from init
),

test as (

  select (str).length() len,
    array(
      select as struct hit,(sym).ifnull(((bare).right(1)=',').if(';',':')) sym,(key = '""').if("undefined",key) key ,val,idx from (
        select hit,bare,
          (bare).right(2).regexp_extract(r'[\{\}\[\]]+\,?') as sym,
          (key).ifnull(if((clip).regexp_contains(r'[\[\{]'),(clip).rtrim(':[{,'),null)) key,
          (jsn[key]).ifnull(jsn) val,idx 
        from (
          select *,(jsn).json_keys(1)[safe_offset(0)] key from (
            select *,coalesce(
              ('{' || clip || '}').(safe.parse_json)(),
              ('[' || clip || ']').(safe.parse_json)()
            ) as jsn from (
              select *,(bare).trim(',') clip from ( 
                select hit,(hit).trim('\t\n\r ').nullif('') bare,(SUM(LENGTH(hit)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx,
                from unnest(hits) hit with offset off
              )
            ) where clip != ''
          )
        )
      ) where sym is not null or key is not null or val is not null
    ) hits
  from proc

)

--select (hits)[safe_offset(cast((array_length(hits)-1)*rand() as int))] from test;
--select (hits).array_last().right(2) from test;

select * from test
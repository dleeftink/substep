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
    '|' r'[\[\{\}\]\,]\s*\,?'
  -- 6. 
    ')'
  
);

create or replace table function tmp.mapJsonFragmentTypes(input table <part string, off int>) as ( 
  from input
    |> extend (part).trim('\t\n\r ').nullif('') bare,
    |> extend (bare).rtrim(',') as clip
    |> extend (clip).right(1) as tail
    |> extend (tail) in ('{','}','[',']').if(tail,'') as sym,((bare).right(1) = ',').if(',','') as sep
    |> extend (SUM(LENGTH(part)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx,
);

create or replace function tmp.getJsonObjects3(str string) as (

  array(
    from unnest (
      (str).regexp_extract_all(tmp.layJsonPartials())
    ) part with offset off
    |> call tmp.mapJsonFragmentTypes()
    |> select as struct * except(part)
  
  )

);

with real as (

    select (hits).to_json_string(wide) as str,wide from (
      select (hits) from `stack-curves.tables.hits` -- limit 1
      union all
      select (hits) from `stack-curves.tables.hits` -- limit 1
    ),unnest([true]) as wide qualify true = max(true) over()
   --  limit 1
  
),

line as (

  --select '{"test":[{"a":1},{"b":2}],"transaction":null,"nested":{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]}]},"arr":[{},7,],"second":[{"test":"ok,ay"} ,, 3,,8 , {} ,, {}],"arr2":[[  "," ],[1]],"arr3":[{    "named" : {    "struct" :   true }}]}' as str, true as wide
  select '{"mixed":[ 1, 2,3,{"nested": true  } ,{"null":true},,,,,4,5,  ", ", " "  ], "okay":false}' as str,true as wide
),

proc as (
  
  select str,tmp.getJsonObjects3(str) as hits,wide
  from line

)

--select (hits)[safe_offset(cast((rand() * array_length(hits)-1) as int))]/*.clip.right(1)*/ from proc;
--select (hits).array_last().right(2) from proc;

select * from proc
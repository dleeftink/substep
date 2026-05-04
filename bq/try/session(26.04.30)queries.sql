-- Source: bq/use/unroller.sql
create or replace table function tmp.unroller(input table<jsn string, pos array<struct<idx int,sub string>>>, rgx string, pick INT) as (

  with init as (

    select jsn,array(
      from unnest(pos)
      |> select idx, sub,
          sum(case when sub = '{' then 1 when sub = '}' then -1 else 0 end) over(w1) as deep,
          sum(case when sub = '[' then 1 when sub = ']' then -1 else 0 end) over(w1) as nest
        window 
          w1 as (order by idx rows between unbounded preceding and current row)
      |> select idx,sub,deep + nest - 1 as depth,deep,nest
      |> select idx,sub, depth - (case when sub in ('{', '[') then 1 else -1 end) as pre, depth,deep,nest,--max(depth) over() deepest
      |> cross join unnest(generate_array(0,/*if(pre+1<deepest,1,0)*/1)) raise
      |> select *
      |> set pre = pre + raise, depth = depth+raise,raise = if(raise = 0,true,false) 
      
      |> aggregate array_agg(struct(pre > depth as pin,raise,idx,sub,nest) order by idx) subs
         group by raise,pre a,depth b
      |> where a < pick + 1 
      |> set a =if(a > b,b,a), b = if(a > b,a,b)

      |> aggregate get.jsonObjectMetadata(any_value(a),any_value(b),array_concat_agg(  
          array(select as struct slot,* except(slot) from unnest(subs) with offset as slot )    
          ),jsn) as level group by a,b
      |> where a < pick and array_length(level.children) > 0

      |> extend 
         sum(array_length(level.children)) over(order by level.depth rows between unbounded preceding and 1 preceding) run1,
         sum(array_length(level.children)) over(order by level.depth rows between unbounded preceding and 2 preceding) run2

      |> order by a,b
      |> select as struct level.depth,array(
        select as struct * except(acid,ocid,ecid,list) from (
  
          select coalesce(slot+run1,0) as nth,coalesce(parent.slot + run2,if(run1 is null,null,0)) as parenth,* replace(
            (select as struct coalesce(parent.slot + run2,if(run1 is null,null,0)) as nth, parent.key,parent.ord) as parent
          )
          from (
            select *,level.parents[range_bucket(child.close,level.looks)] as parent
            from unnest(level.children) as child 
          )
  
        )
      ) as children

    ) as level from input
    
  )

  select * from init

)/* OPTIONS (
  description = "Unrolls a JSON string into a linked parent-child list with structural metadata."
)*/;


-- Source: bq/get/unrolled.sql
/*create or replace table function tmp.unrolled(input table<jsn string>, rgx string, upto INT) as (
  with init as (
    select jsn from input
  )
  select * from tmp.unroller(table init,rgx,upto)

)/* OPTIONS (
  description = "Returns an unrolled JSON string consisting of tuples or (nested) key/value pairs up to a chosen depth."
);*/

-- Source: bq/use/parser.sql
create or replace table function tmp.parser(input table<jsn string>, rgx string, maxDepth INT) as (

  with safe as (
    select *, array(
      select as struct regexp_instr(jsn, rgx, 1, off + 1) AS idx, sub 
      from unnest(regexp_extract_all(jsn, rgx)) AS sub WITH OFFSET AS off
    ) as pos 
      from (
    select (jsn).(fix.jsonPrimitives)() jsn from (
      select jsn from input
      group by jsn having jsn is not null
    ))
  ),

  main as (

    select *,(jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root
    from tmp.unroller(table safe,rgx,maxDepth)

  )

  select * replace(level[safe_offset(0)].children[safe_offset(0)].json as jsn) from main

)/* OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
)*/;

-- TVF calls scalar UDF

-- Make sure not to call jsonPrimitives twice
-- -- Source: bq/get/unrolled.sql
-- create or replace function get.unrolled(jsn STRING, pairs array<struct<open STRING, close STRING>>, upto INT) as (
--   (jsn)/*.(fix.jsonPrimitives)()*/.(use.unroller)(pairs,upto)
-- ) OPTIONS (
--   description = "Returns an unrolled JSON string consisting of tuples or (nested) key/value pairs up to a chosen depth."
-- );

-- Source: bq/use/parser.sql
create or replace table function tmp.parser(input table<jsn string>, rgx string,pairs array<struct<open STRING, close STRING>>, maxDepth INT) as (

  with safe as (
    select (jsn).(fix.jsonPrimitives)() jsn from (
      select jsn from input
      group by jsn having jsn is not null
    )
  ),

  /*main as (

    select *,(jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root
    from tmp.unroller(table safe,rgx,maxDepth)

  )*/

  main as (

    select jsn ,/*array(
      select as struct * replace(array(
        select as struct * replace((json).(lay.jsonSafeGuards)().(safe.parse_json)() as json)
        from unnest(level.children)) as children
      ) from unnest(get.unrolled(jsn,pairs,maxDepth)) level
    ) level,*/
    get.unrolled(jsn,pairs,maxDepth) levels,
     (jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root
    from safe

  )

  select * replace(levels[safe_offset(0)].children[safe_offset(0)].json as jsn) from main

)/* OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
)*/;

with real as (
  select -- Forces materialization of the regex result
    get.jsonStringMask(hits.product[safe_offset(0)]) jsn 
    --use.parser(hits.product[safe_offset(0)],10) dat
  from (
    select * from `stack-curves.tables.hits` -- limit 512
  ) get, get.hits
)

select levels[safe_offset(0)].children[safe_offset(0)].json 
  from tmp.parser(table real,r'[\[\]\{\}]',[('[',']'),('{','}')] ,10)

-- TVF call TVF (string-mask needs to be pre-computed)

-- Source: bq/use/parser.sql
create or replace table function tmp.parser(input table<jsn string>, rgx string, maxDepth INT) as (

  with safe as (
    select (jsn).(fix.jsonPrimitives)() jsn from (
      select jsn from input
      group by jsn having jsn is not null
    )
  ),

  main as (

    select *,(jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root
    from tmp.unroller(table safe,rgx,maxDepth)

  )

  select * replace(level[safe_offset(0)].children[safe_offset(0)].json as jsn) from main

)/* OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
)*/;

with real as (
  select -- Forces materialization of the regex result
    get.jsonStringMask(hits.product[safe_offset(0)]) jsn 
    --use.parser(hits.product[safe_offset(0)],10) dat
  from (
    select * from `stack-curves.tables.hits` -- limit 512
  ) get, get.hits
)

select level[safe_offset(0)].children[safe_offset(0)].json 
  from tmp.parser(table real,r'[\[\]\{\}]' ,10)
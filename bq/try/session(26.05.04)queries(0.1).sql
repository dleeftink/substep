-- this patterns triggers proper query planning, but introduces high amount of shuflling

create or replace table function tmp.jsonObjectLevelProcessor1(
  input table<jsn string,a int,b int, level array<struct<slot int,pin bool,raise bool,idx int,sub string, nest int >>>, pick int
) as (

  with init as (

    from input, unnest(level) as obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by jsn,a,b,slot,raise
    |> extend get.jsonKeyIndex(jsn,head.idx) as kpos
    |> select jsn,cue.jsonObjectInterface(a,b,jsn,head,tail,slot,kpos).*

  ),

  syms as (

    from init
    |> set arr_sym = (key).regexp_extract(r'\:([\[\{]+)').ifnull(key), sym = right(key,1) 
    |> set arr_ctx = if(left(arr_sym,1) = '[' and substring(arr_sym,2,1) in ('[','{'),1,0)

  ),

  keys as (

    from syms
    |> set key = fix.jsonKeyFragment(key)
    |> set key = if(key='#',(json).translate('{}"','').regexp_extract(r'^([^:]+)'),key), sym = if(key='#',key,sym)
    -- |> set key = coalesce(key,last_value(if(not raise,key,null) ignore nulls) over(partition by depth order by open))

  )

  select jsn,array_agg((select as struct objs.* except(jsn))) level from keys as objs -- order by sig,depth
  group by jsn
  
);

-- Source: bq/use/unroller.sql
create or replace table function tmp.unroller(input table<jsn string, pos array<struct<idx int,sub string>>>, pick INT) as (

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

      |> aggregate array_concat_agg(  
          array(select as struct slot,* except(slot) from unnest(subs) with offset as slot )    
          ) as level group by a,b
      /*|> where a < pick and array_length(level.children) > 0

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
      ) as children*/
      |> select as struct *

    ) as levels from input
    
  )

  select * from tmp.jsonObjectLevelProcessor1((select * except(levels) from init get,get.levels),pick)

)/* OPTIONS (
  description = "Unrolls a JSON string into a linked parent-child list with structural metadata."
)*/;

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

    select *,/*(jsn).starts_with('[{') or (jsn).starts_with('[[')*/ null is_array_root
    from tmp.unroller(table safe,maxDepth)

  )

  select * /*replace(level[safe_offset(0)].children[safe_offset(0)].json as jsn)*/ from main

)/* OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
)*/;



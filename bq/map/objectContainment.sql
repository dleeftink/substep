-- TVF candidate:
-- input: a column of array character indices
-- output: 

create or replace table function map.objectContainment(input table<idx INT, sub STRING>, pairs array<struct<open STRING, close STRING>>) as (
  
  with locs as (

    select idx,sub,null as pre,sum(deep) - 1 depth, array_agg(deep) depths,array_agg(pair.open) openers from (
      select array(
        select as struct idx,sub,off,pair, sum(case when sub = pair.open then 1 when sub = pair.close then -1 else 0 end) over(w1) as deep 
        from input window w1 as (order by idx rows between unbounded preceding and current row)
      ) dat from unnest(pairs) pair with offset as off
    ) get,get.dat group by idx,sub

  )
  
  select * except(openers) replace(depth - (case when sub in unnest(openers) then 1 else -1 end) + raise as pre,depth+raise as depth, raise = 0  as raise) 
  from locs,unnest(generate_array(0,/*if(pre+1<deepest,1,0)*/1)) raise
  
)/* OPTIONS (
  description = "Identifies the open and closing indices from provided character pairs."
)*/;
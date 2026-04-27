create or replace table function get.jsonObjectBoundaries(input table <idx INT, sub STRING, pre INT, depth INT, depths array<INT>, raise BOOL>, jsn STRING, pick INT) as ( 

   with init as (
    select * replace(
      if(a > b,b,a) as a,
      if(a > b,a,b) as b
    ) from (
      select raise,pre a, depth b,
        array_agg(struct(pre > depth as pin,raise,idx,sub,depths[0] as nest) order by idx) subs,
      from input -- where depth < coalesce(pick+1,(select max(depth) from locs))
      group by raise,a,b -- qualify depth < coalesce(pick + 1,max(depth) over()) 
      having a < pick + 1 -- and array_length(subs) > 0
    )
  )

  select get.jsonObjectMetadata(a,b,array_concat_agg(  
    array(select as struct slot,* except(slot) from unnest(subs) with offset as slot )    
  ),jsn) as level from init group by a,b having a < pick + 0 order by a,b
  
)/* OPTIONS (
  description = "Groups JSON character indices by discrete object boundaries and depth."
)*/;
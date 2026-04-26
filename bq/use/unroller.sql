create or replace function use.unroller(jsn STRING, pairs array<struct<open STRING, close STRING>>, pick INT) as ((
  
  with init as (
    from get.characterIndices(jsn,(select concat('[',string_agg(concat('\\', pair.open,'\\',pair.close),''),']') from unnest(pairs) pair))
    |> call map.objectContainment(pairs)
    |> call get.objectBoundaries(jsn,pick)
    |> select level.*
  ),

  runs as (

    select *,        
      sum(array_length(children)) over(order by depth rows between unbounded preceding and 1 preceding) run1, 
      sum(array_length(children)) over(order by depth rows between unbounded preceding and 2 preceding) run2  
    from init where array_length(children) > 0
  
  ),

  link as (

    select depth,array(
      select as struct * except(acid,ocid,ecid,list) from (
     
        select coalesce(slot+run1,0) as nth,coalesce(parent.slot + run2,if(run1 is null,null,0)) as parenth,* replace(
          (select as struct coalesce(parent.slot + run2,if(run1 is null,null,0)) as nth, parent.key,parent.ord) as parent
        )
        from (
          select *,parents[range_bucket(child.close,looks)] as parent
          from unnest(children) as child
        )
        
      )
    ) as children from runs
    
  )
  
  select array(select as struct * from link)
   
)) OPTIONS (
  description = "Unrolls a JSON string into a linked parent-child list with structural metadata."
);
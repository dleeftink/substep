create or replace function get.jsonObjectMetadata(a INT, b INT, pack ANY TYPE, jsn STRING) as ((

  with init as (

    from unnest(pack) as obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by slot,raise
    |> extend get.jsonKeyIndex(jsn,head.idx) as kpos
    |> select cue.jsonObjectInterface(a,b,jsn,head,tail,slot,kpos).*
    
  ),
  
  syms as (
  
    from init
    |> set arr_sym = (key).replace('"#":{','').split(':'), sym = right(key,1)
    |> set arr_sym = coalesce(arr_sym[safe_offset(1)],arr_sym[safe_offset(0)])
    |> set arr_ctx = if(left(arr_sym,1) = '[' and substring(arr_sym,2,1) in ('[','{'),1,0)
  
  ),

  keys as (

    from syms       
    |> set key = fix.jsonKeyFragment(key)
    |> set key = if(key='#',(json).translate('{}"','').split(':')[safe_offset(0)],key), sym = if(key='#',key,sym)
    |> set key = coalesce(key,last_value(if(not raise,key,null) ignore nulls) over(partition by depth order by open))

  ),

  locs as (
    
    from keys
    |> set acid = sum(arr_ctx) over(partition by raise,depth order by slot)
    |> set ocid = row_number() over(partition by raise,depth,key order by open)-1
    |> set ecid = row_number() over(partition by raise,ocid order by open)-1
  
    |> set list = if(arr_sym in ("[{","[[") and sym in ("[","{"),true,null) 
    |> set list = coalesce(first_value(list ignore nulls) over(partition by raise,acid order by depth,slot),false)
  
  ),

  ords as ( 
    
    from locs
    |> set key = if(open = 1 and key is null,'$',key)
    |> set key = if(list,concat(coalesce(key,''),'[',row_number() over(partition by raise,depth,acid order by slot)-1,']'),key)
    |> set ord = concat('@{',ocid,',',ecid,'}')

  ),

  aggs as (

    from ords |> as objs 
    |> extend (select as struct objs.* except(raise,pre,depth,kpos,arr_sym,arr_ctx)) as obj,
    |> aggregate 
        array_agg(if(raise,obj,null) ignore nulls order by obj.open) children,
        array_agg(if(not raise,obj,null) ignore nulls order by obj.open) parents,
        array_agg(if(not raise,obj.close,null) ignore nulls order by obj.open) looks group by depth

  )

  select as struct * from aggs
  
)) OPTIONS (
  description = "Generates structural metadata and relational identifiers for packed JSON objects."
);
-- Generally most performant when passing the blob directly
-- Includes optional duplicate filtering based on value equality (see safe.format('%t',blob) > etc.)
-- Decide: pass json as string or json?

create or replace function tmp.getJsonObjectSignature(blob any type,schema string) as ((
  select as struct schema,(blob).to_json_string() str,farm_fingerprint(str) sig,length(str) rel,'any' type 
  from (select safe.format('%t',blob) str)
));

create or replace function tmp.getJsonArraySignature(blob any type,schema string, scan int) as ((
  select as struct schema,(blob).to_json_string() str,farm_fingerprint(str) sig,length(str) rel,'any' type 
  from (
    select if(len = 1,a,a||b) str,len from (
      select len,
        if(scan=0, safe.format('%t',array_first(blob)),
        array_to_string(array(select safe.format('%t',blob[safe_offset(idx)]).ifnull('') from unnest(index) idx),'')) 
        as a,
        
        if(scan=0 and len > 1, safe.format('%t',array_last(blob)),
        array_to_string(array(select safe.format('%t',blob[safe_offset(len-1-idx)]).ifnull('') from unnest(index) idx),''))
        as b
      from (select array_length(blob) len,generate_array(0,scan) index)
    )
  )
));

create or replace function tmp.getJsonObjectMarks(fragment string, tail string) as (
  case  
  when tail in ('[',']') then 
  struct(tail as mark,'ARRAY' as type,(fragment).rtrim(':[').replace('""','"undefined"') as item)
  
  when tail in ('{','}') then 
  struct(tail as mark,'OBJECT' as type,(fragment).rtrim(':{') as item)
  
  else 
  struct(':' as mark, 'ENTRY' as type,fragment as item) 
  end
); 

create or replace function tmp.getParentageFrom(source any type,target any type, step int) as (array(

  select as struct 
    src as source,tgt as target, --tgt.type parent,tgt.data parname,tgt.slot parenth,if(src.entry,src.data,src.type) view,src.slot 
    from unnest(source) src -- ,init
  -- CROSS JOIN UNNEST(target) tgt WHERE src.close between tgt.open and tgt.close
  JOIN ((
    select as struct tgt.*, i * step as bid,max(i) over() buckets
    from unnest(target) tgt,--init,
    unnest(GENERATE_ARRAY(
        DIV(tgt.open, step),
        DIV(tgt.close, step)
      )) as i
    )) tgt 
  on DIV(src.open, step) * step = bid
  and 
    (src.open between tgt.open and tgt.close)
  -- range_contains(tgt.line,src.line)
  -- (src.open < tgt.close)

));

create or replace function tmp.getSearchStepSize(source any type, strength float64) as (
  GREATEST(1, CAST((source.closes - source.opens) / pow(source.size,strength) AS INT64))
);

create or replace function tmp.getJsonAncestors(source any type,target any type) as (
  (source.nodes).(tmp.getParentageFrom)(target.nodes,tmp.getSearchStepSize(target,(1.0 - (1.0 / SQRT(1+target.size))).greatest(0.25).least(1))
));

create or replace function tmp.getJsonObjects2(str string, pick int) as (array(

  from unnest(
    (str).replace('\\"','\x05\\').regexp_extract_all(r'("[^"]*"\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null|[\[\{])|[\[\]\{\}]|\,\s*?)')
  ) AS frag WITH OFFSET AS off
    
  |> extend (SUM(LENGTH(frag)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx, right(frag,1) tail
  |> where tail not in (',',' ',', ')

  |> select idx,tmp.getJsonObjectMarks(frag,tail).*
  |> extend mark in ('{','[') as opener, mark in (']','}') as closer,type in ('ENTRY') as entry
  |> extend if(entry,1,0) as lift 

  |> extend lift + sum(case when opener then 1 when closer then -1 else 0 end) over(w1) - 1 as depth
     window w1 as (order by idx rows between unbounded preceding and current row) 

  |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
  |> where pre < pick 

  |> extend pre > depth as pin
  |> set depth = if(pin,pre,depth)
    
  |> extend row_number() over(partition by depth order by idx) slot 
  |> as obj
  |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by depth,slot - if(closer,1,0) as slot -- if(entry,item,type) 

  |> cross join unnest(generate_array(0,(head.entry or depth >= pick).if(0,2))) raise
  |> set depth = depth + raise --,raise = if(raise = 0,true,false) 
  |> select 
      raise,depth,slot,head.idx as open,tail.idx + if(head.entry,length(head.item).ifnull(1) - 1 ,0) + 1 as close,
      head.mark head,head.type,head.item as data,tail.mark tail,head.entry 
     
  -- |> set data = coalesce(substring(str,open,close-open)/*.left(16).concat('...')*/) -- check if correct index
  -- |> set data = if(entry,parse_json(concat('{',(data).replace('\x05',r'\"'),'}')).to_json_string(),null)  -- optionally parse json ...

  -- |> extend if(not entry,substring(str,greatest(0,open-1),1),null) as arr_ctx

  |> extend range(timestamp_seconds(open),timestamp_seconds(close)) line 

  |> as obj
  |> extend raise = 2 and type = 'ARRAY' as is_root,raise = 1 and not entry as is_stem,raise = 0 as is_leaf
  |> aggregate

      struct(
        min(if(is_leaf,open,null)) as opens,
        max(if(is_leaf,close,null)) as closes,
        array_agg(if(is_leaf,obj,null) ignore nulls /*order by obj.open*/) as nodes,
        countif(is_leaf) as size,
        null as bins
      ) as leaf ,

      struct(
        min(if(is_stem,open,null)) as opens,
        max(if(is_stem,close,null)) as closes,
        array_agg(if(is_stem,obj,null) ignore nulls order by obj.open) as nodes,
        array_agg(if(is_stem,obj.close,null) ignore nulls /*order by obj.open*/) as index,
        countif(is_stem) as size,
        null as bins
      ) stem,

      struct(
        min(if(is_root,open,null)) as opens,
        max(if(is_root,close,null)) as closes,
        array_agg(if(is_root,obj,null) ignore nulls order by obj.open) as nodes,
        array_agg(if(is_root,obj.close,null) ignore nulls /*order by obj.open*/) as index,
        countif(is_root) as size
      ) as root, -- acres

    group by depth
  
  |> where array_length(leaf.nodes) > 0
  -- |> set 
  --     leaf = (select leaf.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *),
  --     stem = (select stem.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *)
  
  |> select as struct depth,leaf,depth depth_2,stem,depth depth_3,root --,bin

));

create or replace table function tmp.mapJsonObjects2(input table< /*schema string,*/str string,sig int /*,rel int,type string*/>, scan bool, dups bool,deep int) as (
  
  with shuf as (
    
    select (str)/*.to_json_string()*/ str from input 
    qualify if(not scan,true,if(dups,true = max(true) over(),row_number() over(partition by sig) = 1))

  )

  select tmp.getJsonObjects2(str,deep) levels from shuf

);

with test as (

  select typeof(blob) type,blob,sel from unnest([struct([
    struct(1 as `id asdasd`, [struct(r'a[]\'s' as sub,2 as val,[struct(1.123 as x,2 as y),(1.0,2),(9.0,0)] as nest),("b",5, [(2.0,3)])] /* as arr */,1 as uid,'x" a' as sub), 
    (2, [("c,a",4,[(3.0,4)]),("d",5,[(5.0,6)])],2,'y STRUCT<>')
    ] as blob,1 as sel),
    struct([
    (3, [("c",4,[(3.0,4)]),("d",5,[(5.0,6)])],2,'x'),
    (4, [("c",4,[(3.0,4)]),("d",5,[(5.0,6)])],2,'y')
    ],0 as sel)
  ])
),

real as (
 
  select
    hits as blob
  from (
    select * from `stack-curves.tables.hits` -- limit 16
  ) --get,get.hits hit -- limit 1

),

sigs as (

  select tmp.getJsonObjectSignature(blob,typeof(blob)).*
  from real limit 1
),

exit as (

  select  -- (levels).array_last().leafs.array_last()-- .data 
    array(
      select as struct *, --depth,--leafs[safe_offset(array_length(leafs)-1)].source.data a,stems[safe_offset(array_length(stems)-1)].target.data b, 
        leafs[safe_offset(array_length(leafs)-1)].target.buckets leaf_buckets,
        stems[safe_offset(array_length(stems)-1)].target.buckets stem_buckets
      from (
        select depth,
          (leaf).(tmp.getJsonAncestors)(stem) as leafs,
          (stem).(tmp.getJsonAncestors)(root) as stems
        from unnest(levels) level -- limit 1 offset 1
      )
  
    )--.array_last() 
    as levels from tmp.mapJsonObjects2(table sigs,scan=>true,dups=>true,deep=>10)
)

select avg(leaf_buckets),avg(stem_buckets) from exit get,get.levels
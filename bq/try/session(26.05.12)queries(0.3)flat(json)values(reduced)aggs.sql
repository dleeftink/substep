-- quite an efficient JSON string extractor
-- can likely be improved by a well-placed unnest in the nest CTE

create temp function getJsonIndex(str string,rgx string) as (array(
  with init as (
    select /*(SUM(LENGTH(sub)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0)*/ off idx, sub,right(sub,1) tail
    from unnest(regexp_extract_all(str,rgx)) AS sub WITH OFFSET AS off
  )

  select as struct idx,(
    case
    when tail in ('[',']') then struct(tail as mark,'ARRAY' as type,(sub).rtrim(':[').replace('""','"undefined"') as item)
    when tail in ('{','}') then struct(tail as mark,'OBJECT' as type,(sub).rtrim(':{') as item)
    else struct(':' as mark, 'ENTRY' as type,sub as item)
    end
  ).* from init where tail not in (',',' ')
));

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
 
  select typeof(blob) type,blob,null as sel from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` -- limit 512
    ) -- get,get.hits hit -- limit 1
  )
),

sigs as (

  -- select farm_fingerprint(safe.format('%t',(blob).array_last()).left(256)) sig,(blob).to_json_string() str from real
  -- qualify row_number() over() = 1 --any_value(true) over(partition by sig) is not null

  
  -- select 0 sig,any_value(blob).to_json_string() str
  --  from real group by blob[0]

  -- various shuffle trigger strategies
  select 0 sig, (blob).to_json_string() str ,
  from real -- ,unnest([generate_uuid()]) sig
  -- qualify row_number() over(partition by generate_uuid()) = 1
  qualify true = max(true) over()-- force perfect shuffle?
 
  -- qualify max(null) over() is null-- force perfect shuffle?
  -- qualify true = max(true) over(partition by cast(rand()*1024 as int)) -- force perfect shuffle?
  -- qualify true = max(true) over(partition by generate_uuid()) -- force perfect shuffle?
  -- qualify true = max(true) over(partition by true) -- for single node
  -- where exists (select true)
  

),

json as (

  select sig,str,(str).replace('\\"','\x05').getJsonIndex(
  ('('
    ||[
    r'"[^"]*"\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null|[\[\{])', -- primitive fields + named structures
    -- r'"[^"]*"\s*:\s*[\[\{]', -- named structures
    r'[\[\]\{\}]', -- structural markers
    r'\,\s*'
    --r'[^\'"\[\]\{\}, ]+' -- remaining values (split)
    
    ].array_to_string('|')
    ||
  ')')
  ) index from sigs

),

nest as (

  select sig,str,array(
    from unnest(index) with offset as temp_slot
   
    |> extend mark in ('{','[') as opener, mark in (']','}') as closer,type in ('ENTRY') as entry
    |> extend sum(case when opener then 1 when closer then -1 else 0 end) over(w1) - 1 as depth
       window w1 as (order by idx rows between unbounded preceding and current row)

    |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
    |> extend if(entry,1,0) as lift

    |> select pre,depth,* except(pre,depth)
    |> set pre = pre + lift , depth = depth + lift

    |> where pre < /*pick*/10 + 1 
    |> extend pre > depth as pin
    |> set depth =  if(pre > depth,pre,depth)
    
    --|> extend row_number() over(partition by depth order by idx) slot 
    |> extend temp_slot as slot
    |> as obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by depth,slot - if(closer,1,0) as slot -- if(entry,item,type)

    |> cross join unnest(generate_array(0,1)) raise
    |> where not (raise = 1 and head.entry)
    |> set depth = depth + raise,raise = if(raise = 0,true,false) 
    |> select 
        raise,depth,slot,head.idx as open,tail.idx + if(head.entry,length(head.item).ifnull(0),0) as close,
        head.mark head,head.type,head.item as data,tail.mark tail,--null as part

    -- |> set data = coalesce(substring(str,open,close-open).left(16).concat('...')) -- check if correct index
    |> as obj
    |> aggregate
        array_agg(if(raise,obj,null) ignore nulls /*order by obj.open*/) children,
        -- array_agg(if(not raise and type in ("ARRAY","OBJECT"),obj,null) ignore nulls order by obj.open) parents,
        -- array_agg(if(not raise and type in ("STRUCT","ARRAY"),obj.close,null) ignore nulls order by obj.open) looks 
      group by depth
   
    |> where array_length(children) > 0   
    |> select as struct array_length(children) len,*,
    -- |> select as struct *
    -- |> order by depth

  ) as levels from json

)

--select getJsonBlobSigFromArray(blob,type,0,0).sig from real group by sig
-- select sig,(levels).array_last().children.array_last().data
--   from nest

select sig,(levels).array_last().children.array_last().data.length()
 from nest

--select (blob).to_json_string().length() from (
--  select any_value(blob) blob from real group by blob[0] -- limit 1
--)

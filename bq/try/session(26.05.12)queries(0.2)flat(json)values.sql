-- quite an efficient JSON string extractor
-- can likely be improved by a well-placed unnest in the nest CTE

create temp function getJsonIndex(str string,rgx string) as (array(
  with init as (
    select (SUM(LENGTH(sub)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx, sub,right(sub,1) tail
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

-- processing gets prohibitively expensive for real data

real as (
 
  select typeof(blob) type,blob,null as sel from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` limit 1
    ) --get,get.hits hit -- limit 1
  )
),

json as (

  select (blob).to_json_string() str,(blob).to_json_string().replace('\\"','\x05').getJsonIndex(
  ('('
    ||[
    r'"[^"]*"\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null)', -- primitive fields
    r'"[^"]*"\s*:\s*[\[\{]', -- named structures
    r'[\[\]\{\}]', -- structural markers
    r'\,\s*'
    --r'[^\'"\[\]\{\}, ]+' -- remaining values (split)
    
    ].array_to_string('|')
    ||
  ')')
  ) val from real -- limit 15 

),

nest as (

  select str,array(
    from unnest(val)
    |> extend mark in ('{','[') as opener, mark in (']','}') as closer,type in ('ENTRY') as entry
    |> extend sum(case when opener then 1 when closer then -1 else 0 end) over(w1) - 1 as depth
       window w1 as (order by idx rows between unbounded preceding and current row)

    |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
    |> extend if(entry,1,0) as lift

    |> select pre,depth,* except(pre,depth)
    |> cross join unnest(generate_array(0,/*if(pre+1<deepest,1,0)*/1)) raise
    |> set pre = pre + raise + lift , depth = depth + raise + lift,raise = if(raise = 0,true,false) 

  
    |> aggregate array_agg(struct(pre > depth as pin,raise,idx,mark,type,item,entry) order by idx) subs
       group by raise,pre a,depth b
    
    |> select a,b,subs
    |> where a < /*pick*/10 + 1 
    |> set a = if(a > b,b,a), b = if(a > b,a,b)

    |> cross join unnest(subs) obj with offset as slot 
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by a,b,slot--,raise
    |> select 
        head.raise,b as depth,slot,head.idx as open,tail.idx + if(head.entry,length(head.item).ifnull(0),0) as close,
        head.mark head,head.type,head.item as data,tail.mark tail,--null as part

    -- |> set data = coalesce(data,substring(str,open,close-open).left(16).concat('...')) -- check if correct index

    |> as obj
    |> aggregate
        array_agg(if(raise,obj,null) ignore nulls order by obj.open) children,
        -- array_agg(if(not raise and type in ("STRUCT","ARRAY"),obj,null) ignore nulls order by obj.open) parents,
        -- array_agg(if(not raise and type in ("STRUCT","ARRAY"),obj.close,null) ignore nulls order by obj.open) looks 
      group by depth
    |> select as struct *,
  
   
    |> where array_length(children) > 0   
    |> select as struct array_length(children),*,
    |> order by depth

  ) as vals from json

)

 select vals -- (vals).array_last().children.array_last().data 
   from nest

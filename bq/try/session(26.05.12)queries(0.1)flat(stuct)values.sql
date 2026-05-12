create temp function getStructuralChars(str string,rgx string) as (array(
  with init as (
    select SUM(LENGTH(sub)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING).ifnull(0) idx, sub,left(sub,1) open
    from unnest(regexp_extract_all(str,rgx)) AS sub WITH OFFSET AS off
  )

  select as struct idx,(
    case
    when sub in ('[',']') then struct(sub as mark,'ARRAY' as type,null as item)
    when sub in ('(',')') then struct(sub as mark,'STRUCT' as type,null as item)
    when open in ('\'','"') then struct(open as mark,'STRING' as type,sub as item)
    else struct(cast(null as string) as mark, null as type,sub as item)
    end
  ).* from init  where sub != ', '
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
      select * from `stack-curves.tables.hits`  -- limit 512
    ) -- get,get.hits hit -- limit 1
  )
),

prep as (

  select safe.format('%T',blob).getStructuralChars(
  ('('||[
    r'"[^"]*"', -- double quoted fields
    r'\'[^\']*\'', -- single quoted fields
    --r'[A-Za-z_]+\("[^"]*"\)', -- geographies
    r'[\[\]\(\)]', -- structural markers

    r'\, ', 
    r'[^\'"\[\]\(\)]+' -- remaining values (squash)
    --r'[^\'"\[\]\(\), ]+' -- remaining values (split)
    ].array_to_string('|')||')')
  ) val from real

),

nest as (

  select array(
    from unnest(val)
    |> extend sum(case when mark in ('(','[') then 1 when mark in (')',']') then -1 else 0 end) over(w1) - 1 as depth
       window w1 as (order by idx rows between unbounded preceding and current row)
    |> extend depth - (case when mark in ('(','[')  then 1 when mark in (')',']') then -1 else 0 end) as pre
    |> select pre,depth,* except(pre,depth)

    |> cross join unnest(generate_array(0,/*if(pre+1<deepest,1,0)*/1)) raise
    |> set pre = pre + raise /*+ if(mark is null,1,0)*/, depth = depth + raise /*+ if(mark is null,1,0)*/,raise = if(raise = 0,true,false) 

    |> aggregate array_agg(struct(pre > depth as pin,raise,idx,mark,type,item) order by idx) subs
       group by raise,pre a,depth b
    
    |> select a,b,subs 
    |> where a < /*pick*/10 + 1 
    |> set a = if(a > b,b,a), b = if(a > b,a,b)
    |> set subs = array(select as struct slot,* except(slot) from unnest(subs) with offset as slot)

    |> cross join unnest(subs) obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by a,b,slot,raise
    |> select 
        head.raise,b as depth,slot,head.idx as open,tail.idx + if(head.mark is null,length(head.type).ifnull(0)+length(head.item).ifnull(0)+1,0) as close,
        head.mark head,head.type,head.item,tail.mark tail,--null as part
    --|> set item = coalesce(item,substring(keystr,open,close-open).left(16).concat('...'))
    |> where raise
    
    |> select as struct *,
    --|> order by depth,open

  ) key from prep

)

--select format('%T',blob) from test

select (key).array_last().close from nest

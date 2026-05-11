create temp function getCharacterIndices(str string,rgx string) as (array(
  with init as (
    select regexp_instr(str, rgx, 1, off + 1) AS idx, sub
    from unnest(regexp_extract_all(str, rgx)) AS sub WITH OFFSET AS off
  )

  select as struct idx,(
    case
    when (sub).ends_with('<') then struct('<' as mark,(sub).rtrim('<').regexp_replace(r'^.* ','') as type,(sub).regexp_replace(r'[^ ][A-Z<]+$','').nullif('') as item)
    when (sub).ends_with('>') then struct('>' as mark,null as type,null as item)
    else (select struct(cast(null as string) as mark,s[safe_offset(1)] as type,s[safe_offset(0)] as item) from (select (sub).split(' ') s)) -- be careful: keys may contain spaces
    end
  ).* from init
));

with test as (

  select typeof(blob) type,blob,sel from unnest([struct([
    struct(1 as id, [struct("a" as sub,2 as val,[struct(1 as x,2 as y),(1,2),(9,0)] as nest),("b",5, [(2,3)])],1 as uid,'x' as sub), 
    (2, [("c,a",4,[(3,4)]),("d",5,[(5,6)])],2,'y')
    ] as blob,1 as sel),
    struct([
    (3, [("c",4,[(3,4)]),("d",5,[(5,6)])],2,'x'),
    (4, [("c",4,[(3,4)]),("d",5,[(5,6)])],2,'y')
    ],0 as sel)
  ])
),

prep as (

  -- to do: handle spaces in schema keys
  --select sel,(type).replace('`','"').(map.jsonSafeGuards)() key,format('%T',blob).(map.jsonSafeGuards)().replace('[','ARRAY<').replace('(','STRUCT<').translate('])','>>') val from test
  
  select sel, strs[0] as key, strs[1].replace('[','ARRAY<').replace('(','STRUCT<').translate('])','>>')  as val from (
    select sel, array(select (str).(map.jsonSafeGuards)() from unnest([(type).replace('`','"'),format('%T',blob)]) str) strs from test
  )

),

char as (
  
  select sel,
    (key).getCharacterIndices(r'((?:[<>]?)(?:ARRAY|STRUCT)(?:[<>]?)|[<>]|(?:[^ ,]+ [A-Z0-9]+[<]?))') as key,
    (val).getCharacterIndices(r'((?:[<>]?)(?:ARRAY|STRUCT)(?:[<>]?)|[<>]|(?:[^ ,<>]+[,]?))') val,
  from prep

),

nest as (

  select array(
    from unnest(key)
    |> extend
        sum(case when mark = '<' then 1 when mark = '>' then -1 else 0 end) over(w1) - 1 as depth
      window 
        w1 as (order by idx rows between unbounded preceding and current row)
    |> extend depth - (case when mark = '<' then 1 when mark = '>' then -1 else 0 end) as pre
    |> select pre,depth,* except(pre,depth)

    |> cross join unnest(generate_array(0,/*if(pre+1<deepest,1,0)*/1)) raise
    |> select *
    |> set pre = pre + raise /*+ if(mark is null,1,0)*/, depth = depth + raise /*+ if(mark is null,1,0)*/,raise = if(raise = 0,true,false) 

    |> aggregate array_agg(struct(pre > depth as pin,raise,idx,mark,type,item) order by idx) subs
       group by raise,pre a,depth b
    
    |> select a,b,subs 
    |> where a < /*pick*/10 + 1 
    |> set a = if(a > b,b,a), b = if(a > b,a,b)
    |> set subs = array(select as struct slot,* except(slot) from unnest(subs) with offset as slot )

    |> cross join unnest(subs) obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by a,b,slot,raise
    |> select head.raise,b as depth,slot,a as pre,head.idx as open,tail.idx as close,head.mark head,head.type,head.item,tail.mark tail
    |> where raise
    
    |> select as struct *
    |> order by depth,open


  ) key from char


)

--select array(select as struct *,countif(mark = '<') over(),countif(mark = '>') over() from unnest(key) where mark in ('<','>')) from char

select * from nest
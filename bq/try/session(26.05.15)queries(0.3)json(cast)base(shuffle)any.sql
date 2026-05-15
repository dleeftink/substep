-- Generally most performant when passing the blob directly
-- Includes optional duplicate filtering based on value equality (see safe.format('%t',blob) > etc.)

create or replace function tmp.getJsonBlobSig1(blob any type,schema string) as ((
  select as struct schema,(blob).to_json() jsn,farm_fingerprint(str) sig,length(str) rel,'any' type 
  from (select safe.format('%t',blob) str)
));

create or replace function tmp.getJsonObjectsFromJson1(str string) as (array(

  from unnest(
    (str).replace('\\"','\x05').regexp_extract_all(r'("[^"]*"\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null|[\[\{])|[\[\]\{\}\, ])')
  ) AS sub WITH OFFSET AS off
    
  |> extend (SUM(LENGTH(sub)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx, right(sub,1) tail
  |> where tail not in (',',' ')

  |> select idx,(
     case
     when tail in ('[',']') then struct(tail as mark,'ARRAY' as type,(sub).rtrim(':[').replace('""','"undefined"') as item)
     when tail in ('{','}') then struct(tail as mark,'OBJECT' as type,(sub).rtrim(':{') as item)
     else struct(':' as mark, 'ENTRY' as type,sub as item)
     end
  ).* 

  |> extend mark in ('{','[') as opener, mark in (']','}') as closer,type in ('ENTRY') as entry
  |> extend sum(case when opener then 1 when closer then -1 else 0 end) over(w1) - 1 as depth
     window w1 as (order by idx rows between unbounded preceding and current row) 

  |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
  |> extend if(entry,1,0) as lift 
  |> set pre = pre + lift , depth = depth + lift 

  |> where pre < /*pick*/10 + 1 
  |> extend pre > depth as pin
  |> set depth =  if(pin,pre,depth)
    
  |> extend row_number() over(partition by depth order by idx) slot |> as obj
  |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by depth,slot - if(closer,1,0) as slot -- if(entry,item,type) 

  |> cross join unnest(generate_array(0,1)) raise
  |> where not (raise = 1 and head.entry)
    
  |> set depth = depth + raise,raise = if(raise = 0,true,false) 
  |> select 
      raise,depth,slot,head.idx as open,tail.idx + if(head.entry,length(head.item).ifnull(1)-1,0) + 1 as close,
      head.mark head,head.type,head.item as data,tail.mark tail,head.entry 
     
  -- |> set data = if(entry,parse_json(concat('{',(data).replace('\x05',r'\"'),'}')),null) --coalesce(substring(str,open,close-open).left(16).concat('...')) -- check if correct index

  |> as obj
  |> aggregate
      array_agg(if(raise,obj,null) ignore nulls /*order by obj.open*/) children,
      array_agg(if(not raise and type in ("ARRAY","OBJECT"),obj,null) ignore nulls order by obj.open) parents,
      -- array_agg(if(not raise and type in ("ARRAY","OBJECT"),obj.close,null) ignore nulls order by obj.open) looks 
    group by depth
  
  |> where array_length(children) > 0   
  |> select as struct array_length(children) len,*

));


create or replace table function tmp.mapJsonObjects1(input table< /*schema string,*/jsn json,sig int /*,rel int,type string*/>, scan bool, dups bool) as (
  
  with shuf as (
    
    select (jsn).to_json_string() str from input 
    qualify if(not scan,true,if(dups,true = max(true) over(),row_number() over(partition by sig) = 1))

  )

  select tmp.getJsonObjectsFromJson1(str) levels from shuf

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

  select tmp.getJsonBlobSig1(blob,typeof(blob)).*
  from real
)

select (levels).array_last().children.array_last() from tmp.mapJsonObjects1(table sigs,scan=>true,dups=>true)

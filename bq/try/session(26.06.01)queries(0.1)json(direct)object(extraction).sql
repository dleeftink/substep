-- this version is head-to-head with session(26.05.15)queries(0.3)json(cast)base(shuffle)any.sql
-- but still a little slower; however we extract long string or value sequences ('runs') as a single datum

create or replace function tmp.layJsonPartials() as (

  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*[\[\{]?'
  --'|' r'(?:[-+\d.eE]+|true|false|null)(?:\s*,)?'

  -- 2. EXTRACT: Isolated string values
  --'|' r'"(?:[^"\\]|\\.)*"[\s\,]*'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'"(?:[^"\\]|\\.)*"[\s\,]*' -- n = 1 sequences
    '|' /*r'(?:\,\s*)?*/ r'(?:"(?:[^"\\]|\\.)*"[\s\,]*){3,}'  -- n > 2 sequences
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence not containing structural JSON markers
    '|' r'[^\[\]\{\}\"\:]+[\s\,]*'
  -- 5. CATCH: Individual structural boundaries with trailing comma (note: may match orphan commas if they weren't already subsumed greedily)
    '|' r'[\}\]\,]\s*\,?'
    '|' r'[\[\{]'
  -- 6. 
    ')'
  
);

create or replace table function tmp.mapJsonFragmentTypes2(/*input table<part string, off int>*/ parts array<string>) as ( 
  from unnest(parts) part with offset off 
  |> extend LENGTH(part) as len
  |> extend (SUM(len) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx,lag(part) over(order by off) as prev,
  |> extend (part).trim('\t\n\r ').nullif('') bare 
  --|> where bare is not null

  |> extend (bare).rtrim('\t\n\r ,') as clip
  |> extend (clip).right(1) as tail
  |> where /*tail is not null and*/ tail != (':')
  
  |> set prev = (prev).rtrim('\t\n\r ').nullif('')
  |> extend 
      (tail) in ('{','}') as obj,
      (tail) in ('[',']') as arr,
      (bare).right(1) in (',') as sep,
      (prev).right(1) in (':') as anc

  |> extend not (obj or arr) as val,
  |> extend (not val).if(tail,null) as sym,case when obj then 'OBJECT' when arr then 'ARRAY' else 'ENTRY' end cat
  |> extend val and not anc as run, if(val and anc,prev,null) as key,if(val,bare,null) as dat -- bare for reconstruction / clip for direct json construction
  |> extend (run).if(length(clip) - (clip).regexp_replace(r'("(?:[^"\\]|\\.)*")|\,', r'\1').length() + 1,null) as cap

  |> set key = if(not val and (clip).starts_with('"'), (clip).rtrim('{['),key)
  |> set key = if((key).starts_with(""),(key).replace('""','"undefined"'),key)
  |> select idx,cat,sym,key,sep,dat,len,cap

);

create or replace aggregate function tmp.getJsonObjectNodes3(
  pick BOOL, obj STRUCT<slot INT64, open INT64, close INT64, head STRING, type STRING, key STRING, data STRING, tail STRING, entry BOOL>
) as (
  struct(
    min(if(pick,obj.open,null)) as opens,
    max(if(pick,obj.close,null)) as closes,
    array_agg(if(pick,obj,null) ignore nulls /*order by obj.open*/) as nodes,
    countif(pick) as size
  )
);

create or replace function tmp.getJsonObjects4(str string, rgx string,pick int) as (

  array(
    -- from unnest((str).regexp_extract_all(rgx)) as part with offset off
    -- |> call tmp.mapJsonFragmentTypes2()
    from tmp.mapJsonFragmentTypes2((str).regexp_extract_all(rgx))

    |> extend sym in ('{','[') as opener, sym in (']','}') as closer,cat in ('ENTRY') as entry
    |> extend if(entry,1,0) as lift 

    |> extend lift + sum(case when opener then 1 when closer then -1 else 0 end) over(w1) - 1 as depth
       window w1 as (order by idx rows between unbounded preceding and current row) 

    |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
    |> where pre < pick 

    |> extend pre > depth as pin
    |> set depth = if(pin,pre,depth) 
    |> extend row_number() over(partition by depth order by idx) slot 
    |> as obj
  
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by depth , slot - if(closer,1,0) as slot -- if(entry,item,type) 
    |> set slot = row_number() over(partition by depth order by slot)
    
    |> cross join unnest(generate_array(0,(head.entry or depth >= pick).if(0,2))) raise
    |> set depth = depth + raise
    |> select 
        raise,depth,slot,head.idx as open,tail.idx + if(head.entry,(head.len).ifnull(1) - 1 ,0) + 1 as close,
        head.sym head,head.cat type,head.key,head.dat as data,tail.sym tail,head.entry 
       
    -- |> set data = coalesce(substring(str,open,close-open)/*.left(16).concat('...')*/) -- check if correct index
    -- |> set data = if(entry,parse_json(concat('{',(data).replace('\x05',r'\"'),'}')).to_json_string(),null)  -- optionally parse json ...
  
    -- |> extend if(not entry,substring(str,greatest(0,open-1),1),null) as arr_ctx
    -- |> extend range(timestamp_seconds(open),timestamp_seconds(close)) line 
    
    |> extend struct(slot,open,close,head,type,key,data,tail,entry) as obj -- |> as obj
    |> extend raise = 2 and type = 'ARRAY' as is_root,(raise = 1 and not entry) or depth = 0 as is_stem,raise = 0 as is_leaf
    |> aggregate
  
        tmp.getJsonObjectNodes3(is_leaf,obj) as leaf,
        tmp.getJsonObjectNodes3(is_stem or depth = 0,obj) as stem, -- always include top-level objects so we don't end up with an empty inner join later
        tmp.getJsonObjectNodes3(is_root /*or depth = 1 */,obj) as root,
  
      group by depth
    
    |> where array_length(leaf.nodes) > 0
    --|> where leaf.nodes[safe_offset(0)] is not null
    -- |> set 
    --     leaf = (select leaf.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *),
    --     stem = (select stem.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *)
    
    |> select as struct depth,leaf,depth depth_2,stem,depth depth_3,root --,bin

  )

);

create or replace table function tmp.mapJsonObjects4(input table< /*schema string,*/str string,sig int /*,rel int,type string*/>, scan bool, dups bool,deep int) as (
  
  with shuf as (
    
    select sig,(str)/*.to_json_string()*/ str from input 
    qualify if(not scan,true,if(dups,true = max(true) over(),row_number() over(partition by sig) = 1))

  ),

  flat as (

    select * except(strs) from (
      select * except(str), json_query_array(str,'$') strs 
      from shuf
    ) get,get.strs str

  )

  select str,sig,tmp.getJsonObjects4(str,tmp.layJsonPartials(),deep) levels from shuf

);

with real as (

    select hits as blob,(hits).to_json_string(wide) as str,wide from (
      select (hits) from `stack-curves.tables.hits` -- limit 1
      union all
      select (hits) from `stack-curves.tables.hits` -- limit 1
    ),unnest([false]) as wide -- qualify true = max(true) over()
   limit 1
  
),

line as (

  --select '{"test":[{"a":1},{"b":2}],"transaction":null,"nested":{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]}]},"arr":[{},7,],"second":[{"test":"ok,ay"} ,, 3,,8 , {} ,, {}],"arr2":[[  "," ],[1]],"arr3":[{    "named" : {    "struct" :   true }}]}' as str, true as wide
  select '{"objarry":[  {"id": 1},{"id":2},[0,1,2],[ , ,, "oi"]],"":[ 1, 2,3,{"nested"   : {"more":true}  } ,{"null":true},, ,,, ,true, ,4,5,  ", ", " ", "äsd",,,,"top","asd"  ], "okay":false}' as str,true as wide
  --select '[{"hostname":"shop.googlemerchandisestore.com","pageTitle":"YouTube","searchKeyword":null,"searchCategory":null,"pagePathLevel1":"/google+redesign/","pagePathLevel2":"/shop+by+brand/"}]' as str,true as wide
),

sigs as (

  -- select tmp.getJsonObjectSignature(blob,typeof(blob)).*
  -- from real -- limit 1

  select str,farm_fingerprint(str) as sig
  from line

)

select str,length(str) len,/*array(
  select as struct part,(part).trim('\t\n\r ').nullif('') bare,(SUM(LENGTH(part)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx,
  from unnest(levels) with offset off
)*/ (levels) from tmp.mapJsonObjects4(table sigs,scan=>true,dups=>true,deep=>10)

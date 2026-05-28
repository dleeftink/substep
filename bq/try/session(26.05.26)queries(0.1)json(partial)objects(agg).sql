create or replace function tmp.layJsonPartials() as (

  -- 1. EXTRACT: Key/Value pairs with optional spacing (assumes spacing and regular JSON escaped double quotes inside string fields)
    '(' r'"(?:[^"\\]|\\.)*"\s*:\s*(?:[\[\{]|(?:"(?:[^"\\]|\\.)*"|[-+\d.eE]+|true|false|null)(?:\s*,)?)'
  -- 2. EXTRACT: Isolated string values
  --'|' r'"(?:[^"\\]|\\.)*"[\s\,]*'
  -- 2. EXTRACT: Isolated or consecutive string values
    '|' r'(?:\,\s*)?(?:"(?:[^"\\]|\\.)*"[\s\,]*)+'
  -- 3. CATCH: Pure whitespace blocks (Highly optimized in RE2)
    '|' r'\s+'
  -- 4. CATCH: Any long sequence not containing structural JSON markers
    '|' r'[^\[\]\{\}\"]+[\s\,]*'
  -- 5. CATCH: Individual structural boundaries with trailing comma (note: may match orphan commas if they weren't already subsumed greedily)
    '|' r'[\[\{\}\]\,]\s*\,?'
  -- 6. 
    ')'
  
);

-- value parsing: incurs heavy compute (key,dat,cap)

create or replace table function tmp.mapJsonFragmentTypes(input table <part string, off int>) as ( 
  from input
  |> extend (SUM(LENGTH(part)) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + 1 ).ifnull(0) idx,
  |> extend (part).trim('\t\n\r ').nullif('') bare 
  |> where bare is not null

  |> extend (bare).rtrim(',') as clip
  |> extend length(clip) as size 
  |> extend (clip).rtrim('\t\n\r ').right(1) as tail --, (clip).right(size - (clip).rtrim('\t\n\r[ {').length()).translate('\t\n\r ','') longtail
  |> extend 
      (tail) in ('{','}') as obj,
      (tail) in ('[',']') as arr,
      (clip).regexp_extract(r'^("(?:[^"\\]|\\.)*"\s*:\s*)') as key, 
      (bare).right(1) in (',').if(',',null) as sep,
  
  |> extend (obj or arr).if(tail,null) as sym,case when obj then 'OBJECT' when arr then 'ARRAY' else 'ENTRY' end cat
  |> extend (key is not null and sym is null).if((clip).right(size-length(key)),null) as dat
  |> extend key is null and sym is null and dat is null as run

  -- to do: handle sparse arrays consistently
  |> extend (run).if(length(clip) - (clip).regexp_replace(r'("(?:[^"\\]|\\.)*")|\,', r'\1').length() + 1,null) as cap
  |> set key = (key).rtrim(': ').replace('""','"undefined"'),dat = (run).if(clip,dat)
  |> select idx,cat,sym,key,sep,dat,cap

);

create or replace function tmp.getJsonObjectPartials(str string) as ((str).regexp_extract_all(tmp.layJsonPartials()));

create or replace function tmp.getJsonObjects3(str string, pick int) as (

  array(
    from unnest((str).regexp_extract_all(tmp.layJsonPartials())) as part with offset off 
    |> call tmp.mapJsonFragmentTypes()

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
        raise,depth,slot,head.idx as open,tail.idx + if(head.entry,length(head.dat).ifnull(1) - 1 ,0) + 1 as close,
        head.sym head,head.cat type,head.dat as data,tail.sym tail,head.entry 
       
    -- |> set data = coalesce(substring(str,open,close-open)/*.left(16).concat('...')*/) -- check if correct index
    -- |> set data = if(entry,parse_json(concat('{',(data).replace('\x05',r'\"'),'}')).to_json_string(),null)  -- optionally parse json ...
  
    -- |> extend if(not entry,substring(str,greatest(0,open-1),1),null) as arr_ctx
    -- |> extend range(timestamp_seconds(open),timestamp_seconds(close)) line 
    
    |> extend struct(slot,open,close,head,type,data,tail,entry) as obj -- |> as obj
    |> extend raise = 2 and type = 'ARRAY' as is_root,raise = 1 and not entry as is_stem,raise = 0 as is_leaf
    |> aggregate
  
        tmp.getJsonObjectNodes2(is_leaf,obj) as leaf,
        tmp.getJsonObjectNodes2(is_stem or depth = 0,obj) as stem, -- always include top-level objects so we don't end up with an empty inner join later
        tmp.getJsonObjectNodes2(is_root /*or depth = 1 */,obj) as root,
  
      group by depth
    
    |> where array_length(leaf.nodes) > 0
    -- |> set 
    --     leaf = (select leaf.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *),
    --     stem = (select stem.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *)
    
    |> select as struct depth,leaf,depth depth_2,stem,depth depth_3,root --,bin
   
  
  )

);


create or replace table function tmp.mapJsonObjects3(input table< /*schema string,*/str string,sig int /*,rel int,type string*/>, scan bool, dups bool,deep int) as (
  
  with shuf as (
    
    select sig,(str)/*.to_json_string()*/ str from input 
    qualify if(not scan,true,if(dups,true = max(true) over(),row_number() over(partition by sig) = 1))

  )

  select sig,tmp.getJsonObjects3(str,deep,tmp.layJsonPartials()) levels from shuf

);


with real as (

    select hits as blob,(hits).to_json_string(wide) as str,wide from (
      select (hits) from `stack-curves.tables.hits` -- limit 1
      union all
      select (hits) from `stack-curves.tables.hits` -- limit 1
    ),unnest([false]) as wide -- qualify true = max(true) over()
   --  limit 1
  
),

line as (

  --select '{"test":[{"a":1},{"b":2}],"transaction":null,"nested":{"id":1,"data":[ ,  0,  "" ,1,  2,   {"":[,  " "  ,  "[]"   ]}]},"arr":[{},7,],"second":[{"test":"ok,ay"} ,, 3,,8 , {} ,, {}],"arr2":[[  "," ],[1]],"arr3":[{    "named" : {    "struct" :   true }}]}' as str, true as wide
  select '{"objarry":[  {"id":1},{"id":2},[["nested"]],["oi"]],"":[ 1, 2,3,{"nested": true  } ,{"null":true},, ,,, ,, ,4,5,  ", ", " "  ], "okay":false}' as str,true as wide
),

proc as (
  
  select str,(str).length() len,tmp.getJsonObjects3(str,10) as hits,wide
  from real

),


sigs as (

  select tmp.getJsonObjectSignature(blob,typeof(blob)).*
  from real -- limit 1

)


--select (hits)[safe_offset(cast((rand() * array_length(hits)-1) as int))].dat.right(1) from proc;
--select (hits).array_last().part from proc;

--select (hits).array_last().leaf.nodes.array_last() from proc -- where array_length(hits) > 0

--select (levels).array_last().leaf.nodes.array_last() from tmp.mapJsonObjects3(table sigs,scan=>true,dups=>true,deep=>10)

select sum((select sum(array_length(leaf.nodes)) from unnest(levels)))from tmp.mapJsonObjects3(table sigs,scan=>true,dups=>true,deep=>10)
--group by sig

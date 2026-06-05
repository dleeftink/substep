-- This version is head-to-head with session(26.05.15)queries(0.3)json(cast)base(shuffle)any.sql
-- a.k.a. Schema-on-Read with OLAP Performance

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
  --'|' r'(?:\b(?:null|true|false|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)\b[\s\,]*)+'
  -- 5. CATCH: Individual structural boundaries with trailing comma
    '|' r'[\}\]\,]\s*\,?'
    '|' r'[\[\{]'
    '|' r'[\"\:]' -- dangling
  -- 6. 
    ')'
  
);

create or replace table function tmp.mapJsonFragmentTypes2(input table<part string, off int> /* parts array<string>*/) as ( 
  from input -- unnest(parts) part with offset off 
  |> extend LENGTH(part) as len
  |> extend if((part).starts_with('\x1e'),1,0) terminator
  |> extend (SUM(len) OVER (ORDER BY off ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + /*1*/ 0 ).ifnull(0) + 0 - terminator idx,lag(part) over(order by off) as prev,
  --|> extend if(part in ('"',':'),Error('Dangling [' ||part|| '] at string index: ' ||idx),(part).trim('\t\n\r ').nullif('')) bare 
  |> extend (part).trim('\t\n\r ').nullif('') as bare
  --|> where bare is not null

  |> extend (bare).rtrim('\t\n\r ,') as clip
  |> extend (clip).right(1) as tail
  |> where /*tail is not null and*/ tail not in (':') or part in (':','"')
  
  |> set prev = (prev).rtrim('\t\n\r ').nullif('')
  |> extend 
      (tail) in ('{','}') as obj,
      (tail) in ('[',']') as arr,
      (bare).right(1) in (',') as sep,
      (prev).right(1) in (':') as anc

  |> extend not (obj or arr) as val,
  |> extend (not val).if(tail,null) as sym,case when obj then 'OBJ' when arr then 'ARR' else 'ENT' end cat
  |> extend val and not anc as run, if(val and anc,prev,null) as key,if(val,bare,null) as dat -- bare for reconstruction / clip for direct json construction
  |> extend (run).if(length(clip) - (clip).regexp_replace(r'("(?:[^"\\]|\\.)*")|\,', r'\1').length() + 1,null) as cap

  |> set key = if(not val and (clip).starts_with('"'), (clip).rtrim('{['),key)
  |> set key = if((key).starts_with(""),(key).replace('""','"undefined"'),key)
  |> select idx,cat,sym,key,sep,dat,len,cap

);

create or replace aggregate function tmp.getJsonObjectNodeLists(
  obj STRUCT<slot INT64, open INT64, close INT64, head STRING, type STRING, key STRING, data STRING, tail STRING, entry BOOL>,
  is_leaf BOOL,is_stem BOOL,is_root BOOL
) as (
  struct(
    struct(
      min(if(is_leaf,obj.open,null)) as opens,
      max(if(is_leaf,obj.close,null)) as closes,
      array_agg(if(is_leaf,obj,null) ignore nulls /*order by obj.open*/) as nodes,
      countif(is_leaf) as size
    ) as leaf,
    struct(
      min(if(is_stem,obj.open,null)) as opens,
      max(if(is_stem,obj.close,null)) as closes,
      array_agg(if(is_stem,obj,null) ignore nulls /*order by obj.open*/) as nodes,
      countif(is_stem) as size
    ) as stem,
    struct(
      min(if(is_root,obj.open,null)) as opens,
      max(if(is_root,obj.close,null)) as closes,
      array_agg(if(is_root,obj,null) ignore nulls /*order by obj.open*/) as nodes,
      countif(is_root) as size
    ) as root
  )
);


create or replace function tmp.getJsonObjects4(str string, rgx string,pick int) as (

  array(
    from unnest((str/*||'\x1e'*/).regexp_extract_all(rgx)) as part with offset off
    |> call tmp.mapJsonFragmentTypes2()
    -- from tmp.mapJsonFragmentTypes2((str).regexp_extract_all(rgx))

    |> extend sym in ('{','[') as opener, sym in (']','}') as closer,cat in ('ENT') as entry
    |> extend if(entry,1,0) as lift 

    |> extend sum(case when sym = '{' then 1 when sym = '}' then -1 else 0 end) over(w1) as deep,sum(case when sym = '[' then 1 when sym = ']' then -1 else 0 end) over(w1) as nest
       window w1 as (order by idx rows between unbounded preceding and current row) 


    |> extend lift + deep + nest - 1 as depth
    |> set nest = lift + nest - 1, deep = lift + deep - 1

    |> extend depth - (case when opener then 1 when closer then -1 else 0 end) as pre
    |> extend deep - (case when sym = '{' then 1 when sym = '}' then -1 else 0 end) as pre_deep
    |> extend nest - (case when sym = '[' then 1 when sym = ']' then -1 else 0 end) as pre_nest
    |> where pre < pick 

    |> extend pre > depth as pin
    |> extend pre_nest > nest as pin_nest
    |> extend pre_deep > deep as pin_deep
    |> set depth = if(pin,pre,depth) 
    |> set nest = if(pin_nest,pre_nest,nest) 
    |> set deep = if(pin_deep,pre_deep,deep)
    |> extend row_number() over(partition by depth order by idx) slot 
    |> as obj
    |> order by idx
  
    /*|> aggregate countif(cat in ('OBJ','ENT')) = countif(cat = 'ARR') unbalanced,min_by(obj,pin) head,max_by(obj,pin) tail group by depth , slot - if(closer,1,0) as slot -- if(entry,item,type) 
    |> set slot = row_number() over(partition by depth order by slot)
    
    |> extend max(depth) over() max_depth
    |> extend least(2, max_depth - depth) as max_raise

    |> left join unnest(generate_array(0,(head.entry or depth >= pick).if(0,max_raise))) raise
    |> set depth = depth + raise
    |> select 
        objs,arrs,raise,depth,slot,head.idx as open,tail.idx + if(head.entry,(head.len).ifnull(1) - 1 ,0) + 1 as close,
        head.sym head,head.cat type,head.key,head.dat as data,tail.sym tail,head.entry 
       
    -- |> extend coalesce(substring(str,open,close-open)) as sub -- check if correct index
    -- |> extend range(timestamp_seconds(open),timestamp_seconds(close)) line 
    
    --|> extend struct(slot,open,close,head,type,key,data,tail,entry) as obj -- |> as obj
    --|> extend raise = 2 and type = 'ARR' as is_root,(raise = 1 and not entry) or depth = 0 as is_stem,raise = 0 as is_leaf
    |> aggregate
  
        tmp.getJsonObjectNodeLists(struct(slot,open,close,head,type,key,data,tail,entry),
          is_leaf => (raise = 0),
          is_stem => (raise = 1 and not entry) or depth = 0, -- always include top-level objects so we don't end up with an empty inner join later
          is_root => (raise = 2 and type = 'ARR') -- only grandparent arrays need to be tracked for indexing
        ).*
  
      group by depth
    
    --|> where array_length(leaf.nodes) > 0
    --|> where leaf.nodes[safe_offset(0)] is not null
    -- |> where depth < max(depth) over()
    -- |> set 
    --     leaf = (select leaf.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *),
    --     stem = (select stem.* |> set bins = GREATEST(1, CAST((closes - opens) / pow(size,0.5) AS INT64)) |> select as struct *)

    |> select as struct depth,leaf,depth depth_2,stem,depth depth_3,root --,bin*/
    |> select as struct *

  )

);

create or replace table function tmp.mapJsonObjects4(input table< /*schema string,*/str string,sig int /*,rel int,type string*/>, scan bool, dups bool,deep int) as (
  
  with shuf as (
    
    select sig,(str)/*.to_json_string()*/ str from input 
    qualify if(not scan,true,if(dups,true = max(true) over(),row_number() over(partition by sig) = 1))

  )/*,

  flat as (

    select * except(strs) from (
      select * except(str), json_query_array(str,'$') strs 
      from shuf
    ) get,get.strs str

  )*/

  select str,sig,tmp.getJsonObjects4(str,
    tmp.layJsonPartials(),
    --r'("(?:[^"\\]|\\.)*"\s*:\s*[\[\{]?|"(?:[^"\\]|\\.)*"[\s\,]*|(?:"(?:[^"\\]|\\.)*"[\s\,]*){3,}|\s+|[^\[\]\{\}\"\:]+[\s\,]*|[\}\]\,]\s*\,?|[\[\{])',
    deep) levels from shuf

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


select str,length(str) len,array(
  select as struct deep,nest,
      row_number() over(partition by depth order by idx) slot,
      
      struct(idx,cat,sym,key,dat) obj,cat,pin,depth,opener,closer,entry,sym,
      case when cat = 'ARR' then nest when cat = 'OBJ' then deep when cat = 'ENT' then  DIV((depth + slot) * (depth + slot + 1), 2) + slot end as dim  -- Cantor's Pairing Function for ent's
  from unnest(levels) order by idx
  |> aggregate max(depth) depth,min_by(if(opener or entry,obj,null),pin) head,max_by(if(closer,obj,null),pin) tail group by cat,dim
  |> select as struct * except(cat,dim) 
  ) from tmp.mapJsonObjects4(table sigs,scan=>true,dups=>true,deep=>10)

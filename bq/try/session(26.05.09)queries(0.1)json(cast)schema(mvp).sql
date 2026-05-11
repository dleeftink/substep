CREATE OR REPLACE FUNCTION tmp.fixJsonSafeGuards5(str STRING, chars string, codes array<int>) AS (
  TRANSLATE(str, 
    chars, -- '{}[]:,<>()#', 
    CODE_POINTS_TO_STRING(codes)--CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B])
  )
) OPTIONS (
  description = "Escapes JSON delimiters using control characters or backslashes to prevent parsing collisions."
 );

CREATE OR REPLACE FUNCTION tmp.layJsonSafeGuards5(str STRING, chars string, codes array<int>) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING(codes), --CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B,0x05]),
    chars -- '{}[]:,<>()#"'
)) OPTIONS (
  description = "Restores control-character markers back to their literal characters."
);

CREATE OR REPLACE FUNCTION tmp.mapStringSafeGuards5(str STRING, chars string, codes array<int>) AS ((

  -- 1. Replace escaped quotes with a unique marker (\x05) so they don't break the SPLIT
  -- 2. Split on the structural double quote (")
  -- 3. Content between quotes will always be at ODD offsets (1, 3, 5...)
  
  WITH chunks AS (
    SELECT 
      (part).ltrim('\x0F') part, off,
      (part).starts_with('\x0F') AS is_content
    FROM UNNEST(
      SPLIT((str).regexp_replace(r'([\'][^\']*[\']|["][^"]*["])',concat('\x0E\x0F',r'\1','\x0E')), '\x0E')
    ) AS part WITH OFFSET off
  )
  
  -- 4. Re-assemble. If it's content, wrap it back in quotes and apply safeguards
  select if(chars is null,str,array_to_string(
    array(SELECT 
      IF(is_content, 
        tmp.fixJsonSafeGuards5(part,chars,codes),
      part),  
    FROM chunks)  
  ,''))

)) OPTIONS (
  description = "Sanitizes quoted fields by escaping reserved delimiters."
);

create or replace function tmp.getCharacterIndices5(str string,rgx string) as (array(
  with init as (
    select regexp_instr(str, rgx, 1, off + 1) AS idx, sub
    from unnest(regexp_extract_all(str, rgx)) AS sub WITH OFFSET AS off
  )

  select as struct idx,(
    case
    when (sub).ends_with('<') then struct('<' as mark,(sub).rtrim('<').regexp_replace(r'^(.*)#','') as type,(sub).regexp_replace(r'[^\s][A-Z<]+$','').nullif('') as item)
    when (sub).ends_with('>') then struct('>' as mark,null as type,null as item)
    else struct(cast(null as string) as mark, regexp_extract(sub,r'#(.*)$') as type,regexp_extract(sub,r'^(.*)#').ifnull(sub) as item)
    end
  ).* from init
));

-- Generate signatures strategy F (direct array of structs access):
-- requires two different function calls depending on source type (struct or array)

create or replace function tmp.getJsonSigFromStruct(blob any type,schema string) as ((
  select as struct schema,[(blob).to_json()] parts,farm_fingerprint(str) sig,length(str) rel,'object' type 
  from (select safe.format('%t',blob) str)
));

create or replace function tmp.getJsonSigFromArray(blob any type,schema string,tail int,scan int) as ((
  select as struct schema,array((
    select (b).to_json() from (select b,i from unnest(blob) b with offset i) 
    where if(tail is null,true,i > len - 2 - tail ))
  ) as parts, farm_fingerprint(str) sig,length(str) rel,'array' type 
  from (
    select if(a=b,a,a||b) str,array_length(blob) len from (
      select
        if(scan=0, safe.format('%t',blob[0]),
        array_to_string(array(select safe.format('%t',blob[safe_offset(idx)]).ifnull('') from unnest(index) idx),'')) 
        as a,
        
        if(scan=0, safe.format('%t',array_last(blob)),
        array_to_string(array(select safe.format('%t',blob[safe_offset(array_length(blob)-1-idx)]).ifnull('') from unnest(index) idx),''))
        as b
      from (select generate_array(0,scan) index)
    )
  )
));

create or replace function tmp.getSchemaObjects5 (src any type) as (array(
  from unnest(src)
  |> extend sum(case when mark = '<' then 1 when mark = '>' then -1 else 0 end) over(w1) - 1 as depth
     window w1 as (order by idx rows between unbounded preceding and current row)
  |> extend depth - (case when mark = '<' then 1 when mark = '>' then -1 else 0 end) as pre
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
      head.raise,b as depth,slot,head.idx as open,tail.idx + if(head.mark is null,length(head.type)+length(head.item)+1,0) as close,
      head.mark head,head.type,head.item,tail.mark tail,--null as part
  --|> set item = coalesce(item,substring(keystr,open,close-open).left(16).concat('...'))
  |> where raise
  
  |> select as struct *,
  |> order by depth,open
   
));

create or replace table function tmp.useJsonSchemaSampler4(input table<schema string>,chars string,codes array<int>,regex string) as (
from input 
  |> select (schema).(tmp.mapStringSafeGuards5)(chars,codes) str
  |> select (str).replace(' ','#').(tmp.getCharacterIndices5)(regex) index

  |> select tmp.getSchemaObjects5(index) as dat 
  -- |> select array_last(dat) d
    
);

create or replace table function tmp.getJsonPathsThru4(input table<sig int64,off int64,jsn json>,constants any type) as (

  with init as ( -- deduplicate
    select sig,off,max_by(jsn,off) jsn from input 
    group by sig,off
  )

  -- A: closure pattern + force an early dependency
  select sig,array_agg((jsn).to_json_string().length() order by off) parts,constants,count(*) mag,count(distinct off) deg 
  from init group by sig -- order by dup desc


  -- B: broadcast pattern
  --select * except(c), c as constants from (
  -- select sig,array_agg((jsn).to_json_string().length() order by off) parts,constants,count(*) mag,count(distinct off) deg 
  -- from init group by sig
  --) cross join unnest([constants]) c

);

create or replace table function tmp.getJsonPaths4(input table<src struct<schema string,parts array<json>,sig int,rel int,type string>>) as (

  with init as (
     
    select src.sig /*^ (i+1)*/ sig,off,jsn from input get,get.src.parts jsn with offset off

  ),
  
  exit as (
    select * from tmp.getJsonPathsThru4(table init,
      constants => (from input |> limit 1 |> select src.schema 
        |> call tmp.useJsonSchemaSampler4(
          '{}[]:,<>()# ',[0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B,0x00],r'((?:[<>]?)(?:ARRAY|STRUCT)(?:[<>]?)|[<>]|(?:[^#,]+#[A-Z0-9]+[<]?))'
        )
      )
    )
  )

  select * from exit

);

with real as (
 
  select tmp.getJsonSigFromArray(blob,typeof(blob),tail=>1,scan=>0) src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` limit 15
    ) --get,get.hits hit
  )
)

select * from tmp.getJsonPaths4(table real)
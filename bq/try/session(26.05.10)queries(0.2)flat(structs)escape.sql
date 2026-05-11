/*CREATE OR REPLACE FUNCTION tmp.fixJsonSafeGuards5(str STRING, chars string, codes array<int>) AS (
  TRANSLATE(str, 
    chars, -- '{}[]:,<>()#', 
    CODE_POINTS_TO_STRING(codes)
    --CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B])
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
);*/

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

create temp function getCharacterIndices(str string,rgx string) as (array(
  with init as (
    select regexp_instr(str, rgx, 1, off + 1) AS idx, sub
    from unnest(regexp_extract_all(str, rgx)) AS sub WITH OFFSET AS off
  )

  select as struct idx,(
    case
    when (sub).ends_with('<') then struct('<' as mark,(sub).rtrim('<').regexp_replace(r'^(.*)#','') as type,(sub).regexp_replace(r'[^\s][A-Z<]+$','').nullif('') as item)
    when (sub).ends_with('>') then struct('>' as mark,null as type,null as item)
    else struct(cast(null as string) as mark, regexp_extract(sub,r'#(.*)$') as type,regexp_extract(sub,r'^(.*)#').ifnull(sub) as item)
    --(select struct(cast(null as string) as mark,s[safe_offset(1)] as type,sub as item) from (select (sub).split('#') s)) -- be careful: keys may contain spaces
    end
  ).* from init
));

with test as (

  select typeof(blob) type,blob,sel from unnest([struct([
    struct(1 as `id asdasd`, [struct("a's" as sub,2 as val,[struct(1 as x,2 as y),(1,2),(9,0)] as nest),("b",5, [(2,3)])] /* as arr */,1 as uid,'x" a' as sub), 
    (2, [("c,a",4,[(3,4)]),("d",5,[(5,6)])],2,'y STRUCT<>')
    ] as blob,1 as sel),
    struct([
    (3, [("c",4,[(3,4)]),("d",5,[(5,6)])],2,'x'),
    (4, [("c",4,[(3,4)]),("d",5,[(5,6)])],2,'y')
    ],0 as sel)
  ])
),

-- processing gets prohibitively expensive for real data

real as (
 
  select typeof(blob) type,blob,null as sel from (
    select
      hit as blob
    from (
      select * from `stack-curves.tables.hits`  -- limit 15
    ) get,get.hits hit -- limit 1
  )
),

prep as (

  -- interesting: causes query plan unrolloing
  -- select sel,(type).replace('`','"').(map.jsonSafeGuards)() key,format('%T',blob).(map.jsonSafeGuards)().replace('[','ARRAY<').replace('(','STRUCT<').translate('])','>>') val from test
  
  select sel, strs[0].str as key, strs[1].str.replace('[','ARRAY<').replace('(','STRUCT<').translate('])','>>')  as val from (
    select sel, array(select as struct STR SRC,(str).(tmp.mapStringSafeGuards5)(chars,codes) str,chars,codes
      from unnest([
        struct((type).replace('`','"') as str,'{}[]:,<>()# ' as chars,[0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B,0x00] as codes), -- remember: 0x05 is reserved for double quote
        struct(safe.format('%T',blob) as str,'<>#' as chars,[0x01, 0x04, 0x1B] as codes)]) -- can be quite sparse with encoding here. as we extract double quotes anyways
    ) strs from test
  )

),

char as (
  
  select sel,
    key keystr,(key).replace(' ','#').getCharacterIndices(r'((?:[<>]?)(?:ARRAY|STRUCT)(?:[<>]?)|[<>]|(?:[^#,]+#[A-Z0-9]+[<]?))') as key, -- encode remaining structural spaces as '#'
    val valstr,(val).getCharacterIndices(r'((?:[<>]?)(?:ARRAY|STRUCT)(?:[<>]?)|[<>]|"(?:[^"]*?)"|\'(?:[^\']*?)\'|(?:[^ ,<>]+))') val,
  from prep

),

nest as (

  select array(
    from unnest(key)
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

  ) key from char

)

--select array(select as struct *,countif(mark = '<') over(),countif(mark = '>') over() from unnest(key) where mark in ('<','>')) from char

select array_last(key) from char
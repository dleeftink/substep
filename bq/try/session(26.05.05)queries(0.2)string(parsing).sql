create temp function jsonTuples(jsn STRING) as (
  (jsn).regexp_replace(r'""\:"?([^\{\}\[\]]*?)"?\,""\:([^\{\}\[\]]*?)',r'"\1":\2')  -- move quoted keys/values into empty key position and mark insertion point
     .replace('"":','"undefined":')
);

create temp function enumKeys(jsn STRING, uid STRING) AS ((
  select array_to_string(
    array(

      -- maybe encode as json..
      select if(right(part,1)!= '#', part /*|| '?node=' || generate_uuid().left(8)*/ 
      || '?' || uid || '&idx=' || i || '&open=' || sum(length(part)) over(order by i) || '&' || uid || '":',(part).rtrim('#')) part
      FROM UNNEST(SPLIT(jsn||'#', '":')) AS part WITH OFFSET i
      
    ), ''
  )
));

create temp function jsonStringMask(object ANY TYPE) as (
  (object).(get.jsonStringFromStruct)().(map.jsonSafeGuards)(true).(jsonTuples)() -- .(enumKeys)().(layJsonSafeGuards)()
);

CREATE temp FUNCTION layJsonSafeGuards(str STRING) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B]),
    '{}[]:,<>()#'
).replace(code_points_to_string([0x05]),r'\"')
);

create temp function parsed(object any type,maxDepth int) as ((

  with init as (
    select *,(str).parse_json() jsn from (
      select src,(src).enumKeys(uid).(layJsonSafeGuards)() str,uid from (  
        select (object).(jsonStringMask)() src, 'uid=v'||generate_uuid().left(6) uid
      )
    )
  ),

  prep as (
    
    select *,(jsn).json_keys(maxDepth,mode=>"lax recursive") paths ,length(uid)+2 uid_len
    from init
    
  ),

  frag as (

    select *,array(
      select pid, (path).LEFT(LENGTH(path) - (uid_len-1)).split('&'||uid) path
      from unnest(paths) path with offset pid 
      --|> cross join unnest(path) p with offset depth
      --|> select pid,depth,(p).split('?'||uid) dat 
      --|> extend dat[safe_offset(0)].ltrim('."').ltrim('".') as key,dat[safe_offset(1)].ltrim('&').split('&') as meta
      --|> select as struct pid,depth,key,cast(meta[safe_offset(0)].split('=')[safe_offset(1)] as int) as idx,cast(meta[safe_offset(1)].split('=')[safe_offset(1)] as int) as loc
      --|> order by pid,depth,idx,loc
      |> set path = array(
          select depth,(p).split('?'||uid) dat from unnest(path) p with offset depth
          |> extend dat[safe_offset(0)].ltrim('."').ltrim('".') as key,dat[safe_offset(1)].ltrim('&').split('&') as meta
          |> select as struct pid,depth,key,cast(meta[0].split('=')[1] as int) as idx,cast(meta[1].split('=')[1] as int) as open
          |> order by pid,depth,idx,open
        )
      |> select as struct *
    ) fragment
    from prep

  )

  select as struct src,fragment from frag
));


with opts as (

  select (
      'trip', 'a string", okay',
      1,2.0,3,4,
      'span', 0.0, 
      'text', "('oi',1)), ",
      'comma', "a, b, c",
      'tuple', (1, "inner"),--[1,2,3]),
      'novalue',"yesvalue", "maybevalue", -- parsing imbalance between tups an flat -> fact of life
      'nested', STRUCT('v1' AS version, 2024 AS year),
      'geo',ST_GEOGFROMTEXT('LINESTRING(0 0, 1 1, 2 1, 2 2)'),
      'empty', CAST(NULL AS STRING),
      'kern', [1.0, 1, 2],
      (0,(0,(0))),[1,2,3],
      'top','val'
    ) as blob

),

opts2 as (

  select (
       "test3.hello", " {'a': [2]} ",
      1,2.0,3,--4,
      --"1",--"2","3","4",
      ('span.test', (1,(1,(1,(1,(1)))))),
      ('kern',(1,'inner',3,"binner"),struct([1.0, 1, 2] /*as ok*/,struct(0 as test,struct([1,2,3] as ntmp,parse_json('[1,2,[2,3]]')) as b) /*as tmp*/, null as oi,('text', "('zi',1)"),struct(1 as v) as io,(struct("a" as b),struct(1 as c)))),
      ('text',  (struct("a" as b),struct(1 as c))),        -- Nested lookalike
      ('comma', "a, b, c"),         -- Internal comma
      ('tuple', (1,'inner'), 'novalue','yesvalue'),      -- Valid tuple but odd key
      (0,(0,(0))),
       'novalue',"yesvalue", "maybevalue",--'okay',     -- No value or odd pattern (uncomment)
      ('nested',STRUCT('v1' AS version, 2024 AS year),'nested',STRUCT('v1' AS version, 2024 AS year))
      ,0
    ) as blob
),

opts3 as (

  select [
    
    -- [0]
    struct(1 as id, 
      [ -- [0]
        struct("a" as sub,2 as val,[
          -- [0]
          struct(1 as x,2 as y),
          (1,2)
        ] as nest), 
        -- [1]
        ("b",5, [
          -- [0]
          (2,3)
        ])
      ],
    1 as uid), 
    
    -- [1]
    struct(2, 
      [ -- [0]
        ("c",4,[
          -- [0]
          (3,4)
        ]), 
        -- [1]
        ("d",5,[
          -- [0]
          (5,6)
        ])
      ],
    2)

  ] as blob

),

real as (
  select
    --get.jsonStringMask(hits[safe_offset(0)]) jsn 
    --use.parser(hits.product[safe_offset(0)],10) dat
    hits.product[safe_offset(0)] blob
  from (
    select * from `stack-curves.tables.hits` -- limit 128
  ) get, get.hits
)


--select parsed(blob,5) jsn from real  -- where blob.productSKU = 'GGOEGAAX0098'
select parsed(blob,10) jsn from opts3
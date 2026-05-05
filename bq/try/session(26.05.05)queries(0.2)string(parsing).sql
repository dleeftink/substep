create temp function jsonTuples(jsn STRING) as (
  (jsn).regexp_replace(r'""\:"?([^\{\}\[\]]*?)"?\,""\:([^\{\}\[\]]*?)',r'"\1":\2')  -- move quoted keys/values into empty key position and mark insertion point
);

create temp function enumMissing(jsn STRING) AS ((
  select array_to_string(
    array(
      select if(i > 0, '"undefined_' || i || '":' || part, part)
      FROM UNNEST(SPLIT(jsn, '"":')) AS part WITH OFFSET i
      order by i
    ), ''
  )
));

create temp function jsonStringMask(object ANY TYPE) as (
  (object).(get.jsonStringFromStruct)().(map.jsonSafeGuards)(true).(jsonTuples)().(enumMissing)().(layJsonSafeGuards)()
);

CREATE temp FUNCTION layJsonSafeGuards(str STRING) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B]),
    '{}[]:,<>()#'
).replace(code_points_to_string([0x05]),r'\"')
);

create temp function parsed(object any type,maxDepth int) as ((

  select (object).(jsonStringMask)().(parse_json)().json_keys(maxDepth,mode=>"lax recursive")

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
       "test3", " {'a': [2]} ",
      1,2.0,3,--4,
      --"1",--"2","3","4",
      ('span', (1,(1,(1,(1,(1)))))),
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

real as (
  select
    --get.jsonStringMask(hits[safe_offset(0)]) jsn 
    --use.parser(hits.product[safe_offset(0)],10) dat
    hits.product[safe_offset(0)] blob
  from (
    select * from `stack-curves.tables.hits` limit 512
  ) get, get.hits
)


select parsed(blob,1) jsn from real  -- where blob.productSKU = 'GGOEGAAX0098'
--select parsed(blob) jsn from opts2 
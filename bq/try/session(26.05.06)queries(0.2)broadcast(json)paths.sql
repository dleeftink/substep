create or replace function tmp.jsonTuples1(jsn STRING) as (
  (jsn).regexp_replace(r'""\:"?([^\{\}\[\]]*?)"?\,""\:([^\{\}\[\]]*?)',r'"\1":\2')  -- move quoted keys/values into empty key position and mark insertion point
     .replace('"":','"undefined":')
);

create or replace function tmp.enumKeys1(jsn STRING, uid STRING) AS ((
  select array_to_string(
    array(

      -- maybe encode query string as json INSIDE the key..
      select if(right(part,1)= ':', (part).rtrim('":')
      || '?' || uid || '&idx=' || i 
      || '&' || uid || '":',(part)) part
      FROM UNNEST(SPLIT((jsn).replace('":','":>>').replace(',',',>>'), '>>')) AS part WITH OFFSET i
      
    ),''
  )
)); 

create or replace function tmp.jsonStringMask1(object ANY TYPE) as (
  (object).(get.jsonStringFromStruct)().(map.jsonSafeGuards)(true).(tmp.jsonTuples1)() -- .(enumKeys)().(layJsonSafeGuards)()
);

CREATE or replace FUNCTION tmp.layJsonSafeGuards1(str STRING) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B]),
    '{}[]:,<>()#'
).replace(code_points_to_string([0x05]),r'\"')
);

CREATE or replace FUNCTION tmp.getJsonPathsData1(str string,maxDepth int) AS ((
  with init as (
    select (str).parse_json() schema
  )
  select as struct schema,(schema).json_keys(maxDepth,mode=>"lax recursive") paths 
  from init
  
));

CREATE or replace AGGREGATE FUNCTION tmp.getJsonPathSchema1(src string,uid string,maxDepth int) AS (
  any_value(src).(tmp.enumKeys1)(any_value(uid)).(tmp.layJsonSafeGuards1)().(tmp.getJsonPathsData1)(any_value(maxDepth)) --as jsn
);

create or replace table function tmp.getJsonPathsThru1(input table<src string>,constants any type) as (

  select src,array_length(jsn.paths) jsn from input 
  cross join (select null |> aggregate any_value(constants) as jsn) 

);

create or replace table function tmp.getJsonPaths1(input table<src string/*,msk string*/>,uid string,maxDepth int) as (

  with exit as (
    select * from tmp.getJsonPathsThru1(table input, 
      constants => 
      (from input |> aggregate tmp.getJsonPathSchema1(/*msk*/ src,uid,maxDepth) ) -- UDAF aggregator
    )
  )

  select * from exit

);

with real as (
  select (blob).(tmp.jsonStringMask1)() as src/*,any_value(blob) over().(tmp.jsonStringMask1)() as msk*/ from (
    select
      hits[safe_offset(0)] as blob
    from (
      select * from `stack-curves.tables.hits` limit 32
    ) get--, get.hits
  )
)

select * from tmp.getJsonPaths1(table real,('sid=v'||generate_uuid().left(3)),9) -- second argument = unused uid/ns mechanism

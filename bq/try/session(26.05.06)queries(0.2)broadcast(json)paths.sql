create or replace function tmp.jsonTuples1(jsn STRING) as (
  (jsn).regexp_replace(r'""\:"?([^\{\}\[\]]*?)"?\,""\:([^\{\}\[\]]*?)',r'"\1":\2')  -- move quoted keys/values into empty key position and mark insertion point
     .replace('"":','"undefined":')
);

CREATE OR REPLACE FUNCTION tmp.mapJsonSafeGuards1(jsn STRING, esc BOOL) AS ((

  -- 1. Replace escaped quotes with a unique marker (\x05) so they don't break the SPLIT
  -- 2. Split on the structural double quote (")
  -- 3. Content between quotes will always be at ODD offsets (1, 3, 5...)
  
  WITH chunks AS (
    SELECT 
      part, 
      off,
      MOD(off, 2) = 1 AS is_content
    FROM UNNEST(
      SPLIT(REPLACE(jsn, '\\"', '\x05'), '"')
    ) AS part WITH OFFSET off
  )
  
  -- 4. Re-assemble. If it's content, wrap it back in quotes and apply safeguards
  select array_to_string(
    array(SELECT 
      IF(is_content, 
        CONCAT('"', fix.jsonSafeGuards(part, esc), '"'), 
      part),  
    FROM chunks)  
  ,'')

)) OPTIONS (
  description = "Sanitizes quoted JSON fields by escaping reserved delimiters."
);

-- enumerate keys so repeated/unnamed keys will also be extracted
create or replace function tmp.enumKeys1(jsn STRING, uid STRING) AS ((
  select array_to_string(
    array(

      -- investigate: encode query string as JSON INSIDE the key..
      select if(right(part,1)= ':', (part).rtrim('":')
      || '?' || uid || '&idx=' || i 
      || '&' || uid || '":',(part)) part
      FROM UNNEST(SPLIT((jsn).replace('":','":>>')/*.replace(',',',>>')*/, '>>')) AS part WITH OFFSET i
      
    ),''
  )
)); 

create or replace function tmp.getJsonStringFromStruct(object ANY TYPE) as ((

  with list as (
  
    select (sql).split(',') sql,(jsn).split(',') jsn from (
      select format("%T",object) sql,(object).to_json_string() jsn 
    ) -- coalesce(safe_divide(((jsn).split('},"":').array_length()-1),((jsn).split('","":').array_length()-1)),0), -- optional initial well-formedness check
  
  ),

  fuse as (

    -- resolve JSON floating conversion from source SQL string
    -- assumes balanced commas
    
    select if(array_length(sql) = array_length(jsn),

      array_to_string(array(
        select IF((jsonpart).translate('0123456789','0').contains_substr("0"),
          (jsonpart).REGEXP_REPLACE(r'^([^0-9]*)[0-9\.\s-]+([\]\}]*)$',
             (r'\1').CONCAT((sql[idx]).ltrim().REGEXP_REPLACE(r'[^0-9\.\s-]', ''), r'\2')
        ),jsonpart) as res from unnest(jsn) jsonpart with offset idx
        order by idx
      ),',')

    , error("Imbalanced SQL / JSON part arrays")) jsn from list
  
  )

  select jsn from fuse

)) OPTIONS (
  description = "Serializes a SQL struct to JSON while preserving literal source values."
);

-- convert any SQL object to escaped json string, fix json tuples for some SQL > JSON conversion

create or replace function tmp.jsonStringMask1(object ANY TYPE) as (
  (object).(tmp.getJsonStringFromStruct)().(tmp.mapJsonSafeGuards1)(true).(tmp.jsonTuples1)()
);

-- drop safeguards before calling parse_json()

CREATE or replace FUNCTION tmp.layJsonSafeGuards1(str STRING) AS (
  TRANSLATE(str, 
    CODE_POINTS_TO_STRING([0x1C, 0x1D, 0x02, 0x03, 0x1E, 0x1F, 0x01, 0x04, 0x11, 0x13, 0x1B]),
    '{}[]:,<>()#'
).replace(code_points_to_string([0x05]),r'\"')
);

CREATE or replace FUNCTION tmp.getJsonPathsData1(str string,maxDepth int) AS ((
  with init as (
    select (str).parse_json() parsed
  ),

  path as (
    select parsed,(parsed).json_keys(maxDepth,mode=>"lax recursive") paths 
    from init
  
  ),

  flat as (

    select parsed,array(
      select as struct *,count(*) over() len from (
        select distinct (p).regexp_replace(r'\?sid=v.*?\&sid=v...','') from unnest(paths) p
      )
    ) paths from path

  )

  select as struct * from path
 
));

CREATE or replace AGGREGATE FUNCTION tmp.getJsonPathSchema1(src string,uid string,maxDepth int) AS (
  any_value(src).(tmp.enumKeys1)(any_value(uid)).(tmp.layJsonSafeGuards1)().(tmp.getJsonPathsData1)(any_value(maxDepth)) --as jsn
);

CREATE or replace FUNCTION tmp.getJsonPathSchema2(src string,uid string,maxDepth int) AS (
  (src).(tmp.enumKeys1)(uid).(tmp.layJsonSafeGuards1)().(tmp.getJsonPathsData1)(maxDepth)
);

create or replace table function tmp.getJsonPathsThru1(input table<src string>,constants any type) as (

  select src,jsn from input 
  cross join (select null |> aggregate any_value(constants) as jsn) 

  -- select src,constants jsn from input 

);

create or replace table function tmp.getJsonPaths1(input table<src string>,maxDepth int) as (

  with exit as (
    select * from tmp.getJsonPathsThru1(table input, 
      constants => (from input |> limit 128

        --|> extend farm_fingerprint(src) as sig
        --|> where sig >> 62 = 1
        --|> limit 32

        -- -- sampling strategy A:
        -- |> order by length(src) desc
        -- |> limit 1
  
        -- sampling strategy B (won't always get the highest entropy schema -> you need to split by structural commas instead):
        
        |> aggregate max_by(src,length(src)) src
        |> extend farm_fingerprint(src) as sig
        
        -- pass result to schema extrctor
        |> extend ('sid=v'||cast(sig as string).left(3)) as uid
        |> select tmp.getJsonPathSchema2(src,uid,maxDepth)
        
        -- |> aggregate tmp.getJsonPathSchema1(src=>src, uid=>('sid=v'||generate_uuid().left(3)),maxDepth=>maxDepth) -- UDAF aggregator
      ) 
    )
  )

  select * from exit

);

with real as (
  select (blob).(tmp.jsonStringMask1)() as src/*,any_value(blob) over().(tmp.jsonStringMask1)() as msk*/ from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` -- limit 256
    ) get, get.hits
  )
)

select array_length(jsn.paths) from tmp.getJsonPaths1(table real,8)
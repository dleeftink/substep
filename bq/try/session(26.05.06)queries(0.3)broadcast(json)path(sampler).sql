-- proposed architecture:
-- schema sampler: uses internal broadcast, small set of rows 
-- value extractor: receives N schemas and extracts values per row/matching schema
-- > optionally matches schema based on signature, otherwise falls back to most common schema

CREATE or replace AGGREGATE FUNCTION tmp.getJsonPathSignature1(i int, part string) AS (struct(

  --array_agg(if(part in ('[',']','{','}','[]','[{','}]'),struct(part,i),null)ignore nulls) parts,
  bit_xor(if(part in ('[',']','{','}','[]','[{','}]'),farm_fingerprint(part||i),0)) as sig,
  array_agg(if(right(part,1)=':',struct(part,i),null)ignore nulls) as parts,
  --bit_xor(if(right(part,1)=':',farm_fingerprint(part||i),0)) sig,
  count(distinct if(right(part,1)=':',part,null)) as keys,
  countif(right(part,1)=':') as size
  
));

CREATE or replace function tmp.getJsonPathIndex1(src string) as ((
  (split((src).replace('":','":>>').replace(',',',>>').regexp_replace(r'([\[\]\{\}]+)',r'\1>>'), '>>'))  
));


CREATE or replace FUNCTION tmp.getJsonPathsData2(str string,maxDepth int) AS ((
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
        select distinct (p).regexp_replace(r'\?sid=v.*?\&sid=v.+?$','') path from unnest(paths) p
      )
    ) paths from path

  )

  select as struct * from flat
 
));

create or replace table function tmp.getJsonPaths1(input table<src string>,maxDepth int) as (

  with exit as (
    select * from tmp.getJsonPathsThru1(table input, 
      constants => (from input |> limit 64
      |> extend (from unnest(tmp.getJsonPathIndex1(src)) part with offset i
        |> aggregate tmp.getJsonPathSignature1(i,part)
      ).*
      |> aggregate count(*) deg,max_by(struct(src,keys,size,parts),sig).* group by sig 
      |> aggregate max_by((select as struct src,(src).(tmp.enumKeys1)('sid=v2').(tmp.layJsonSafeGuards1)().(tmp.getJsonPathsData2)(10).*),deg)
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
      select * from `stack-curves.tables.hits` limit 512
    ) get, get.hits
  )
)

select jsn from tmp.getJsonPaths1(table real,8) limit 16
-- Generate signatures strategy F (direct array of structs access):
-- requires two different function calls depending on source type (struct or array)

create or replace function tmp.getJsonSigFromStruct(blob any type) as (
 (select as struct [(blob).to_json()] parts,farm_fingerprint(str) sig,length(str) rel,'object' type from (select safe.format('%t',blob) str))
);

create or replace function tmp.getJsonSigFromArray(blob any type,tail int,scan int) as ((
  select as struct array((
    select (b).to_json() from (select b,i from unnest(blob) b with offset i) where if(tail is null,true,i > len - 2 - tail )
    )) parts, farm_fingerprint(str) sig,length(str) rel,'array' type from (
      select if(scan=0,
        safe.format('%t',blob[0])||safe.format('%t',array_last(blob)),

        (select if(a=b,a,a||b) sttr from (
        select
          array_to_string(array(select safe.format('%t',blob[safe_offset(idx)]).ifnull('') from unnest(indx) idx),'') a ,
          array_to_string(array(select safe.format('%t',blob[safe_offset(array_length(blob)-1-idx)]).ifnull('') from unnest(indx) idx),'')  b
          from (select generate_array(0,scan) indx)
        ))
    ) as str,array_length(blob) len
  )

));

/*create or replace function tmp.getJsonSigFromArray(blob any type,tail int,scan int) as ((
  select as struct array((
    select (b).to_json() from (select b,i from unnest(blob) b with offset i) where if(tail is null,true,i > len - 2 - tail )
    )) parts, farm_fingerprint(str) sig,length(str) rel,'array' type from (
      select if(scan=0,
        (blob[safe_offset(0)]).to_json_string()||(array_last(blob)).to_json_string(),

        (select if(a=b,a,a||b) sttr from (
        select
          array_to_string(array(select blob[safe_offset(idx)].to_json_string().ifnull('') from unnest(indx) idx),'') a ,
          array_to_string(array(select blob[safe_offset(array_length(blob)-1-idx)].to_json_string().ifnull('') from unnest(indx) idx),'')  b
          from (select generate_array(0,scan) indx)
        ))
    ) as str,array_length(blob) len
  )

));*/

create or replace table function tmp.useJsonSchemaSampler4(input table<sig int,off int,jsn json>) as (
from input 
  |> where abs(mod(sig,100)) < 5
  |> order by sig 
  |> limit 4

  --|> aggregate max_by(off,abs(sig)>61) off group by abs(sig) >> 61 sig
  |> aggregate array_agg(struct(sig,off)) c
  |> select as struct *
);

create or replace table function tmp.getJsonPathsThru4(input table<sig int64,off int64,jsn json>,constants any type) as (

  with init as (
    select sig,off,max_by(jsn,off) jsn from input 
    group by sig,off
  )

  -- A: closure pattern + force an early dependency
  select sig ^ constants.c[0].sig sig,array_agg((jsn).to_json_string().length() order by off) parts,count(*) mag,count(distinct off) deg 
  from init group by sig -- order by dup desc


  -- B: broadcast pattern
  -- select * except(c), c as constants from (
  --   select sig,array_agg((jsn).to_json_string().length() order by off) parts,count(*) mag,count(distinct off) deg 
  --   from init group by sig
  -- ) cross join unnest([constants]) c

);

create or replace table function tmp.getJsonPaths4(input table<src struct<parts array<json>,sig int,rel int,type string>>) as (

  with init as (
     
    select src.sig /*^ (i+1)*/ sig,off,jsn from input get,get.src.parts jsn with offset off

  ),
  
  exit as (
    select * from tmp.getJsonPathsThru4(table init,
      constants => (from init |> call tmp.useJsonSchemaSampler4())
    )
  )

  select * from exit

);

with real as (
 
  select tmp.getJsonSigFromArray(blob,tail=>1,scan=>0) src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`  limit 15
    ) --get,get.hits hit
  )
)

select * from tmp.getJsonPaths4(table real)
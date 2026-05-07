create or replace table function tmp.useJsonSchemaSampler3(input table<jsn json,keys array<string>,sig int>) as (
from input
  --|> select coalesce(jsn[0],jsn) jsn
  |> where abs(sig) >> 62 = 1
  |> extend (select bit_xor(farm_fingerprint((jsn[k]).to_json_string())) from unnest(keys) k) hsh
  |> order by hsh
  |> limit 1
  --|> extend (jsn).json_keys(2,mode=>'lax recursive') as keys 
  --|> extend farm_fingerprint(array_to_string(keys,'')) sig
  --|> aggregate count(*) as deg group by sig
  --|> aggregate array_agg(struct(sig,deg) order by deg desc) dat
  |> select as struct sig,1 as deg
);

create or replace table function tmp.getJsonPathsThru3(input table<jsn json>,constants any type) as (

  select (jsn).to_json_string().length() jsn, constants c from input 
  --cross join unnest([constants]) c

);

create or replace table function tmp.getJsonPaths3(input table<jsn json,keys array<string>,sig int>) as (

  with exit as (
    select * from tmp.getJsonPathsThru3(table input,
      constants => 
       
        (from input |> call tmp.useJsonSchemaSampler3())
        --(from input |> where sig >> 63 = 1 |> limit 64 |> call tmp.useJsonSchemaSampler1()) 
        --(from input |> where sig >> 63 = 1 |> limit 64  |> aggregate array_agg(struct(src)).(tmp.useJsonSchemaSamplerUDF)())
        --(from input |> where mod(abs(src.sig),100) < 5 |> order by src.sig |> limit 64 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src.str))
        --(from input |> where mod(abs(farm_fingerprint(left(src,32))),100) < 10 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src))
    )
  )

  select * from exit

);

create or replace table function tmp.getJsonPathsSort3(input table<jsn json>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig  
    from (
      select jsn,coalesce(jsn[0],jsn).json_keys(1) keys
      from input
    ) -- order by abs(sig)
  )

  from init |> call tmp.getJsonPaths3()

);

with real as (
 
  select (blob).(to_json)() as jsn from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`  -- limit 15
    ) -- get, get.hits hit
  )
  -- |> aggregate any_value(src) src group by farm_fingerprint(src)
)

select c from  tmp.getJsonPathsSort3(table real)

--select (
--  select bit_xor(cast(term as int)*count) from(
--    select bag_of_words(array(select cast(b as string) from unnest(to_code_points(a)) b)) bag from unnest(arr) a) 
--  get,get.bag),count(*) deg from (
--  select (jsn).json_keys(10,mode=>'lax') arr from real
--) group by arr
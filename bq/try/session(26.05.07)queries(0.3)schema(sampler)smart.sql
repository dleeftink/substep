create or replace function tmp.useJsonSignature3 (jsn json,keys array<string>) as ((
  select as struct bit_xor(farm_fingerprint((jsn).to_json_string())) hsh,array_concat_agg(((jsn).json_keys(1))) dat
  from (select coalesce(jsn[0][k],jsn[k]) jsn from unnest(keys) k) where jsn is not null
));

create or replace table function tmp.useJsonSchemaSampler3(input table<jsn json,keys array<string>,sig int>) as (
from input
  |> where abs(sig) >> 62 = 1
  |> extend tmp.useJsonSignature3(jsn,keys).*

  -- A: order and select
  |> order by hsh |> limit 4
  
  -- B: aggregate and pick
  -- |> aggregate min(hsh) hsh
  
  -- C: top-k
  |> aggregate array_agg(struct(hsh,array_length(dat) as len) order by hsh limit 4) hsh
  |> select as struct hsh--,1 as deg

  -- investigate:
  -- |> extend farm_fingerprint(array_to_string(keys,',')) schema_id
  -- |> select * qualify row_number() over(partition by schema_id order by hsh) <= 3
);

create or replace table function tmp.getJsonPathsThru3(input table<jsn json>,constants any type) as (

  -- A: closure pattern
  select (jsn).to_json_string().length() jsn, constants c from input

  -- B: broadcast pattern
  -- select (jsn).to_json_string().length() jsn,c from input
  -- cross join unnest([constants]) c

);

create or replace table function tmp.getJsonPaths3(input table<jsn json,keys array<string>,sig int>) as (

  with exit as (
    select * from tmp.getJsonPathsThru3(table input,
      constants => (from input |> call tmp.useJsonSchemaSampler3())
    )
  )

  select * from exit

);

create or replace table function tmp.getJsonPathsSort3(input table<jsn json>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig --> when hi/lo entropy?
    from (
      select jsn,coalesce(jsn[0],jsn).json_keys(2,mode=>"lax") keys
      from input
    ) order by abs(sig) --> consider ordering here or not
  )

  from init |> call tmp.getJsonPaths3()

);

with real as (
 
  select (blob).(to_json)() as jsn from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`
    )
  )
)

select c from  tmp.getJsonPathsSort3(table real)
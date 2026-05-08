-- Generate signatures strategy B:

create or replace table function tmp.getJsonPathsSort3(input table<jsn json>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,farm_fingerprint(str) hsh,length(str).ifnull(1048576+1) len
    from (
      select jsn,coalesce(jsn).json_keys(2,mode=>"lax") keys, (jsn).to_json_string() str
      from input
    )
  )

  from init 
  |> select * 

);

with real as (
 
  select (blob).to_json() jsn from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` 
    ) 
  )
)

select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSort3(table real) 
 group by sig order by mag desc

-- Generate signatures strategy C (unrolled struct):

create or replace function tmp.getJsonStringData3 (blob any type) as (struct(
  (blob).(to_json)() as jsn,(blob).to_json_string() as str
));

create or replace table function tmp.getJsonPathsSort3(input table<jsn json,str string>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,hsh,len
    from (
      select jsn,(jsn).json_keys(2,mode=>"lax") keys,farm_fingerprint(str) hsh,length(str).ifnull(1048576+1) len
      from input
    )
  )

  from init 
  |> select * 

);

with real as (
 
  select tmp.getJsonStringData3(blob).* from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`
    ) -- get,get.hits hit
  )
)



select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSort3(table real) 
 group by sig order by mag desc

-- Generate signatures strategy D (internal unrolled struct):

create or replace function tmp.getJsonStringData3 (blob any type) as (struct(
  (blob).(to_json)() as jsn,(blob).to_json_string() as str
));

create or replace table function tmp.getJsonPathsSort3(input table<src struct<jsn json,str string>>) as (
  
  with init as (
    select src.* from input
  ), 
  
  prep as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,hsh,len
    from (
      select jsn,(jsn).json_keys(2,mode=>"lax") keys,farm_fingerprint(str) hsh,length(str).ifnull(1048576+1) len
      from init
    )
  )

  from prep 
  |> select * 

);

with real as (
 
  select tmp.getJsonStringData3(blob) src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`
    ) --get,get.hits hit
  )
)



select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSort3(table real) 
 group by sig order by mag desc

-- Generate signatures strategy E (direct struct access):

create or replace function tmp.getJsonStringData3 (blob any type) as (struct(
  (blob).(to_json)() as jsn,(blob).to_json_string() as str
));

create or replace table function tmp.getJsonPathsSort3(input table<src struct<jsn json,str string>>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,hsh,len
    from (
      select src.jsn,(src.jsn).json_keys(2,mode=>"lax") keys,farm_fingerprint(src.str) hsh,length(src.str).ifnull(1048576+1) len
      from input
    )
  )

  from init 
  |> select * 

);

with real as (
 
  select tmp.getJsonStringData3(blob) src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`
    ) --get,get.hits hit
  )
)



select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSort3(table real) 
 group by sig order by mag desc

-- Generate signatures strategy F (unrolled struct in external wrapper):

create or replace function tmp.getJsonStringData3 (blob any type) as (struct(
  (blob).(to_json)() as jsn,(blob).to_json_string() as str
));

create or replace table function tmp.getJsonPathsSort3(input table<jsn json,str string>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,hsh,len
    from (
      select jsn,(jsn).json_keys(2,mode=>"lax") keys,farm_fingerprint(str) hsh,length(str).ifnull(1048576+1) len
      from input
    )
  )

  from init 
  |> select * 

);

create or replace table function tmp.getJsonPathsSortWrapper3(input table<src struct<jsn json,str string>>) as ( 
  
  from input 
  |> select src.* |> call tmp.getJsonPathsSort3()

);

with real as (
 
  select tmp.getJsonStringData3(blob) src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`
    ) -- get,get.hits hit
  )
)



select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSortWrapper3(table real) 
 group by sig order by mag desc
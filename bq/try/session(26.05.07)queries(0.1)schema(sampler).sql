create or replace function tmp.getJsonValuesAt(object json,keys array<string>) as (
  array(select as struct key,object[key] val from unnest(keys) key |> where val is not null)
);

create or replace function tmp.getJsonTopLevelValues(object json, keys array<string>) as ((
  with init as (
    select json_type(object) type
  )
  select as struct case 
    when type = 'array' then 
    array(select as struct '['||i||']' as ord,tmp.getJsonValuesAt(obj,keys) obj from unnest(json_query_array(object,'$')) obj with offset i)
    when type = 'object' then
    array(select as struct '$' as ord,tmp.getJsonValuesAt(object,keys) obj)
  end as vals,type from init
));

CREATE or replace function tmp.getJsonPathIndex1(src string) as ((
  (split((src).replace('":','":>>').replace(',',',>>').regexp_replace(r'([\[\]\{\}]+)',r'\1>>'), '>>'))  
));

create or replace function tmp.enumKeys2(str STRING, uid any type) AS ((
  select if(uid is null,str,array_to_string(
    array(

      -- investigate: encode query string as JSON INSIDE the key..
      select if(right(part,1)= ':', (part).rtrim('":')
      || '#' || uid || '&idx=' || i 
      || '&' || uid || '":',(part)) part
      FROM UNNEST(tmp.getJsonPathIndex1(str)) AS part WITH OFFSET i
      
    ),''
  ))
)); 

create or replace function tmp.getJsonSignature2(object any type,uid any type) as ((
  with init as (
    select 
      uid as ns,
      (object).(to_json_string)().(fix.jsonTuples)().(tmp.enumKeys2)(uid) as str,
      format('%T',object) as sql
  ),
  prep as (
    select *,(str).parse_json() as jsn from init
  ),
  prop as (
    select *,(jsn).json_keys(1,mode=>"lax") key from prep
  ),
  tops as (
    select *,(jsn).(tmp.getJsonTopLevelValues)(key).* from prop
  ),
  sigs as (
    select *,farm_fingerprint(str) sig from tops
  )
  select as struct * from sigs
));

CREATE or replace AGGREGATE FUNCTION tmp.useJsonSchemaSamplerUDAF1(
  src string
) AS (struct(
  bit_xor(farm_fingerprint(src)) 
 ));

create or replace table function tmp.useJsonSchemaSampler1(input table<src string>) as (

  with init as (
    select bit_xor(farm_fingerprint(src)) sig 
    from input
  )

  select as struct * from init

);

create or replace function tmp.useJsonSchemaSamplerUDF(input any type) as ((

  with init as (
    select bit_xor(farm_fingerprint(src)) sig from unnest(input)
  )

  select as struct * from init

));

create or replace table function tmp.getJsonPathsThru2(input table<src struct<ns string,str string,sql string,jsn json,key array<string>,sig int>>,constants any type) as (

  select src.*,c from input 
  cross join unnest([constants]) c  

);

create or replace table function tmp.getJsonPaths2(input table<src struct<ns string,str string,sql string,jsn json,key array<string>,sig int>>) as (

  with exit as (
    select * from tmp.getJsonPathsThru2(table input,
      constants => 
        --(from input |> where sig >> 63 = 1 |> limit 64 |> call tmp.useJsonSchemaSampler1()) 
        --(from input |> where sig >> 63 = 1 |> limit 64  |> aggregate array_agg(struct(src)).(tmp.useJsonSchemaSamplerUDF)())
        (from input |> where mod(abs(src.sig),100) < 5 |> order by src.sig |> limit 64 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src.str))
        --(from input |> where mod(abs(farm_fingerprint(left(src,32))),100) < 10 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src))
    )
  )

  select * from exit

);

with real as (
  select (blob).(tmp.getJsonSignature2)() as src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`  limit 15
    ) get --, get.hits hit
  ) 
  -- |> aggregate any_value(src) src group by farm_fingerprint(src)
)

--select c from tmp.getJsonPaths2(table real) order by sig
select * from real
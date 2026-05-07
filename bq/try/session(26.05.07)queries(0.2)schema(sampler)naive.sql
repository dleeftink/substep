-- naively passes getJsonSignature2 to getJsonPaths2

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

create or replace function tmp.getJsonValuesAt(object json,keys array<string>) as ((
  select as struct array_agg(obj) dat, struct(bit_xor(farm_fingerprint(key)) as key,bit_xor(farm_fingerprint(val)) as val) as sigs from (
    select key,(jsn).to_json_string() val from (
      select key,object[key] jsn from unnest(keys) key
    )
  ) obj where val is not null
  -- select as struct array_concat_agg(  get.unrolled((object[key]).to_json_string(),[('[',']'),('{','}')],10)) obj from unnest(keys) key

));

create or replace function tmp.getJsonTopLevelValues(object json, keys array<string>) as ((
  with init as (
    select json_type(object) type
  )
  select as struct case 
    when type = 'array' then 
    array(select as struct '['||i||']' as loc,tmp.getJsonValuesAt(obj,keys).* from unnest(json_query_array(object,'$')) obj with offset i)
    when type = 'object' then
    array(select as struct '$' as loc,tmp.getJsonValuesAt(object,keys).*)
  end as obj,type from init
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
  )
  select as struct ns,str,obj from tops
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

create or replace table function tmp.getJsonPaths2(input table< src struct<ns string,str string,obj array<struct<loc string,dat array<struct<key string,val string>>,sigs struct<key int,val int>>>>>) as (

  /*with exit as (
    select * from tmp.getJsonPathsThru2(table input,
      constants => 
        --(from input |> where sig >> 63 = 1 |> limit 64 |> call tmp.useJsonSchemaSampler1()) 
        --(from input |> where sig >> 63 = 1 |> limit 64  |> aggregate array_agg(struct(src)).(tmp.useJsonSchemaSamplerUDF)())
        (from input |> where mod(abs(src.sig),100) < 5 |> order by src.sig |> limit 64 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src.str))
        --(from input |> where mod(abs(farm_fingerprint(left(src,32))),100) < 10 |> aggregate tmp.useJsonSchemaSamplerUDAF1(src))
    )
  )*/

  select * from input

);

with real as (
  select (blob).(tmp.getJsonSignature2)(cast(null as string)) as src from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits`  limit 15
    ) get --, get.hits hit
  ) 
  -- |> aggregate any_value(src) src group by farm_fingerprint(src)
)

select * from tmp.getJsonPaths2(table real) -- order by sig
--select src.obj[safe_offset(0)].sigs.val from real


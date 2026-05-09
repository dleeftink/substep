-- Generate signatures strategy G (direct any struct > JSON access):

create or replace function tmp.getJsonSigFromAny1(blob any type,tail int,scan int) as ((
  select if(jsn[0] is not null,
  
    --(select as struct array(select * from unnest(jsns) jsn with offset idx |> where idx < 1 |> select jsn) jsns from (select json_query_array(jsn) jsns)),
    (select as struct array_agg(if(incTail,json 'null',null) ignore nulls) parts,bit_xor(if(incScan,farm_fingerprint(str),null)) sig,sum(if(incTail,length(str),null)) rel,'array' type from (
        select *,tail is null or i > len - 2 - tail incTail, scan is null or i not between scan and len - 1 - scan or (i = 0 or i = len -1) incScan from (
          select i,obj,safe.format('%t',obj) str,array_length(jsns) len, 
          from ( select json_query_array(jsn) jsns) get,get.jsns obj with offset i)
        )
      ),
  
    (select as struct [jsn] parts,farm_fingerprint(str) sig,length(str) rel,'object' type from (select safe.format('%t',blob) str))
  ) jsn
  from (
    select (blob).to_json() jsn
  )
));

/*create or replace table function tmp.getJsonPathsSort3(input table<src struct<jsn json,str string>>) as (
  
  with init as (
    select jsn,keys,farm_fingerprint(array_to_string(keys,'')) sig,hsh,len
    from (
      select src.jsn,coalesce(src.jsn).json_keys(2,mode=>"lax") keys,farm_fingerprint(src.str) hsh,length(src.str).ifnull(1048576+1) len
      from input
    )
  )

  from init 
  |> select * 

);*/

with real as (
 
  select tmp.getJsonSigFromAny1(blob,tail=>0,scan=>0) from (
    select
      hits as blob
    from (
      select * from `stack-curves.tables.hits` -- limit 15
    ) --get,get.hits hit
  )
)

select * from real

--select src.sig,count(*) mag,array_agg(src order by src.rel desc) from real group by sig 
--having mag > 1 order by mag desc

/*select count(*) mag,any_value(array_length(keys)) deg,cast(avg(len) as int64) len, bit_xor(hsh) hsh
  from tmp.getJsonPathsSort3(table real) 
 group by sig order by mag desc*/

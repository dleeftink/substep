-- Generate signatures strategy G (direct any struct > JSON access):

create or replace function tmp.getJsonSigFromAny1(blob any type,tail int,scan int) as ((
  select if(jsn[0] is not null,
  
    -- Array strategy A1 (dynamic signature from separate tail and scan)
    -- (select as struct array_agg(if(incTail,json 'null',null) ignore nulls) parts,bit_xor(if(incScan,farm_fingerprint(str),null)) sig,sum(if(incTail,length(str),null)) rel,'array' type from (
    --    select *,tail is null or i > len - 2 - tail incTail, scan is null or i not between scan and len - 1 - scan or (i = 0 or i = len -1) incScan from (
    --      select i,obj,
    --      safe.format('%t',obj) str,
    --      --(obj).to_json_string() str,
    --      --array_length(jsns) len, 
    --      --from ( select json_query_array(jsn) jsns) get,get.jsns obj with offset i
    --      max(i) over()+1 len
    --      from unnest(json_query_array(jsn)) obj with offset i
    --    )
    --   )
    -- ),

    -- Array Strategy A2 (dynamic signature from tail only)
     (select as struct array_agg(obj) parts,bit_xor(farm_fingerprint(str)) sig,sum(length(str)) rel,'array' type from (
       
          select i,obj,safe.format('%t',obj) str,
          array_length(jsns) len, 
          from ( select json_query_array(jsn) jsns) get,get.jsns obj with offset i
          -- max(i) over()+1 len
          -- from unnest(json_query_array(jsn)) obj with offset i
        ) where tail is null or i > len - 2 - tail -- or i = 0 
        
      ),

    -- Array Strategy B (static signature from first and last element)
    -- (select as struct array(select json 'null' /*obj*/ from unnest(dat)), 
    -- (array_first(dat).sig ^ array_last(dat).sig).nullif(0).ifnull(dat[0].sig) sig,array_first(dat).rel + array_last(dat).rel rel,'array' type from (select array((
    --     select as struct obj,farm_fingerprint(str) sig ,length(str) rel from (
    --       select i,obj,safe.format('%t',obj) str,array_length(jsns) len, 
    --       from ( select json_query_array(jsn) jsns) get,get.jsns obj with offset i
    --   ) where tail is null or i > len - 2 - tail --  where scan is null or i not between scan and len - 1 - scan or (i = 0 /*or i = len -1*/)
    -- )) as dat)),
    
    -- Object strategy
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

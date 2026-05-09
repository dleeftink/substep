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
        --if(take is null,safe.format('%t',blob),safe.format('%t',blob[0])||safe.format('%t',array_last(blob))) str
        safe.format('%t',blob[0])||safe.format('%t',array_last(blob)),

        (select if(a=b,a,a||b) sttr from (
        select
          array_to_string(array(select safe.format('%t',blob[safe_offset(idx)]).ifnull('') from unnest(indx) idx),'') a ,
          array_to_string(array(select safe.format('%t',blob[safe_offset(array_length(blob)-1-idx)]).ifnull('') from unnest(indx) idx),'')  b
          from (select generate_array(0,scan) indx)
        ))
    ) as str,array_length(blob) len
  )

    

    /*(select as struct array_agg((obj).to_json()) parts,bit_xor(farm_fingerprint(str)) sig,sum(length(str)) rel,'array' type from (
      select *, safe.format('%t',obj) str from (
        select obj,idx from unnest(blob) obj with offset idx)) where if(take is null,true,i < (take)),*/
    
   


  -- if(jsn[0] is not null,
  --   (select as struct jsn[0] jsn,farm_fingerprint((jsn[0]).to_json_string()||array_last(json_query_array(jsn)).to_json_string()) sig),
  --   (select as struct jsn,farm_fingerprint((jsn).to_json_string()) sig)
  -- )
  
  --(select as struct (sel).ifnull(jsn) jsn, if(sel is null,'object','array') type from (select jsn[0] sel))
  --struct( (jsn[0]).ifnull(jsn) as jsn, if(jsn[0] is null,'object','array') as type)
  --(select if(src.jsn is not null,src,null) from (select struct(jsn[0] as jsn, 'array' as type) src)).ifnull(struct(jsn,'object'))
  --if(jsn[0] is not null,struct(jsn[0],'array' as type),struct(jsn,'object' as type))
  --from (
  --  select (blob).to_json() jsn
  --)
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
 
  select tmp.getJsonSigFromArray(blob,tail=>0,scan=>0) from (
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


with line as (

  select '[[{{"hello":"true", "world":false}}]' as str

),

sigs as (

  -- select tmp.getJsonObjectSignature(blob,typeof(blob)).*
  -- from real -- limit 1

  select str,farm_fingerprint(str) as sig
  from line

)

select str,length(str) len,array(
  select as struct deep,nest,
      row_number() over(partition by cat,deep order by idx) dth,
      row_number() over(partition by cat,nest order by idx) nth,
      row_number() over(partition by depth order by idx) slot,
      
      struct(idx,cat,sym,key,dat) obj,cat,pin,depth,opener,closer,entry,sym,
      --if(cat = 'OBJ',deep,null) is_obj,if(cat = 'ARR',nest,null) is_arr,if(cat = 'ENT',depth,null) is_ent,if(cat = 'ENT',slot,null) is_slo
  from unnest(levels) order by idx
  |> aggregate 
     min(depth) depth,
     countif(opener or entry) heads,
     countif(closer or entry) tails,
     min_by(if(opener or entry,obj,null),pin) head,
     max_by(if(closer,obj,null),pin) tail,

    --group by cat,if(entry,depth,greatest(deep,nest)) a ,if(entry,slot,least(dth - if(sym = '}',1,0),nth - if(sym = ']',1,0))  ) b  --, 
    /*GROUP BY GROUPING SETS (
      (cat, is_obj),
      (cat, is_arr),
      (cat, is_ent, is_slo)
    )
  |> where not (is_obj is null and is_arr is null and is_ent is null and is_slo is null)*/
  group by cat,case when cat = 'ARR' then nest when cat = 'OBJ' then deep when cat = 'ENT' then depth end as dim1,if(cat = 'ENT',slot,null) dim2
    
  |> select as struct * except(cat,dim1,dim2) --is_obj,is_arr,is_ent,is_slo)
  ) from tmp.mapJsonObjects4(table sigs,scan=>true,dups=>true,deep=>10)

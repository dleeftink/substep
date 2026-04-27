create or replace function cue.jsonObjectInterface(a INT, b INT, jsn STRING, head ANY TYPE, tail ANY TYPE, slot INT, kpos INT) as (
  struct(
    head.raise,b as depth,slot,a as pre,head.idx as open,tail.idx as close,kpos,head.nest,
    get.jsonKeyFragment(jsn,head.idx,kpos) as key,null as arr_sym,null as arr_ctx,null as ord,null as sym, 
    get.jsonObjectFragment(jsn,head.idx,tail.idx) as json, null as acid,null as ocid,null as ecid,false as list --> acid: array container id / ocid: object container id / ecid: element container id
  )
) OPTIONS (
  description = "Defines the internal `get.jsonObjectMetadata()` interface."
);
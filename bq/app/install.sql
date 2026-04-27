# Meta functions (no dependencies)

-- def.meta
CREATE OR REPLACE FUNCTION def.meta() AS (STRUCT(
  "Contracts: Schema defaults and API definitions for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Schema defaults and API definitions for the 'substep' namespace."
);


-- lay.meta
CREATE OR REPLACE FUNCTION lay.meta() AS (STRUCT(
  "Layers: Formatters and layouters for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Formatters and layouters for the 'substep' namespace."
);


-- fix.meta
CREATE OR REPLACE FUNCTION fix.meta() AS (STRUCT(
  "Fixers: Patchers an correctors for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Patchers an correctors for the 'substep' namespace."
);


-- cue.meta
CREATE OR REPLACE FUNCTION cue.meta() AS (STRUCT(
  "Validation: Type checkers and initialisers for the 'subtype' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Type checkers and initialisers for the 'subtype' namespace."
);

-- map.meta
CREATE OR REPLACE FUNCTION map.meta() AS (STRUCT(
  "Mapping: Lambdas and transformers for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Lambdas and transformers for the 'substep' namespace."
);

-- try.meta
CREATE OR REPLACE FUNCTION try.meta() AS (STRUCT(
  "Testing: Dry-runs and unit tests for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Dry-runs and unit tests for the 'substep' namespace."
);


-- use.meta
CREATE OR REPLACE FUNCTION use.meta() AS (STRUCT(
  "Tooling: Core functions for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Core functions for the 'substep' namespace."
);


-- get.meta
CREATE OR REPLACE FUNCTION get.meta() AS (STRUCT(
  "Extraction: Parsers and extractors for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Parsers and extractors for the 'substep' namespace."
);

# Core functions (in dependency order)

-- fix.unsafeJson
create or replace function fix.unsafeJson(str STRING, esc BOOL) AS (
  (str)
  -- 1. JSON Structural Elements (Highest Priority)
  .REPLACE('{', IF(esc, '\x1C', '\\{')) -- FS: File Separator (Object Open)
  .REPLACE('}', IF(esc, '\x1D', '\\}')) -- GS: Group Separator (Object Close)
  .REPLACE('[', IF(esc, '\x02', '\\[')) -- STX: Start Text (Array Open)
  .REPLACE(']', IF(esc, '\x03', '\\]')) -- ETX: End Text (Array Close)
  .REPLACE(':', IF(esc, '\x1E', '\\:')) -- RS: Record Separator (KV Pair)
  .REPLACE(',', IF(esc, '\x1F', '\\,')) -- US: Unit Separator (List Item)

  -- 2. Secondary Wrappers (Lower Priority)
  .REPLACE('<', IF(esc, '\x01', '\\<')) -- SOH: Start Heading
  .REPLACE('>', IF(esc, '\x04', '\\>')) -- EOT: End Transmission
  .REPLACE('(', IF(esc, '\x11', '\\(')) -- DC1: Device Control 1
  .REPLACE(')', IF(esc, '\x13', '\\)')) -- DC3: Device Control 3

  -- 3. Escapes
  .REPLACE('#', IF(esc, '\x1B', '\\#')) -- ESC: Escape

) OPTIONS (
  description = "Escapes JSON delimiters using control characters or backslashes to prevent parsing collisions."
);

-- fix.emptyJsonKeys
create or replace function fix.emptyJsonKeys(jsn STRING) as (
  (jsn)
    .regexp_replace(r'""\:([^\{\}\[\]]*?)\,""\:([^\{\}\[\]]*?)',r'\1:\2')  -- move quoted keys/values into empty key position and mark insertion point
    .regexp_replace(r'([\{\,])\s*([^"\:\{\[\]\}\s]+)(\s*\:)',  r'\1"\2"\3') -- handle unquoted keys
    --.regexp_replace(r'^\{"":\{','{"_root":{') -- set root in case of unnamed top-level struct
    .replace('"":','"undefined":')
) OPTIONS (
  description = "Resolves empty:non-empty key/value sequences resulting from SQL-to-JSON conversion."
);

-- fix.shallowItems
create or replace function fix.shallowItems(jsn STRING) as (
  (jsn).regexp_replace(r'((?:"[^"]*"|[^:,{}]*)\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null))',r'"#":{\1},"#":#')
) OPTIONS (
  description = "Wraps shallow JSON key/value pairs with temporary object boundaries."
);

-- get.stringifiedJsonFromStruct
create or replace function get.stringifiedJsonFromStruct(object ANY TYPE) as ((

  with list as (
  
    select (sql).split(',') sql,(jsn).split(',') jsn from (
      select format("%T",object) sql,(object).to_json_string() jsn 
    ) -- coalesce(safe_divide(((jsn).split('},"":').array_length()-1),((jsn).split('","":').array_length()-1)),0), -- optional initial well-formedness check
  
  )

  -- resolve JSON floats from SQL string
  -- assumes balanced commas
  
  select /*array_to_string(sql,',') sql,*/if(array_length(sql) = array_length(jsn),(
    select string_agg(res,',' order by idx) from (
      select idx,IF((jsonpart).REGEXP_CONTAINS(r'[0-9]'),
        (jsonpart).REGEXP_REPLACE(r'^([^0-9]*)[0-9\.\s-]+([\]\}]*)$', 
           (r'\1').CONCAT((sql[idx]).ltrim().REGEXP_REPLACE(r'[^0-9\.\s-]', ''), r'\2') -- ltrim or no?    
      ),jsonpart) as res from unnest(jsn) jsonpart with offset idx
    )
  ), error("Imbalanced SQL / JSON part arrays")) jsn from list
  
)) OPTIONS (
  description = "Serializes a SQL struct to JSON while preserving literal source values."
);

-- lay.shallowItems
create or replace function lay.shallowItems(jsn STRING) as (
  (jsn).replace('"#":{','').replace('},"#":#','')
) OPTIONS (
  description = "Removes temporary object boundaries from nested JSON items."
);

-- lay.unsafeJson
create or replace function lay.unsafeJson(str STRING) AS (
  (str)
  -- 1. JSON Structural Elements (Highest Priority)
  .REPLACE('\x1C','{') -- FS: File Separator (Object Open)
  .REPLACE('\x1D','}') -- GS: Group Separator (Object Close)
  .REPLACE('\x02','[') -- STX: Start Text (Array Open)
  .REPLACE('\x03',']') -- ETX: End Text (Array Close)
  .REPLACE('\x1E',':') -- RS: Record Separator (KV Pair)
  .REPLACE('\x1F',',') -- US: Unit Separator (List Item)
  
  -- 2. Secondary Wrappers (Lower Priority)
  .REPLACE('\x01','<') -- SOH: Start Heading
  .REPLACE('\x04','>') -- EOT: End Transmission
  .REPLACE('\x11','(') -- DC1: Device Control 1
  .REPLACE('\x13',')') -- DC3: Device Control 3
  
  -- 3. Escapes
  .REPLACE('\x1B','#') -- ESC: Escape
  .REPLACE('\x05','"') -- ENQ (Enquiry) - Quote/Query Marker
 
) OPTIONS (
  description = "Restores control-character markers back to their literal characters."
);

-- map.unsafeJson
create or replace function map.unsafeJson(jsn STRING, esc BOOL) AS ((
  select string_agg(if(
    (str).starts_with("\x0F"),
      (str).replace("\x0F",'').(fix.unsafeJson)(esc),str),'' order by idx  --> make sure you don't accidentally replace 'safe' \x0F byte markers...
  )  from (
    select (jsn).REPLACE('\\"', if(esc,'\x05','\\“')) -- replace double quote with curly quote “ if esc = false (for debugging)
      .regexp_replace(r'"([^"]*)"', 
        CONCAT(CODE_POINTS_TO_STRING([14, 15]), '"\\1"', CODE_POINTS_TO_STRING([14])) -- 14 = \x0E and 15 = \x0F
      ).split('\x0E') as arr
  ) get, get.arr str with offset idx
)) OPTIONS (
  description = "Sanitizes quoted JSON fields by escaping reserved delimiters."
);

-- use.unroller
create or replace function use.unroller(jsn STRING, pairs array<struct<open STRING, close STRING>>, pick INT) as ((
  
  with init as (
    from get.characterIndices(jsn,(select concat('[',string_agg(concat('\\', pair.open,'\\',pair.close),''),']') from unnest(pairs) pair))
    |> call map.objectContainment(pairs)
    |> call get.objectBoundaries(jsn,pick)
    |> select level.*
  ),

  runs as (

    select *,        
      sum(array_length(children)) over(order by depth rows between unbounded preceding and 1 preceding) run1, 
      sum(array_length(children)) over(order by depth rows between unbounded preceding and 2 preceding) run2  
    from init where array_length(children) > 0
  
  ),

  link as (

    select depth,array(
      select as struct * except(acid,ocid,ecid,list) from (
     
        select coalesce(slot+run1,0) as nth,coalesce(parent.slot + run2,if(run1 is null,null,0)) as parenth,* replace(
          (select as struct coalesce(parent.slot + run2,if(run1 is null,null,0)) as nth, parent.key,parent.ord) as parent
        )
        from (
          select *,parents[range_bucket(child.close,looks)] as parent
          from unnest(children) as child
        )
        
      )
    ) as children from runs
    
  )
  
  select array(select as struct * from link)
   
)) OPTIONS (
  description = "Unrolls a JSON string into a linked parent-child list with structural metadata."
);

-- cue.objectMetadataInterface
create or replace function cue.objectMetadataInterface(a INT, b INT, jsn STRING, head ANY TYPE, tail ANY TYPE, slot INT, kpos INT) as (
  struct(
    head.raise,b as depth,slot,a as pre,head.idx as open,tail.idx as close,kpos,head.nest,
    get.keyFragment(jsn,head.idx,kpos) as key,null as arr_sym,null as arr_ctx,null as ord,null as sym, 
    get.objectFragment(jsn,head.idx,tail.idx) as json, null as acid,null as ocid,null as ecid,false as list --> acid: array container id / ocid: object container id / ecid: element container id
  )
) OPTIONS (
  description = "Defines the internal `get.objectMetadata()` interface."
);

-- fix.keyFragment
create or replace function fix.keyFragment(key STRING) as (
  (key).regexp_replace(r'[\{\[]+','').nullif('').rtrim(':').split(':').array_last().replace('"','')
) OPTIONS (
  description = "Normalizes a key string by removing padding and structural artifacts."
);

-- get.keyFragment
create or replace function get.keyFragment(jsn STRING,open INT, keypos INT) as (
  (jsn).substring(keypos+1,greatest(0,open-keypos-0)).ltrim(' ') 
) OPTIONS (
  description = "Extracts a JSON key segment based on open and closing positions."
);

-- get.nearestJsonKeyIndex
create or replace function get.nearestJsonKeyIndex(jsn STRING,idx INT) as (
  coalesce(
    NULLIF(INSTR(jsn, ',', -1 * (LENGTH(jsn) - idx + 2)), 0),
    NULLIF(INSTR(jsn, '[', -1 * (LENGTH(jsn) - idx + 3)), 0),
    NULLIF(INSTR(jsn, '{', -1 * (LENGTH(jsn) - idx + 2)), 0),
  0 )
) OPTIONS (
  description = "Locates a nearest key-like string based on structural boundaries preceding a JSON index."
);

-- get.objectFragment
create or replace function get.objectFragment(jsn STRING, open INT, close INT) as (
  (jsn).substr(open,close-open+1).(lay.shallowItems)()
) OPTIONS (
  description = "Extracts a specific JSON object fragment and removes temporary structural boundaries."
);

-- get.objectMetadata
create or replace function get.objectMetadata(a INT, b INT, pack ANY TYPE, jsn STRING) as ((

  with init as (

    from unnest(pack) as obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by slot,raise
    |> extend get.nearestJsonKeyIndex(jsn,head.idx) as kpos
    |> select cue.objectMetadataInterface(a,b,jsn,head,tail,slot,kpos).*
    
  ),
  
  syms as (
  
    from init
    |> set arr_sym = (key).replace('"#":{','').split(':'), sym = right(key,1)
    |> set arr_sym = coalesce(arr_sym[safe_offset(1)],arr_sym[safe_offset(0)])
    |> set arr_ctx = if(left(arr_sym,1) = '[' and substring(arr_sym,2,1) in ('[','{'),1,0)
  
  ),

  keys as (

    from syms       
    |> set key = fix.keyFragment(key)
    |> set key = if(key='#',(json).translate('{}"','').split(':')[safe_offset(0)],key), sym = if(key='#',key,sym)
    |> set key = coalesce(key,last_value(if(not raise,key,null) ignore nulls) over(partition by depth order by open))

  ),

  locs as (
    
    from keys
    |> set acid = sum(arr_ctx) over(partition by raise,depth order by slot)
    |> set ocid = row_number() over(partition by raise,depth,key order by open)-1
    |> set ecid = row_number() over(partition by raise,ocid order by open)-1
  
    |> set list = if(arr_sym in ("[{","[[") and sym in ("[","{"),true,null) 
    |> set list = coalesce(first_value(list ignore nulls) over(partition by raise,acid order by depth,slot),false)
  
  ),

  ords as ( 
    
    from locs
    |> set key = if(open = 1 and key is null,'$',key)
    |> set key = if(list,concat(coalesce(key,''),'[',row_number() over(partition by raise,depth,acid order by slot)-1,']'),key)
    |> set ord = concat('@{',ocid,',',ecid,'}')

  ),

  aggs as (

    from ords |> as objs 
    |> extend (select as struct objs.* except(raise,pre,depth,kpos,arr_sym,arr_ctx)) as obj,
    |> aggregate 
        array_agg(if(raise,obj,null) ignore nulls order by obj.open) children,
        array_agg(if(not raise,obj,null) ignore nulls order by obj.open) parents,
        array_agg(if(not raise,obj.close,null) ignore nulls order by obj.open) looks group by depth

  )

  select as struct * from aggs
  
)) OPTIONS (
  description = "Generates structural metadata and relational identifiers for packed JSON objects."
);

-- get.safeJson
create or replace function get.safeJson(object ANY TYPE) as (
  (object).(get.stringifiedJsonFromStruct)().(map.unsafeJson)(true).(fix.emptyJsonKeys)() 
) OPTIONS (
  description = "Serializes a SQL struct to JSON and applies control-character escaping for structural safety."
);

-- get.unrolled
create or replace function get.unrolled(jsn STRING, pairs array<struct<open STRING, close STRING>>, upto INT) as (
  (jsn).(fix.shallowItems)().(use.unroller)(pairs,upto)
) OPTIONS (
  description = "Returns an unrolled JSON string consisting of tuples or (nested) key/value pairs up to a chosen depth."
);

-- use.parser
create or replace function use.parser(object ANY TYPE, maxDepth INT) as ((

  with safe as (
    select get.safeJson(object) as jsn,[('[',']'),('{','}')] as pairs -- pairs' is for tracking array and object contexts during parsing
  ),

  main as (

    select jsn as str,array(
      select as struct * replace(array(
        select as struct * replace((json).(lay.unsafeJson)().(safe.parse_json)() as json) 
        from unnest(level.children)) as children
      ) from unnest(get.unrolled(jsn,pairs,maxDepth)) level
    ) levels, (jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root 
    from safe

  )

  select as struct * from main

)) OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
);

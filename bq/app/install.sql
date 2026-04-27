-- Generated BigQuery Install Script

-- ==========================================
-- META FUNCTIONS
-- ==========================================

-- Source: bq/cue/_meta.sql
CREATE OR REPLACE FUNCTION cue.meta() AS (STRUCT(
  "Validation: Type checkers and initialisers for the 'subtype' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Type checkers and initialisers for the 'subtype' namespace."
);

-- Source: bq/def/_meta.sql
CREATE OR REPLACE FUNCTION def.meta() AS (STRUCT(
  "Contracts: Schema defaults and API definitions for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Schema defaults and API definitions for the 'substep' namespace."
);

-- Source: bq/fix/_meta.sql
CREATE OR REPLACE FUNCTION fix.meta() AS (STRUCT(
  "Fixers: Patchers an correctors for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Patchers an correctors for the 'substep' namespace."
);

-- Source: bq/get/_meta.sql
CREATE OR REPLACE FUNCTION get.meta() AS (STRUCT(
  "Extraction: Parsers and extractors for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Parsers and extractors for the 'substep' namespace."
);

-- Source: bq/lay/_meta.sql
CREATE OR REPLACE FUNCTION lay.meta() AS (STRUCT(
  "Layers: Formatters and layouters for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Formatters and layouters for the 'substep' namespace."
);

-- Source: bq/map/_meta.sql
CREATE OR REPLACE FUNCTION map.meta() AS (STRUCT(
  "Mapping: Lambdas and transformers for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Lambdas and transformers for the 'substep' namespace."
);

-- Source: bq/try/_meta.sql
CREATE OR REPLACE FUNCTION try.meta() AS (STRUCT(
  "Testing: Dry-runs and unit tests for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Dry-runs and unit tests for the 'substep' namespace."
);

-- Source: bq/use/_meta.sql
CREATE OR REPLACE FUNCTION use.meta() AS (STRUCT(
  "Tooling: Core functions for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Core functions for the 'substep' namespace."
);

-- ==========================================
-- CORE FUNCTIONS (DEPENDENCY ORDER)
-- ==========================================


-- Source: bq/fix/jsonKeyFragment.sql
create or replace function fix.jsonKeyFragment(key STRING) as (
  (key).regexp_replace(r'[\{\[]+','').nullif('').rtrim(':').split(':').array_last().replace('"','')
) OPTIONS (
  description = "Normalizes a key string by removing padding and structural artifacts."
);

-- Source: bq/fix/jsonPrimitives.sql
create or replace function fix.jsonPrimitives(jsn STRING) as (
  (jsn).regexp_replace(r'((?:"[^"]*"|[^:,{}]*)\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null))',r'"#":{\1},"#":#')
) OPTIONS (
  description = "Wraps shallow JSON key/value pairs with temporary object boundaries."
);

-- Source: bq/fix/jsonSafeGuards.sql
create or replace function fix.jsonSafeGuards(str STRING, esc BOOL) AS (
  (str)

  .REPLACE('{', IF(esc, '\x1C', '\\{'))
  .REPLACE('}', IF(esc, '\x1D', '\\}'))
  .REPLACE('[', IF(esc, '\x02', '\\['))
  .REPLACE(']', IF(esc, '\x03', '\\]'))
  .REPLACE(':', IF(esc, '\x1E', '\\:'))
  .REPLACE(',', IF(esc, '\x1F', '\\,'))


  .REPLACE('<', IF(esc, '\x01', '\\<'))
  .REPLACE('>', IF(esc, '\x04', '\\>'))
  .REPLACE('(', IF(esc, '\x11', '\\('))
  .REPLACE(')', IF(esc, '\x13', '\\)'))


  .REPLACE('#', IF(esc, '\x1B', '\\#'))

) OPTIONS (
  description = "Escapes JSON delimiters using control characters or backslashes to prevent parsing collisions."
);

-- Source: bq/fix/jsonTuples.sql
create or replace function fix.jsonTuples(jsn STRING) as (
  (jsn)
    .regexp_replace(r'""\:([^\{\}\[\]]*?)\,""\:([^\{\}\[\]]*?)',r'\1:\2')
    .regexp_replace(r'([\{\,])\s*([^"\:\{\[\]\}\s]+)(\s*\:)',  r'\1"\2"\3')

    .replace('"":','"undefined":')
) OPTIONS (
  description = "Resolves empty:non-empty key/value sequences resulting from SQL-to-JSON conversion."
);

-- Source: bq/get/characterIndices.sql
create or replace table function get.characterIndices(str STRING, rgx STRING) as ((
  select regexp_instr(str, rgx, 1, off + 1) AS idx, sub
  from unnest(regexp_extract_all(str, rgx)) AS sub WITH OFFSET AS off
));

-- Source: bq/get/jsonKeyFragment.sql
create or replace function get.jsonKeyFragment(jsn STRING,open INT, keypos INT) as (
  (jsn).substring(keypos+1,greatest(0,open-keypos-0)).ltrim(' ')
) OPTIONS (
  description = "Extracts a JSON key segment based on open and closing positions."
);

-- Source: bq/get/jsonKeyIndex.sql
create or replace function get.jsonKeyIndex(jsn STRING,idx INT) as (
  coalesce(
    NULLIF(INSTR(jsn, ',', -1 * (LENGTH(jsn) - idx + 2)), 0),
    NULLIF(INSTR(jsn, '[', -1 * (LENGTH(jsn) - idx + 3)), 0),
    NULLIF(INSTR(jsn, '{', -1 * (LENGTH(jsn) - idx + 2)), 0),
  0 )
) OPTIONS (
  description = "Locates a nearest key-like string based on structural boundaries preceding a JSON index."
);

-- Source: bq/get/jsonStringFromStruct.sql
create or replace function get.jsonStringFromStruct(object ANY TYPE) as ((

  with list as (

    select (sql).split(',') sql,(jsn).split(',') jsn from (
      select format("%T",object) sql,(object).to_json_string() jsn
    )

  )




  select if(array_length(sql) = array_length(jsn),(
    select string_agg(res,',' order by idx) from (
      select idx,IF((jsonpart).REGEXP_CONTAINS(r'[0-9]'),
        (jsonpart).REGEXP_REPLACE(r'^([^0-9]*)[0-9\.\s-]+([\]\}]*)$',
           (r'\1').CONCAT((sql[idx]).ltrim().REGEXP_REPLACE(r'[^0-9\.\s-]', ''), r'\2')
      ),jsonpart) as res from unnest(jsn) jsonpart with offset idx
    )
  ), error("Imbalanced SQL / JSON part arrays")) jsn from list

)) OPTIONS (
  description = "Serializes a SQL struct to JSON while preserving literal source values."
);

-- Source: bq/lay/jsonPrimitives.sql
create or replace function lay.jsonPrimitives(jsn STRING) as (
  (jsn).replace('"#":{','').replace('},"#":#','')
) OPTIONS (
  description = "Removes temporary object boundaries from nested JSON items."
);

-- Source: bq/get/jsonObjectFragment.sql
create or replace function get.jsonObjectFragment(jsn STRING, open INT, close INT) as (
  (jsn).substr(open,close-open+1).(lay.jsonPrimitives)()
) OPTIONS (
  description = "Extracts a specific JSON object fragment and removes temporary structural boundaries."
);

-- Source: bq/cue/jsonObjectInterface.sql
create or replace function cue.jsonObjectInterface(a INT, b INT, jsn STRING, head ANY TYPE, tail ANY TYPE, slot INT, kpos INT) as (
  struct(
    head.raise,b as depth,slot,a as pre,head.idx as open,tail.idx as close,kpos,head.nest,
    get.jsonKeyFragment(jsn,head.idx,kpos) as key,null as arr_sym,null as arr_ctx,null as ord,null as sym,
    get.jsonObjectFragment(jsn,head.idx,tail.idx) as json, null as acid,null as ocid,null as ecid,false as list
  )
) OPTIONS (
  description = "Defines the internal `get.jsonObjectMetadata()` interface."
);

-- Source: bq/get/jsonObjectMetadata.sql
create or replace function get.jsonObjectMetadata(a INT, b INT, pack ANY TYPE, jsn STRING) as ((

  with init as (

    from unnest(pack) as obj
    |> aggregate min_by(obj,pin) head,max_by(obj,pin) tail group by slot,raise
    |> extend get.jsonKeyIndex(jsn,head.idx) as kpos
    |> select cue.jsonObjectInterface(a,b,jsn,head,tail,slot,kpos).*

  ),

  syms as (

    from init
    |> set arr_sym = (key).replace('"#":{','').split(':'), sym = right(key,1)
    |> set arr_sym = coalesce(arr_sym[safe_offset(1)],arr_sym[safe_offset(0)])
    |> set arr_ctx = if(left(arr_sym,1) = '[' and substring(arr_sym,2,1) in ('[','{'),1,0)

  ),

  keys as (

    from syms
    |> set key = fix.jsonKeyFragment(key)
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

-- Source: bq/get/jsonObjectBoundaries.sql
create or replace table function get.jsonObjectBoundaries(input table <idx INT, sub STRING, pre INT, depth INT, depths array<INT>, raise BOOL>, jsn STRING, pick INT) as (

   with init as (
    select * replace(
      if(a > b,b,a) as a,
      if(a > b,a,b) as b
    ) from (
      select raise,pre a, depth b,
        array_agg(struct(pre > depth as pin,raise,idx,sub,depths[0] as nest) order by idx) subs,
      from input
      group by raise,a,b
      having a < pick + 1
    )
  )

  select get.jsonObjectMetadata(a,b,array_concat_agg(
    array(select as struct slot,* except(slot) from unnest(subs) with offset as slot )
  ),jsn) as level from init group by a,b having a < pick + 0 order by a,b

);

-- Source: bq/lay/jsonSafeGuards.sql
create or replace function lay.jsonSafeGuards(str STRING) AS (
  (str)

  .REPLACE('\x1C','{')
  .REPLACE('\x1D','}')
  .REPLACE('\x02','[')
  .REPLACE('\x03',']')
  .REPLACE('\x1E',':')
  .REPLACE('\x1F',',')


  .REPLACE('\x01','<')
  .REPLACE('\x04','>')
  .REPLACE('\x11','(')
  .REPLACE('\x13',')')


  .REPLACE('\x1B','#')
  .REPLACE('\x05','"')

) OPTIONS (
  description = "Restores control-character markers back to their literal characters."
);

-- Source: bq/map/jsonSafeGuards.sql
create or replace function map.jsonSafeGuards(jsn STRING, esc BOOL) AS ((
  select string_agg(if(
    (str).starts_with("\x0F"),
      (str).replace("\x0F",'').(fix.jsonSafeGuards)(esc),str),'' order by idx
  )  from (
    select (jsn).REPLACE('\\"', if(esc,'\x05','\\“'))
      .regexp_replace(r'"([^"]*)"',
        CONCAT(CODE_POINTS_TO_STRING([14, 15]), '"\\1"', CODE_POINTS_TO_STRING([14]))
      ).split('\x0E') as arr
  ) get, get.arr str with offset idx
)) OPTIONS (
  description = "Sanitizes quoted JSON fields by escaping reserved delimiters."
);

-- Source: bq/get/jsonStringMask.sql
create or replace function get.jsonStringMask(object ANY TYPE) as (
  (object).(get.jsonStringFromStruct)().(map.jsonSafeGuards)(true).(fix.jsonTuples)()
) OPTIONS (
  description = "Serializes a SQL struct to JSON and applies control-character escaping for structural safety."
);

-- Source: bq/map/objectContainment.sql
create or replace table function map.objectContainment(input table<idx INT, sub STRING>, pairs array<struct<open STRING, close STRING>>) as (

  with locs as (

    select idx,sub,null as pre,sum(deep) - 1 depth, array_agg(deep) depths,array_agg(pair.open) openers from (
      select array(
        select as struct idx,sub,off,pair, sum(case when sub = pair.open then 1 when sub = pair.close then -1 else 0 end) over(w1) as deep
        from input window w1 as (order by idx rows between unbounded preceding and current row)
      ) dat from unnest(pairs) pair with offset as off
    ) get,get.dat group by idx,sub

  )

  select * except(openers) replace(depth - (case when sub in unnest(openers) then 1 else -1 end) + raise as pre,depth+raise as depth, raise = 0  as raise)
  from locs,unnest(generate_array(0,1)) raise

);

-- Source: bq/use/unroller.sql
create or replace function use.unroller(jsn STRING, pairs array<struct<open STRING, close STRING>>, pick INT) as ((

  with init as (
    from get.characterIndices(jsn,(select concat('[',string_agg(concat('\\', pair.open,'\\',pair.close),''),']') from unnest(pairs) pair))
    |> call map.objectContainment(pairs)
    |> call get.jsonObjectBoundaries(jsn,pick)
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

-- Source: bq/get/unrolled.sql
create or replace function get.unrolled(jsn STRING, pairs array<struct<open STRING, close STRING>>, upto INT) as (
  (jsn).(fix.jsonPrimitives)().(use.unroller)(pairs,upto)
) OPTIONS (
  description = "Returns an unrolled JSON string consisting of tuples or (nested) key/value pairs up to a chosen depth."
);

-- Source: bq/use/parser.sql
create or replace function use.parser(object ANY TYPE, maxDepth INT) as ((

  with safe as (
    select get.jsonStringMask(object) as jsn, [('[',']'),('{','}')] as pairs
  ),

  main as (

    select jsn as str,array(
      select as struct * replace(array(
        select as struct * replace((json).(lay.jsonSafeGuards)().(safe.parse_json)() as json)
        from unnest(level.children)) as children
      ) from unnest(get.unrolled(jsn,pairs,maxDepth)) level
    ) levels, (jsn).starts_with('[{') or (jsn).starts_with('[[') is_array_root
    from safe

  )

  select as struct * from main

)) OPTIONS (
   description = "Parses a complex SQL object into plain JSON by canonicalising the input."
);

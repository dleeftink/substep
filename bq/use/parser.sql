create or replace function use.parser(object ANY TYPE, maxDepth INT) as ((

  with safe as (
    select get.jsonStringMask(object) as jsn, [('[',']'),('{','}')] as pairs -- pairs' is for tracking array and object contexts during parsing
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
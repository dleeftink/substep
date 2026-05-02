# su~~b~~*p*step

The global `substep` namespace containing single step functions for downstream `sup.*` packages. Includes various BigQuery utility functions for scaffolding complex UDFs and TVFs.
This is the only 'non-sup' prefixed package as I couldn't refrain from picking the (still) available `substep` namespace on BigQuery.  

Above all: it just makes sense. We can globally call `substep.get.parsed(obj)` for instance, when we want to get a parsed SQL object (struct) in a substep of an existing workflow.
Generally these functions are for internal use only but may find utility elsewhere (see `bq/try` for example test cases).

## Architecture

``` mermaid
graph BT
    cue.jsonObjectInterface((cue.jsonObjectInterface))
    cue.meta[cue.meta]
    def.meta[def.meta]
    fix.jsonKeyFragment[fix.jsonKeyFragment]
    fix.jsonPrimitives[fix.jsonPrimitives]
    fix.jsonSafeGuards[fix.jsonSafeGuards]
    fix.jsonTuples[fix.jsonTuples]
    fix.meta[fix.meta]
    get.characterIndices[get.characterIndices]
    get.jsonKeyFragment[get.jsonKeyFragment]
    get.jsonKeyIndex[get.jsonKeyIndex]
    get.jsonObjectBoundaries((get.jsonObjectBoundaries))
    get.jsonObjectFragment((get.jsonObjectFragment))
    get.jsonObjectMetadata((get.jsonObjectMetadata))
    get.jsonStringFromStruct[get.jsonStringFromStruct]
    get.jsonStringMask((get.jsonStringMask))
    get.meta[get.meta]
    get.unrolled((get.unrolled))
    lay.jsonPrimitives[lay.jsonPrimitives]
    lay.jsonSafeGuards[lay.jsonSafeGuards]
    lay.meta[lay.meta]
    map.jsonSafeGuards((map.jsonSafeGuards))
    map.meta[map.meta]
    map.objectContainment[map.objectContainment]
    use.meta[use.meta]
    use.parser((use.parser))
    use.unroller((use.unroller))
    lay.jsonPrimitives --> get.jsonObjectFragment
    get.jsonKeyFragment --> cue.jsonObjectInterface
    get.jsonObjectFragment --> cue.jsonObjectInterface
    cue.jsonObjectInterface --> get.jsonObjectMetadata
    fix.jsonKeyFragment --> get.jsonObjectMetadata
    get.jsonKeyIndex --> get.jsonObjectMetadata
    get.jsonObjectMetadata --> get.jsonObjectBoundaries
    fix.jsonSafeGuards --> map.jsonSafeGuards
    fix.jsonTuples --> get.jsonStringMask
    get.jsonStringFromStruct --> get.jsonStringMask
    map.jsonSafeGuards --> get.jsonStringMask
    get.characterIndices --> use.unroller
    get.jsonObjectBoundaries --> use.unroller
    map.objectContainment --> use.unroller
    fix.jsonPrimitives --> get.unrolled
    use.unroller --> get.unrolled
    get.jsonStringMask --> use.parser
    get.unrolled --> use.parser
    lay.jsonSafeGuards --> use.parser
```
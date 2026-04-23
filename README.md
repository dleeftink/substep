# su~~b~~*p*step

The global `substep` namespace containing single step functions for downstream `sup.*` packages. Includes various BigQuery utility functions for scaffolding complex UDFs and TVFs.
This is the only 'non-sup' prefixed package as I couldn't refrain from picking the (still) available `substep` namespace on BigQuery.  

Above all: it just makes sense. We can globally call `substep.get.parsed(obj)` for instance, when we want to get a parsed SQL object (struct) in a substep of an existing workflow.
Generally these functions are for internal use only but may find utility elsewhere (see `bq/try` for example test cases).

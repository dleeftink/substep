# su~~b~~*p*step

The global `substep` namespace for downstream `sup.*` packages. Contains various BigQuery utility functions for scaffolding complex UDFs and TVFs.
The only 'non-sup' prefixed package as I couldn't refrain from picking up the (still) available `substep` namespace on BigQuery.  

Above all: it just makes sense. For instance, we can globally call `substep.get.parsed(obj)` when we want to get a parsed SQL object (struct) in a substep of an existing workflow.
Generally these functions are for internal use only, but may find utility elsewhere (see `bq/try` for example test cases).

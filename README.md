# su~~b~~*p*step

The global `substep` namespace for downstream `sup.*` packages. Contains various BigQuery utility functions for scaffolding complex UDFs and TVFs.
The only 'non-sup' prefixed package as I couldn't refrain from picking the (still) available `substep` namespace on BigQuery.  

Above all: it just makes sense. We can globally call `substep.use.unroller()` for instance, when we require an 'unroll substep' in our existing dataflow.
Generally these functions are for internal use but may find utility elsewhere (see `bq/try` for example test cases)

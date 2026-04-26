CREATE OR REPLACE FUNCTION map.meta() AS (STRUCT(
  "Mapping: Lambdas and transformers for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Lambdas and transformers for the 'substep' namespace."
);
CREATE OR REPLACE FUNCTION def.meta() AS (STRUCT(
  "Contracts: Schema defaults and API definitions for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Schema defaults and API definitions for the 'substep' namespace."
);

CREATE OR REPLACE FUNCTION use.meta() AS (STRUCT(
  "Tooling: Core functions for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Core functions for the 'substep' namespace."
);
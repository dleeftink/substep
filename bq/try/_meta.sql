CREATE OR REPLACE FUNCTION try.meta() AS (STRUCT(
  "Testing: Dry-runs and unit tests for the 'substep' namespace." AS scope,
  "0.1.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Dry-runs and unit tests for the 'substep' namespace."
);
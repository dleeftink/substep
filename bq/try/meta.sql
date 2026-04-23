CREATE OR REPLACE FUNCTION try.meta() AS (STRUCT(
  "Testing: Dry-runs and unit tests for the 'substep' namespace." AS scope,
  "v0.0.0" AS version,
  null AS repo
)) OPTIONS (
  description = "Dry-runs and unit tests for the 'substep' namespace."
);

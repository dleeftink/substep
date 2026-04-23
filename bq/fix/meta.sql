CREATE OR REPLACE FUNCTION fix.meta() AS (STRUCT(
  "Fixers: Patchers an correctors for the 'substep' namespace." AS scope,
  "v0.0.0" AS version,
  null AS repo
)) OPTIONS (
  description = "Patchers an correctors for the 'substep' namespace."
);

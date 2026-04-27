CREATE OR REPLACE FUNCTION fix.meta() AS (STRUCT(
  "Fixers: Patchers an correctors for the 'substep' namespace." AS scope,
  "0.1.1" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Patchers an correctors for the 'substep' namespace."
);
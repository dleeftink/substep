CREATE OR REPLACE FUNCTION lay.meta() AS (STRUCT(
  "Layers: Formatters and layouters for the 'substep' namespace." AS scope,
  "v0.0.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Formatters and layouters for the 'substep' namespace."
);

CREATE OR REPLACE FUNCTION get.meta() AS (STRUCT(
  "Extraction: Parsers and extractors for the 'substep' namespace." AS scope,
  "v0.0.0" AS version,
  null AS repo
)) OPTIONS (
  description = "Parsers and extractors for the 'substep' namespace."
);

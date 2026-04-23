CREATE OR REPLACE FUNCTION get.meta() AS (STRUCT(
  "Extraction: Parsers and extractors for the 'substep' namespace." AS scope,
  "v0.0.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Parsers and extractors for the 'substep' namespace."
);

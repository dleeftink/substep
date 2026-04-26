CREATE OR REPLACE FUNCTION cue.meta() AS (STRUCT(
  "Validation: Type checkers and initialisers for the 'subtype' namespace." AS scope,
  "v0.0.0" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Type checkers and initialisers for the 'subtype' namespace."
);
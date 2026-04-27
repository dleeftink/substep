CREATE OR REPLACE FUNCTION cue.meta() AS (STRUCT(
  "Validation: Type checkers and initialisers for the 'subtype' namespace." AS scope,
  "0.1.2" AS version,
  "https://github.com/dleeftink/substep" AS repo
)) OPTIONS (
  description = "Type checkers and initialisers for the 'subtype' namespace."
);
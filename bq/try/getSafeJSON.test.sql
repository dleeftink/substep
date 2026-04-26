CREATE OR REPLACE FUNCTION try.if__get_safeJSON__produces_valid_json_after_unescape() AS (
  SAFE.PARSE_JSON(
    (get.safeJSON(STRUCT('hello' AS greeting, 42 AS answer)).(lay.unsafeJson)())
  ) IS NOT NULL
) OPTIONS (
  description = 'Verifies get.safeJSON output becomes valid JSON after unescaping.'
);

CREATE OR REPLACE FUNCTION try.if__get_safeJSON__preserves_scalar_values_after_unescape() AS (
  JSON_EXTRACT_SCALAR(
    (get.safeJSON(STRUCT('hello' AS greeting, 42 AS answer)).(lay.unsafeJson)()),
    '$.greeting'
  ) = 'hello'
  AND JSON_EXTRACT_SCALAR(
    (get.safeJSON(STRUCT('hello' AS greeting, 42 AS answer)).(lay.unsafeJson)()),
    '$.answer'
  ) = '42'
) OPTIONS (
  description = 'Verifies get.safeJSON preserves scalar fields after unescaping.'
);

CREATE OR REPLACE FUNCTION try.if__get_safeJSON__preserves_nested_fields_after_unescape() AS (
  JSON_EXTRACT_SCALAR(
    (get.safeJSON(STRUCT(STRUCT(1 AS inner) AS nested)).(lay.unsafeJson)()),
    '$.nested.inner'
  ) = '1'
) OPTIONS (
  description = 'Verifies get.safeJSON preserves nested struct values after unescaping.'
);

CREATE OR REPLACE FUNCTION try.if__get_safeJSON__uses_control_character_escapes() AS (
  STRPOS(
    get.safeJSON(STRUCT('quoted "value"' AS text)),
    CODE_POINTS_TO_STRING([28])
  ) > 0
) OPTIONS (
  description = 'Verifies get.safeJSON uses control-character escaping in the encoded payload.'
);
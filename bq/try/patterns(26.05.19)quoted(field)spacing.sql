WITH test_cases AS (
  SELECT 'Standard JSON' AS case_name, '{\n  "name": "John Doe",\n  "age": 30\n}' AS input UNION ALL
  SELECT 'Escaped Backslashes' AS case_name, '{"path": "C:\\\\Program Files\\\\App"}' AS input UNION ALL
  SELECT 'Escaped Quotes Inside' AS case_name, '{"quote": "He said, \\"Hello World\\" today."}' AS input UNION ALL
  SELECT 'Unicode Sequences' AS case_name, '{"char": "\\u0041 and \\u3042"}' AS input UNION ALL
  SELECT 'All Control Escapes' AS case_name, '{"escapes": "\\b \\f \\n \\r \\t \\/"}' AS input UNION ALL
  SELECT 'Preserve Empty Strings' AS case_name, '{"empty": ""}' AS input
)
SELECT 
  case_name,
  input AS original,
  REGEXP_REPLACE(input, r'("(?:[^"\\]|\\.)*")|\s+', r'\1') AS minified, -- basic
  REGEXP_REPLACE(input, r'("[^"\\]*(?:\\.[^"\\]*)*")|\s+', r'\1') AS minified, -- no alternation
  REGEXP_REPLACE(input, r'("([^"\\]|\\["\\bfnrtv]|\\u[0-9a-fA-F]{4})*")|\s+', r'\1') AS minified, -- validation during extraction 1
  REGEXP_REPLACE(input, r'("([^"\\]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*")|\s+', r'\1') AS minified, -- validation during extraction 2 (corrected)
  REGEXP_REPLACE(input, r'("([^"\\\x00-\x1F]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*")|\s+', r'\1') AS minified, -- validation during extraction 3 (corrected)
FROM test_cases;
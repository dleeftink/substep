CREATE OR REPLACE FUNCTION fix.jsonPrimitives(jsn STRING) AS (
  (jsn).REGEXP_REPLACE(r'("[^"]*"\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null))', r'"#":{\1},"#":#')
); OPTIONS (
  description = "Wraps shallow JSON key/value pairs with temporary object boundaries."
);
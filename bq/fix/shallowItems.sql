create or replace function fix.shallowItems(jsn STRING) as (
  (jsn).regexp_replace(r'((?:"[^"]*"|[^:,{}]*)\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null))',r'"#":{\1},"#":#')
) OPTIONS (
  description = "Temporarily escapes shallow JSON key/value pairs."
);

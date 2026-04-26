create or replace function fix.shallowItems(jsn STRING) as (
  (jsn).regexp_replace(r'((?:"[^"]*"|[^:,{}]*)\s*:\s*(?:"[^"]*"|[\d\.]+|true|false|null))',r'"#":{\1},"#":#')
) OPTIONS (
  description = "Wraps shallow JSON key/value pairs with temporary object boundaries."
);
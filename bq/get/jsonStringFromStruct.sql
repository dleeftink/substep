create or replace function get.jsonStringFromStruct(object ANY TYPE) as ((

  with list as (
  
    select (sql).split(',') sql,(jsn).split(',') jsn from (
      select format("%T",object) sql,(object).to_json_string() jsn 
    ) -- coalesce(safe_divide(((jsn).split('},"":').array_length()-1),((jsn).split('","":').array_length()-1)),0), -- optional initial well-formedness check
  
  )

  -- resolve JSON floats from SQL string
  -- assumes balanced commas
  
  select /*array_to_string(sql,',') sql,*/if(array_length(sql) = array_length(jsn),(
    select string_agg(res,',' order by idx) from (
      select idx,IF((jsonpart).REGEXP_CONTAINS(r'[0-9]'),
        (jsonpart).REGEXP_REPLACE(r'^([^0-9]*)[0-9\.\s-]+([\]\}]*)$', 
           (r'\1').CONCAT((sql[idx]).ltrim().REGEXP_REPLACE(r'[^0-9\.\s-]', ''), r'\2') -- ltrim or no?    
      ),jsonpart) as res from unnest(jsn) jsonpart with offset idx
    )
  ), error("Imbalanced SQL / JSON part arrays")) jsn from list
  
)) OPTIONS (
  description = "Serializes a SQL struct to JSON while preserving literal source values."
);
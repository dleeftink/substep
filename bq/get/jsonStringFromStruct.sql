create or replace function get.jsonStringFromStruct(object ANY TYPE) as ((

  with list as (
  
    select (sql).split(',') sql,(jsn).split(',') jsn from (
      select format("%T",object) sql,(object).to_json_string() jsn 
    ) -- coalesce(safe_divide(((jsn).split('},"":').array_length()-1),((jsn).split('","":').array_length()-1)),0), -- optional initial well-formedness check
  
  ),

  fuse as (

    -- resolve JSON floating conversion from source SQL string
    -- assumes balanced commas
    
    select if(array_length(sql) = array_length(jsn),(
      select string_agg(res,',' order by idx) from (
        select idx,IF((jsonpart).translate('0123456789','0').contains_substr("0"),
          (jsonpart).REGEXP_REPLACE(r'^([^0-9]*)[0-9\.\s-]+([\]\}]*)$',
             (r'\1').CONCAT((sql[idx]).ltrim().REGEXP_REPLACE(r'[^0-9\.\s-]', ''), r'\2')
        ),jsonpart) as res from unnest(jsn) jsonpart with offset idx
      )
    ), error("Imbalanced SQL / JSON part arrays")) jsn from list
  
  )

  select jsn from fuse

)) OPTIONS (
  description = "Serializes a SQL struct to JSON while preserving literal source values."
);
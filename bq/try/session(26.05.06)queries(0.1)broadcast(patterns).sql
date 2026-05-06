CREATE or replace AGGREGATE FUNCTION tmp.ScaledAverage(
  v FLOAT64,
  divisor FLOAT64)
AS (
  AVG(v / divisor)
 );

CREATE or replace AGGREGATE FUNCTION tmp.multiAggregate1(
  v FLOAT64,
  divisor FLOAT64)
AS (struct(
  AVG(v / divisor) as sv,
  max(v) as mv
));

-- unused

create or replace table function tmp.aggregator1(input table<v int>, divisor int) as (

  --select AVG(v / divisor) sv from input
  --any_value((select tmp.ScaledAverage(v,divisor) sv from input)) sv from unnest([0])
  --select tmp.ScaledAverage(v,divisor) as sv,max(v) as mv from input
  select tmp.multiAggregate1(v,divisor) as constants from input
);

create or replace table function tmp.inner1(input table<v int>,constants any type) as (

  
  select (v-c.sv)/c.mv v from input 
  cross join ((select any_value(constants) c from (select null))) --> trade shuffle for compute
  -- left join ((select any_value(constants) c from (select null))) on true --> trade compute for shuffle

  --select (v-c.sv)/c.mv v from input 
  --cross join (select any_value(c).* from unnest(constants) c) c  

  -- select (v - constants.sv)/constants.mv v from input 

  -- select (v -  any_value(constants.sv))/any_value(constants.mv) nv
  -- from input group by v

);

create or replace table function tmp.thru1(input table<v int>,constants any type) as (

  with init as (
    select v
    from input
  )

  from init |> call tmp.inner1(constants)

);

create or replace table function tmp.processor1(input table<v int>,divisor int) as (

  with exit as (
    select * from tmp.thru1(table input, 
      constants => -- (from input |> call tmp.aggregator1(2) |> select *) 
      -- (from input |> call tmp.aggregator1(divisor) |> select as struct *)
      (from input |> aggregate tmp.multiAggregate1(v,divisor))
      --(select tmp.multiAggregate1(v,divisor) from input)
      --(select * from tmp.aggregator1(table input,divisor))
    )
  )

  select * from exit

);

create temp table init cluster by v as (
  select v from  unnest(generate_array(0,1000000)) v
);

select * from tmp.processor1(table init,2)


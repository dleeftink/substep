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
  max(v) as mv --,any_value(rand()) as rv
));

create or replace table function tmp.aggregator1(input table<v int>, divisor int) as (

  -- Granular:
  -- select tmp.ScaledAverage(v,divisor) as sv,max(v) as mv from input
  
  -- Colocated:
  select tmp.multiAggregate1(v,divisor) as constants from input

);

create or replace table function tmp.inner1(input table<v int>,constants any type) as (

  -- Pattern to emulate:
  -- select (v - avg(v/2) over())/max(v) over() v
  -- from input

  -- Single scan patterns:
  
  -- Pattern A:
  -- select (v-c.sv)/c.mv v from input 
  -- cross join unnest([constants]) c

  -- Pattern B:
  select (v-c.sv)/c.mv v from input 
  cross join (select null |> aggregate any_value(constants) c) --> trade shuffle for compute
  -- left join ((select any_value(constants) c from (select null))) on true --> trade compute for shuffle

  -- Pattern C:
  -- select (select (v-c.sv)/c.mv from (select any_value(constants) over() c from (select null))) v
  -- from input
  
  -- Double scan patterns:
  
  -- Pattern C:
  -- select ((v - constants.sv)/constants.mv) v 
  -- from input --> reads twice but keeps local compute

  -- Pattern D:
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
      constants => 
      (from input |> aggregate tmp.multiAggregate1(v,divisor)) -- UDAF aggregator
      -- (from input |> call tmp.aggregator1(divisor) -- TVF aggregator
    )
  )

  select * from exit

);

create temp table init cluster by v as (
  select v from  unnest(generate_array(0,1000000)) v
);

select * from tmp.processor1(table init,2)
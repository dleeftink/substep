DECLARE target_strategy STRING DEFAULT 'Strategy_A';
DECLARE total_runs INT64 DEFAULT 2;

DECLARE current_run INT64 DEFAULT 1;
DECLARE current_job_id STRING;

create temp function query (label string,run int) as (
  r"-- run: " || label||' ('||cast(run as string)||')'||
  r"""

  with init as (

    select * from (
      select (hits).to_json_string(true) as str from `stack-curves.tables.hits` -- limit 1
      union all
      select (hits).to_json_string(true) as str from `stack-curves.tables.hits` -- limit 1
    ) where rand() > 0 qualify true = max(true) over()
  
  ),
  
  proc as (
  
    select str,(str).regexp_extract_all(tmp.layJsonFragmentPattern2a()) hits from init
    --select str,(str).replace('\\"','\x05\\').regexp_extract_all(tmp.layJsonFragmentPattern2d()) hits from init
    --select str,(str).replace('\\"','\x05\\').regexp_replace(r'("[^"]*")|\s', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2e()) hits from init
    --select str,(str).regexp_replace(r'("(?:[^"\\]|\\.)*")|\s+', r'\1').regexp_extract_all(tmp.layJsonFragmentPattern2g()) hits from init
  ),
  
  test as (
  
    select as struct (str).length() len,
      array(select /*as struct*/ (hit).rtrim('\t\n\r ')--,sum((hit).length()) over() 
      from unnest(hits) hit
      ) hits
    from proc
  
  )
  
  select (hits)[safe_offset(cast((array_length(hits)-1)*rand() as int))].right(1) from test;
  
""");

CREATE OR REPLACE TEMP TABLE benchmark_results AS 
select * from (
  SELECT 
  CAST(NULL AS STRING) AS strategy,
  CAST(NULL AS INT64) AS run_number,
  CAST(NULL AS STRING) AS job_id,
  CAST(NULL AS FLOAT64) AS elapsed_time_sec,
  CAST(NULL AS FLOAT64) AS total_slot_time_sec,
  CAST(NULL AS FLOAT64) AS min_stage_slot_time_sec,
  CAST(NULL AS FLOAT64) AS max_stage_slot_time_sec,
  CAST(NULL AS FLOAT64) AS bytes_processed,
  CAST(NULL AS FLOAT64) AS bytes_shuffled,
  CAST(NULL AS FLOAT64) AS bytes_spilled
) WHERE 1=0;

WHILE current_run <= total_runs DO
  
  EXECUTE IMMEDIATE query(target_strategy, current_run);

  SET current_job_id = @@last_job_id;

  CREATE OR REPLACE TEMP TABLE benchmark_results AS
  SELECT * FROM benchmark_results
  UNION ALL
  SELECT
    target_strategy AS strategy,
    current_run AS run_number,
    j.job_id,
    TIMESTAMP_DIFF(j.end_time, j.start_time, MILLISECOND) / 1000.0 AS elapsed_time_sec,
    j.total_slot_ms / 1000.0 AS total_slot_time_sec,
    -- Extract the lowest slot time consumed by any single stage
    (SELECT SAFE_DIVIDE(MIN(stage.slot_ms), 1000.0) FROM UNNEST(j.job_stages) AS stage) AS min_stage_slot_time_sec,
    -- Extract the peak slot time consumed by the heaviest stage
    (SELECT SAFE_DIVIDE(MAX(stage.slot_ms), 1000.0) FROM UNNEST(j.job_stages) AS stage) AS max_stage_slot_time_sec,
    SAFE_DIVIDE(j.total_bytes_processed, 1024 * 1024).round(2) AS bytes_processed,
    -- Flatten the nested stage data to calculate total shuffle across the entire query graph
    (SELECT SAFE_DIVIDE(SUM(stage.shuffle_output_bytes), 1024 * 1024) FROM UNNEST(j.job_stages) AS stage).round(2) AS bytes_shuffled,
    -- Flatten the nested stage data to track any spilled disk usage
    (SELECT SAFE_DIVIDE(SUM(stage.shuffle_output_bytes_spilled), 1024 * 1024) FROM UNNEST(j.job_stages) AS stage).round(2) AS bytes_spilled
  FROM
    `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT j
  WHERE
    j.job_id = current_job_id;

  SET current_run = current_run + 1;
END WHILE;

-- 5. Output the Final Aggregated Aggregations (Noise-Filtered)
with exit as (
  
  SELECT
    strategy,
    -- Calculate percentiles across the entire strategy population safely
    PERCENTILE_CONT(elapsed_time_sec, 0.5) OVER(PARTITION BY strategy) AS p50_elapsed_sec,
    PERCENTILE_CONT(elapsed_time_sec, 0.9) OVER(PARTITION BY strategy) AS p90_elapsed_sec,
    -- Pass the raw metrics through to the next step for averaging
    total_slot_time_sec,
    min_stage_slot_time_sec,
    max_stage_slot_time_sec,
    bytes_processed,
    bytes_shuffled,
    bytes_spilled
  FROM
    benchmark_results

),

aggs as (
  SELECT
    strategy,
    COUNT(*) AS total_successful_runs,
    -- Take the MAX or MIN of the percentiles since they are already calculated uniformly per strategy
    MAX(p50_elapsed_sec) AS p50_elapsed_sec,
    MAX(p90_elapsed_sec) AS p90_elapsed_sec,
    -- Average the remaining resource metrics safely
    ROUND(AVG(total_slot_time_sec), 3) AS avg_total_slot_sec,
    ROUND(AVG(min_stage_slot_time_sec), 3) AS avg_min_stage_slot_sec,
    ROUND(AVG(max_stage_slot_time_sec), 3) AS avg_max_stage_slot_sec,
    ROUND(AVG(bytes_processed), 2) AS avg_mb_processed,
    ROUND(AVG(bytes_shuffled), 2) AS avg_mb_shuffled,
    ROUND(AVG(bytes_spilled), 2) AS avg_mb_spilled
  FROM
    exit
  GROUP BY
    strategy
)

select * from aggs

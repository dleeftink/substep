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
    elapsed_time_sec,
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
    avg(elapsed_time_sec) as avg_elapsed_time,
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

/*
x1	Strategy_A	25	1.1860833333333334	1.1415	1.3637000000000001	23.916	0.04	20.487	17.59	143.69	0.0	(no post string trimming)
1	Strategy_A	25	1.5755416666666668	1.5005	1.8424	28.143	0.058	24.069	17.59	196.13	0.0	

Row	strategy	total_successful_runs	avg_elapsed_time	p50_elapsed_sec	p90_elapsed_sec	avg_total_slot_sec	avg_min_stage_slot_sec	avg_max_stage_slot_sec	avg_mb_processed	avg_mb_shuffled	avg_mb_spilled
1	Strategy_A	25	1.55554	1.468	1.7498	27.122	0.042	23.128	17.59	196.13	0.0	
2	Strategy_B	25	1.3792272727272727	1.3929	1.6088	24.882	0.048	21.027	17.59	196.13	0.0	
3	Strategy_C	25	1.4126666666666672	1.3795	1.6032	25.672	0.04	21.918	17.59	196.13	0.0
4	Strategy_D	25	1.32604	1.296	1.5466	24.759	0.038	21.055	17.59	196.13	0.0	
5	Strategy_E	25	1.5662	1.564	1.7354	39.528	0.041	35.817	17.59	196.13	0.0
6	Strategy_E2	25	1.1645217391304346	1.141	1.3354	20.371	0.034	17.004	17.59	143.69	0.0	
7	Strategy_F	25	1.54084	1.486	1.819	30.14	0.041	26.367	17.59	196.13	0.0
8	Strategy_F2	25	1.2238695652173912	1.227	1.4514	19.832	0.03	16.667	17.59	143.69	0.0	
9	Strategy_G	25	1.5149199999999998	1.501	1.7368000000000001	33.346	0.034	29.526	17.59	196.13	0.0
10	Strategy_G2	25	1.187304347826087	1.141	1.3728	21.354	0.032	17.928	17.59	143.69	0.0	

1	Strategy_D&G2_branchD	25	1.64996	1.612	1.9094000000000002	25.493	0.049	21.271	17.59	196.14	0.0	
1	Strategy_D&G2_branchG2	25	1.5330416666666669	1.517	1.7962000000000002	19.391	0.038	15.335	17.59	143.7	0.0	

1	Strategy_B_run2b	25	1.1199166666666667	1.0875	1.3391000000000002	28.036	0.036	24.783	17.59	83.08	0.0
1	Strategy_D_unescapex05_2b	25	1.1946521739130436	1.181	1.3082	28.787	0.04	25.757	17.59	83.09	0.0

1	Strategy_A_run2	25	1.2832083333333333	1.2825	1.4826	26.492	0.029	22.846	17.59	196.13	0.0	
1	Strategy_B_run2	25	1.2563333333333335	1.2455	1.418	24.576	0.028	21.101	17.59	196.13	0.0
1	Strategy_D_unescapex05_2	25	1.3757199999999998	1.365	1.4538	25.474	0.029	21.851	17.59	196.13	0.0


1	Strategy_B_refined	25	1.2107391304347825	1.196	1.3504	24.221	0.038	20.523	17.59	196.13	0.0	
1	Strategy_B_refined_run2	25	1.2233749999999997	1.187	1.4161000000000001	24.439	0.035	20.803	17.59	196.13	0.0	

1	Strategy_B_refined(consec)	25	1.262	1.1920000000000002	1.4361	23.778	0.032	20.154	17.59	196.13	0.0
1	Strategy_B_refined(isol)	25	1.2148400000000001	1.167	1.4536000000000002	24.578	0.031	20.34	17.59	196.13	0.0

1	Strategy_D_refined(consec)	25	1.3940833333333333	1.3675000000000002	1.6134000000000002	27.133	0.045	23.35	17.59	196.13	0.0
1	Strategy_D_refined(isol)	25	1.2407826086956524	1.235	1.3783999999999998	26.564	0.029	22.91	17.59	196.13	0.0

*/
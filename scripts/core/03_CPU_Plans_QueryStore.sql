/* Validation: EXECUTED-CI | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT TOP (30) DB_NAME(st.dbid) AS database_name,qs.execution_count,
       qs.total_worker_time/1000 AS total_cpu_ms,
       (qs.total_worker_time/NULLIF(qs.execution_count,0))/1000 AS avg_cpu_ms,
       qs.total_elapsed_time/1000 AS total_elapsed_ms,qs.total_logical_reads,
       qs.total_logical_writes,qs.last_execution_time,qs.query_hash,qs.query_plan_hash,
       SUBSTRING(st.text,(qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END-qs.statement_start_offset)/2)+1) AS statement_text,
       qs.plan_handle
FROM sys.dm_exec_query_stats AS qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_worker_time DESC;

SELECT scheduler_id,cpu_id,status,is_online,is_idle,current_tasks_count,runnable_tasks_count,
       current_workers_count,active_workers_count,load_factor
FROM sys.dm_os_schedulers
WHERE status='VISIBLE ONLINE'
ORDER BY scheduler_id;

SELECT DB_NAME(database_id) AS database_name,OBJECT_SCHEMA_NAME(object_id,database_id) AS schema_name,
       OBJECT_NAME(object_id,database_id) AS object_name,cached_time,last_execution_time,
       execution_count,total_worker_time,total_elapsed_time,total_logical_reads,total_logical_writes
FROM sys.dm_exec_procedure_stats
ORDER BY total_worker_time DESC;

SELECT name,actual_state_desc,desired_state_desc,readonly_reason,current_storage_size_mb,
       max_storage_size_mb,query_capture_mode_desc,size_based_cleanup_mode_desc,
       stale_query_threshold_days,data_flush_interval_seconds
FROM sys.database_query_store_options;

/* Validation: EXECUTED-CI | Read-only | Requires VIEW SERVER STATE for complete results */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT @@SERVERNAME AS server_name, @@VERSION AS version_string,
       SERVERPROPERTY('Edition') AS edition, SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('ProductLevel') AS product_level, SERVERPROPERTY('IsHadrEnabled') AS hadr_enabled,
       osi.sqlserver_start_time, osi.cpu_count, osi.scheduler_count,
       CAST(osi.physical_memory_kb / 1024.0 AS decimal(18,1)) AS host_memory_mb
FROM sys.dm_os_sys_info AS osi;

SELECT d.name, d.state_desc, d.recovery_model_desc, d.log_reuse_wait_desc,
       d.page_verify_option_desc, d.user_access_desc, d.is_read_only,
       d.is_auto_close_on, d.is_auto_shrink_on, d.compatibility_level,
       SUSER_SNAME(d.owner_sid) AS owner_name
FROM sys.databases AS d
ORDER BY d.database_id;

SELECT TOP (50) r.session_id, r.blocking_session_id, DB_NAME(r.database_id) AS database_name,
       s.login_name, s.host_name, s.program_name, r.status, r.command,
       r.wait_type, r.wait_time, r.wait_resource, r.cpu_time, r.total_elapsed_time,
       r.logical_reads, r.reads, r.writes, r.open_transaction_count,
       SUBSTRING(t.text,(r.statement_start_offset/2)+1,
         ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
           ELSE r.statement_end_offset END-r.statement_start_offset)/2)+1) AS current_statement,
       t.text AS batch_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id=r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id<>@@SPID
ORDER BY CASE WHEN r.blocking_session_id>0 THEN 0 ELSE 1 END,r.total_elapsed_time DESC;

SELECT TOP (25) wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms,
       wait_time_ms-signal_wait_time_ms AS resource_wait_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE 'SLEEP%' AND wait_type NOT IN
 ('BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP','BROKER_TO_FLUSH',
  'CHECKPOINT_QUEUE','CHKPT','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
  'HADR_LOGCAPTURE_WAIT','HADR_NOTIFICATION_DEQUEUE','HADR_TIMER_TASK','LAZYWRITER_SLEEP',
  'LOGMGR_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','SP_SERVER_DIAGNOSTICS_SLEEP_TASK',
  'SQLTRACE_BUFFER_FLUSH','WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT')
ORDER BY wait_time_ms DESC;

WITH b AS
(
 SELECT database_name,
   MAX(CASE WHEN type='D' AND is_copy_only=0 THEN backup_finish_date END) AS last_full,
   MAX(CASE WHEN type='I' AND is_copy_only=0 THEN backup_finish_date END) AS last_diff,
   MAX(CASE WHEN type='L' THEN backup_finish_date END) AS last_log
 FROM msdb.dbo.backupset GROUP BY database_name
)
SELECT d.name,d.recovery_model_desc,b.last_full,b.last_diff,b.last_log,
       DATEDIFF(hour,b.last_full,SYSDATETIME()) AS hours_since_full,
       CASE WHEN d.recovery_model_desc<>'SIMPLE' THEN DATEDIFF(minute,b.last_log,SYSDATETIME()) END AS minutes_since_log
FROM sys.databases AS d LEFT JOIN b ON b.database_name=d.name
WHERE d.database_id>4 AND d.source_database_id IS NULL
ORDER BY b.last_full;

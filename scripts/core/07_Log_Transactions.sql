/* Validation: EXECUTED-CI | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT d.name,d.recovery_model_desc,d.log_reuse_wait_desc,
       ls.total_log_size_mb,ls.active_log_size_mb,
       CAST(100.0*ls.active_log_size_mb/NULLIF(ls.total_log_size_mb,0) AS decimal(6,2)) AS active_log_pct,
       ls.log_truncation_holdup_reason,ls.log_since_last_log_backup_mb,
       ls.log_backup_time,ls.total_vlf_count
FROM sys.databases AS d
CROSS APPLY sys.dm_db_log_stats(d.database_id) AS ls
WHERE d.state_desc='ONLINE'
ORDER BY active_log_pct DESC,d.name;

SELECT DB_NAME(dt.database_id) AS database_name,st.session_id,at.transaction_id,
       at.name AS transaction_name,at.transaction_begin_time,at.transaction_type,
       at.transaction_state,dt.database_transaction_log_bytes_used,
       dt.database_transaction_log_bytes_reserved,
       s.login_name,s.host_name,s.program_name,r.status,r.command,r.wait_type,r.wait_resource,
       txt.text AS current_or_recent_sql
FROM sys.dm_tran_active_transactions AS at
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id=at.transaction_id
JOIN sys.dm_tran_database_transactions AS dt ON dt.transaction_id=at.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id=st.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id=s.session_id
LEFT JOIN sys.dm_exec_connections AS c ON c.session_id=s.session_id
OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle,c.most_recent_sql_handle)) AS txt
WHERE s.is_user_process=1
ORDER BY at.transaction_begin_time;

SELECT DB_NAME(mf.database_id) AS database_name,mf.name,mf.physical_name,mf.size/128.0 AS size_mb,
       mf.is_percent_growth,mf.growth,
       CASE WHEN mf.is_percent_growth=1 THEN CONCAT(mf.growth,'%') ELSE CONCAT(mf.growth/128,' MB') END AS growth_setting
FROM sys.master_files AS mf WHERE mf.type=1 ORDER BY database_name,mf.file_id;

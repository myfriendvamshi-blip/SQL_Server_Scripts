/* Validation: EXECUTED-CI | Collector is read-only; XE creation gated by @CreateXE */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @CreateXE bit=0;

SELECT s.session_id,r.blocking_session_id,s.status AS session_status,r.status AS request_status,
       s.open_transaction_count,s.login_name,s.host_name,s.program_name,
       DB_NAME(COALESCE(r.database_id,s.database_id)) AS database_name,
       r.wait_type,r.wait_time,r.wait_resource,at.transaction_begin_time,
       DATEDIFF(second,at.transaction_begin_time,SYSDATETIME()) AS transaction_age_seconds,
       txt.text AS most_recent_sql
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id=s.session_id
LEFT JOIN sys.dm_tran_session_transactions AS st ON st.session_id=s.session_id
LEFT JOIN sys.dm_tran_active_transactions AS at ON at.transaction_id=st.transaction_id
LEFT JOIN sys.dm_exec_connections AS c ON c.session_id=s.session_id
OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle,c.most_recent_sql_handle)) AS txt
WHERE s.is_user_process=1 AND
 (r.blocking_session_id>0 OR EXISTS(SELECT 1 FROM sys.dm_exec_requests x WHERE x.blocking_session_id=s.session_id))
ORDER BY at.transaction_begin_time,s.session_id;

SELECT tl.request_session_id,tl.resource_type,tl.resource_database_id,DB_NAME(tl.resource_database_id) AS database_name,
       tl.resource_associated_entity_id,tl.request_mode,tl.request_status,tl.request_owner_type
FROM sys.dm_tran_locks AS tl
WHERE tl.request_session_id IN
 (SELECT session_id FROM sys.dm_exec_requests WHERE blocking_session_id>0
  UNION SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id>0)
ORDER BY tl.request_session_id,tl.resource_type,tl.request_mode;

IF @CreateXE=1 AND NOT EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name=N'DBA_Deadlocks')
BEGIN
 EXEC(N'CREATE EVENT SESSION [DBA_Deadlocks] ON SERVER
 ADD EVENT sqlserver.xml_deadlock_report
 ADD TARGET package0.event_file(SET filename=N''DBA_Deadlocks'',max_file_size=(100),max_rollover_files=(5))
 WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=5 SECONDS,STARTUP_STATE=ON);');
 ALTER EVENT SESSION [DBA_Deadlocks] ON SERVER STATE=START;
END;

-- Existing deadlocks in system_health; no file path assumption.
;WITH x AS
(
 SELECT CAST(t.target_data AS xml) AS target_xml
 FROM sys.dm_xe_session_targets AS t
 JOIN sys.dm_xe_sessions AS s ON s.address=t.event_session_address
 WHERE s.name=N'system_health' AND t.target_name=N'ring_buffer'
)
SELECT n.value('@timestamp','datetime2') AS event_time_utc,
       n.query('(data/value/deadlock)[1]') AS deadlock_xml
FROM x CROSS APPLY target_xml.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS q(n)
ORDER BY event_time_utc DESC;

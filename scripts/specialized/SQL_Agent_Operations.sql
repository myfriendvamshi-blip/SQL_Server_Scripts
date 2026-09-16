/* Validation: PARSED-CI + LAB-REQUIRED | Read-only | Requires SQL Server Agent/msdb */
SET NOCOUNT ON;
SELECT j.name,j.enabled,SUSER_SNAME(j.owner_sid) AS owner_name,c.name AS category_name,
       s.name AS schedule_name,s.enabled AS schedule_enabled,
       CASE js.next_run_date WHEN 0 THEN NULL ELSE msdb.dbo.agent_datetime(js.next_run_date,js.next_run_time) END AS next_run
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.syscategories AS c ON c.category_id=j.category_id
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id=j.job_id
LEFT JOIN msdb.dbo.sysschedules AS s ON s.schedule_id=js.schedule_id
ORDER BY j.name,s.name;

SELECT TOP (200) j.name,h.step_id,h.step_name,msdb.dbo.agent_datetime(h.run_date,h.run_time) AS run_datetime,
       h.run_status,h.run_duration,h.sql_severity,h.sql_message_id,h.message
FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id=h.job_id
WHERE h.run_status IN (0,2,3) OR h.sql_severity>=16
ORDER BY run_datetime DESC;

SELECT ja.job_id,j.name,ja.start_execution_date,ja.stop_execution_date,
       DATEDIFF(minute,ja.start_execution_date,SYSDATETIME()) AS running_minutes,
       ISNULL(NULLIF(ja.last_executed_step_id,0)+1,1) AS probable_current_step
FROM msdb.dbo.sysjobactivity AS ja
JOIN msdb.dbo.sysjobs AS j ON j.job_id=ja.job_id
WHERE ja.session_id=(SELECT MAX(session_id) FROM msdb.dbo.syssessions)
  AND ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL;

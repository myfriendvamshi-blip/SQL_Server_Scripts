/* Validation: EXECUTED-CI | Read-only; generated commands require review */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT DB_NAME(mf.database_id) AS database_name,mf.file_id,mf.type_desc,mf.name,mf.physical_name,
       CAST(mf.size/128.0 AS decimal(18,2)) AS size_mb,
       CASE WHEN mf.max_size=-1 THEN NULL ELSE CAST(mf.max_size/128.0 AS decimal(18,2)) END AS max_size_mb,
       mf.is_percent_growth,mf.growth,vs.volume_mount_point,
       CAST(vs.total_bytes/1073741824.0 AS decimal(18,2)) AS volume_total_gb,
       CAST(vs.available_bytes/1073741824.0 AS decimal(18,2)) AS volume_free_gb,
       CAST(100.0*vs.available_bytes/NULLIF(vs.total_bytes,0) AS decimal(6,2)) AS volume_free_pct
FROM sys.master_files AS mf CROSS APPLY sys.dm_os_volume_stats(mf.database_id,mf.file_id) AS vs
ORDER BY volume_free_pct,database_name,mf.file_id;

SELECT d.name,d.recovery_model_desc,d.log_reuse_wait_desc,
       CAST(SUM(CASE WHEN mf.type=0 THEN mf.size END)/128.0 AS decimal(18,2)) AS data_size_mb,
       CAST(SUM(CASE WHEN mf.type=1 THEN mf.size END)/128.0 AS decimal(18,2)) AS log_size_mb
FROM sys.databases AS d JOIN sys.master_files AS mf ON mf.database_id=d.database_id
GROUP BY d.name,d.recovery_model_desc,d.log_reuse_wait_desc ORDER BY d.name;

WITH h AS
(
 SELECT bs.database_name,bs.type,bs.backup_start_date,bs.backup_finish_date,bs.first_lsn,bs.last_lsn,
        bs.checkpoint_lsn,bs.database_backup_lsn,bs.is_copy_only,bs.has_backup_checksums,
        bs.backup_size,bs.compressed_backup_size,
        ROW_NUMBER() OVER(PARTITION BY bs.database_name,bs.type ORDER BY bs.backup_finish_date DESC) AS rn
 FROM msdb.dbo.backupset AS bs
)
SELECT * FROM h WHERE rn<=10 ORDER BY database_name,backup_finish_date DESC;

SELECT r.session_id,r.command,DB_NAME(r.database_id) AS database_name,r.status,r.percent_complete,
       r.start_time,r.total_elapsed_time/1000 AS elapsed_seconds,
       r.estimated_completion_time/1000 AS remaining_seconds,
       DATEADD(ms,r.estimated_completion_time,GETDATE()) AS estimated_finish,r.wait_type,r.wait_resource
FROM sys.dm_exec_requests AS r
WHERE r.command LIKE 'BACKUP%' OR r.command LIKE 'RESTORE%' OR r.command LIKE 'DBCC%';

SELECT DB_NAME(database_id) AS database_name,name AS logical_name,type_desc,physical_name,state_desc,size*8/1024 AS size_mb
FROM sys.master_files ORDER BY DB_NAME(database_id),file_id;

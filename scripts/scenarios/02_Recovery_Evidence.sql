/* READ-ONLY, SQL Server 2022. Run in the database whose history you need.
   Requires SELECT on msdb dbo.backupset, backupmediafamily, restorehistory.
   Candidate inventory, NOT an executable or certified restore chain.
   No RESTORE, BACKUP, file access, tail-log, or recovery state changes. */
SET NOCOUNT ON;
DECLARE @Database sysname=DB_NAME();
DROP TABLE IF EXISTS #BackupEvidence;
SELECT b.backup_set_id,b.media_set_id,b.position,b.database_name,b.type,
       b.backup_start_date,b.backup_finish_date,b.first_lsn,b.last_lsn,
       b.checkpoint_lsn,b.database_backup_lsn,b.differential_base_lsn,
       b.differential_base_guid,b.backup_set_uuid,b.family_guid,
       b.first_recovery_fork_guid,b.last_recovery_fork_guid,b.fork_point_lsn,
       b.is_copy_only,b.has_backup_checksums,b.is_damaged,b.has_bulk_logged_data,
       b.has_incomplete_metadata,b.recovery_model,b.key_algorithm,b.encryptor_thumbprint,
       CASE WHEN b.is_damaged=1 THEN N'DAMAGED_REVIEW'
            WHEN b.has_incomplete_metadata=1 THEN N'INCOMPLETE_METADATA_REVIEW'
            WHEN b.first_recovery_fork_guid<>b.last_recovery_fork_guid THEN N'FORK_TRANSITION_REVIEW'
            ELSE N'INVENTORY_ONLY_NOT_VERIFIED' END AS assessment
INTO #BackupEvidence
FROM msdb.dbo.backupset AS b WHERE b.database_name=@Database;
SELECT SYSUTCDATETIME() AS captured_utc,@@SERVERNAME AS server_name,@Database AS database_name,
       N'Backup timestamps are server-local; establish timezone before STOPAT. History can be pruned or stale.' AS caveat;
SELECT * FROM #BackupEvidence ORDER BY backup_finish_date,backup_set_id;
SELECT e.backup_set_id,m.family_sequence_number,m.mirror,m.device_type,m.physical_device_name
FROM #BackupEvidence AS e JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id=e.media_set_id
ORDER BY e.backup_set_id,m.mirror,m.family_sequence_number;
/* A differential base is identified by UUID, not by latest filename/date. */
SELECT d.backup_set_id AS differential_id,f.backup_set_id AS base_full_id,
       CASE WHEN f.backup_set_id IS NULL THEN N'BASE_NOT_IN_HISTORY_OR_MULTIBASE'
            ELSE N'BASE_METADATA_MATCH_MEDIA_STILL_UNVERIFIED' END AS base_assessment
FROM #BackupEvidence AS d
LEFT JOIN #BackupEvidence AS f ON f.backup_set_uuid=d.differential_base_guid AND f.type='D' AND f.is_copy_only=0
WHERE d.type='I';
SELECT restore_history_id,restore_date,destination_database_name,backup_set_id,restore_type,
       replace,recovery,stop_at FROM msdb.dbo.restorehistory
WHERE destination_database_name=@Database ORDER BY restore_history_id;
GO

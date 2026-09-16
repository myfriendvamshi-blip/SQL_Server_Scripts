/* DESTRUCTIVE LAB ONLY. Fixed names, isolated CI, no REPLACE and no real destinations.
   Exercises full + differential + log + STOPAT and validates restored row contents.
   Does not prove damaged tail-log, missing stripe, fork transition, or TDE recovery. */
:on error exit
USE master;
IF N'$(DisposableLab)'<>N'YES' THROW 51600,'Disposable CI opt-in required.',1;
IF DB_ID(N'DBA_Toolkit_PITR_Source') IS NOT NULL OR DB_ID(N'DBA_Toolkit_PITR_Restore') IS NOT NULL
 THROW 51601,'Fixture collision; refusing overwrite.',1;
CREATE DATABASE DBA_Toolkit_PITR_Source;
ALTER DATABASE DBA_Toolkit_PITR_Source SET RECOVERY FULL;
GO
USE DBA_Toolkit_PITR_Source;
CREATE TABLE dbo.Marker(id int NOT NULL PRIMARY KEY);
INSERT dbo.Marker VALUES(1);
BACKUP DATABASE DBA_Toolkit_PITR_Source TO DISK='/var/opt/mssql/backup/phase1_full.bak' WITH INIT,CHECKSUM;
INSERT dbo.Marker VALUES(2);
BACKUP DATABASE DBA_Toolkit_PITR_Source TO DISK='/var/opt/mssql/backup/phase1_diff.bak' WITH INIT,DIFFERENTIAL,CHECKSUM;
WAITFOR DELAY '00:00:02';
/* STOPAT uses the same server-local clock as transaction log timestamps. */
DECLARE @StopAt datetime=GETDATE();
WAITFOR DELAY '00:00:02';
INSERT dbo.Marker VALUES(3);
BACKUP LOG DBA_Toolkit_PITR_Source TO DISK='/var/opt/mssql/backup/phase1_log.trn' WITH INIT,CHECKSUM;
/* Session-scoped target survives GO/includes without persistent metadata. */
CREATE TABLE #PitrTarget(stop_at datetime NOT NULL);
INSERT #PitrTarget VALUES(@StopAt);
GO
:r scripts/scenarios/02_Recovery_Evidence.sql
IF (SELECT COUNT(*) FROM #BackupEvidence WHERE type IN ('D','I','L'))<>3
 THROW 51602,'Expected full/differential/log inventory.',1;
IF NOT EXISTS(SELECT 1 FROM #BackupEvidence d JOIN #BackupEvidence f
 ON f.backup_set_uuid=d.differential_base_guid WHERE d.type='I' AND f.type='D' AND f.is_copy_only=0)
 THROW 51603,'Differential base GUID relationship missing.',1;
IF EXISTS(SELECT 1 FROM #BackupEvidence WHERE has_backup_checksums<>1 OR is_damaged=1)
 THROW 51604,'Unexpected backup checksum/damage flags.',1;
USE master;
RESTORE VERIFYONLY FROM DISK='/var/opt/mssql/backup/phase1_full.bak' WITH CHECKSUM;
RESTORE DATABASE DBA_Toolkit_PITR_Restore FROM DISK='/var/opt/mssql/backup/phase1_full.bak'
 WITH NORECOVERY,CHECKSUM,
 MOVE 'DBA_Toolkit_PITR_Source' TO '/var/opt/mssql/data/phase1_pitr_restore.mdf',
 MOVE 'DBA_Toolkit_PITR_Source_log' TO '/var/opt/mssql/data/phase1_pitr_restore.ldf';
RESTORE DATABASE DBA_Toolkit_PITR_Restore FROM DISK='/var/opt/mssql/backup/phase1_diff.bak' WITH NORECOVERY,CHECKSUM;
DECLARE @StopAt datetime=(SELECT stop_at FROM #PitrTarget);
RESTORE LOG DBA_Toolkit_PITR_Restore FROM DISK='/var/opt/mssql/backup/phase1_log.trn' WITH RECOVERY,CHECKSUM,STOPAT=@StopAt;
IF (SELECT COUNT(*) FROM DBA_Toolkit_PITR_Restore.dbo.Marker)<>2
 OR EXISTS(SELECT 1 FROM DBA_Toolkit_PITR_Restore.dbo.Marker WHERE id=3)
 THROW 51605,'STOPAT did not recover expected pre-target rows only.',1;
DBCC CHECKDB(N'DBA_Toolkit_PITR_Restore') WITH NO_INFOMSGS,ALL_ERRORMSGS;
GO
USE DBA_Toolkit_PITR_Restore;
:r scripts/scenarios/02_Recovery_Evidence.sql
IF (SELECT COUNT(*) FROM msdb.dbo.restorehistory WHERE destination_database_name=DB_NAME())<>3
 THROW 51606,'Full/differential/log restore history incomplete.',1;
SELECT N'PASS: full + differential + log STOPAT, row assertions and CHECKDB' AS result;
USE master;
DROP DATABASE DBA_Toolkit_PITR_Restore;
DROP DATABASE DBA_Toolkit_PITR_Source;
GO

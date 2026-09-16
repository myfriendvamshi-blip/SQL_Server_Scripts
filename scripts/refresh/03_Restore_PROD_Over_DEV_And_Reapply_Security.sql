/*
  Run on DEV during an approved outage. SQLCMD mode must be enabled.

  Prerequisites:
  - A READY SnapshotId returned by step 01.
  - The PROD backup is readable by the DEV SQL Server service account.
  - DEV application connections and jobs are stopped.
  - DataPath and LogPath exist and include a trailing slash/backslash.

  EXPERIMENTAL DESTRUCTIVE TEMPLATE: see docs/REFRESH_SAFETY_REVIEW.md.
  SINGLE_USER is not an access-control boundary. Keep the destination externally isolated.
  Replay failure intends to leave SINGLE_USER, but failures outside apply can differ;
  CHECKDB below runs AFTER apply returns MULTI_USER. Not production certified.
*/
:setvar DevDatabase "CHANGE_ME_DEV_DATABASE"
:setvar SnapshotId "00000000-0000-0000-0000-000000000000"
:setvar BackupFile "D:\SQLBackups\CHANGE_ME_PROD_DATABASE_COPY_ONLY.bak"
:setvar DataPath "D:\SQLData\"
:setvar LogPath "E:\SQLLogs\"

USE master;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @TargetDatabase sysname=N'$(DevDatabase)',
        @SnapshotId uniqueidentifier=TRY_CONVERT(uniqueidentifier,N'$(SnapshotId)'),
        @BackupFile nvarchar(4000)=N'$(BackupFile)',
        @DataPath nvarchar(4000)=N'$(DataPath)',
        @LogPath nvarchar(4000)=N'$(LogPath)',
        @Sql nvarchar(max),@Moves nvarchar(max);

IF @TargetDatabase=N'CHANGE_ME_DEV_DATABASE' OR @BackupFile LIKE N'%CHANGE_ME%'
   OR @SnapshotId IS NULL OR @SnapshotId='00000000-0000-0000-0000-000000000000'
    THROW 51220, 'Set DevDatabase, SnapshotId, BackupFile, DataPath, and LogPath.', 1;
IF DB_ID(N'DBA_Admin') IS NULL
    THROW 51221, 'DBA_Admin security snapshot engine is not installed.', 1;
IF NOT EXISTS
(
 SELECT 1 FROM DBA_Admin.dbo.DevSecuritySnapshot
 WHERE snapshot_id=@SnapshotId AND database_name=@TargetDatabase AND status IN (N'READY',N'FAILED')
)
    THROW 51222, 'The SnapshotId is not READY or was captured from a different DEV database.', 1;

SET @Sql=N'RESTORE VERIFYONLY FROM DISK=N'''+REPLACE(@BackupFile,N'''',N'''''')+N''' WITH CHECKSUM;';
EXEC master.sys.sp_executesql @Sql;

DROP TABLE IF EXISTS #FileList;
CREATE TABLE #FileList
(
 LogicalName nvarchar(128),PhysicalName nvarchar(260),[Type] char(1),FileGroupName nvarchar(128) NULL,
 Size numeric(20,0),MaxSize numeric(20,0),FileID bigint,CreateLSN numeric(25,0),DropLSN numeric(25,0) NULL,
 UniqueID uniqueidentifier,ReadOnlyLSN numeric(25,0) NULL,ReadWriteLSN numeric(25,0) NULL,
 BackupSizeInBytes bigint,SourceBlockSize int,FileGroupID int,LogGroupGUID uniqueidentifier NULL,
 DifferentialBaseLSN numeric(25,0) NULL,DifferentialBaseGUID uniqueidentifier NULL,IsReadOnly bit,IsPresent bit,
 TDEThumbprint varbinary(32) NULL,SnapshotURL nvarchar(360) NULL
);
SET @Sql=N'RESTORE FILELISTONLY FROM DISK=N'''+REPLACE(@BackupFile,N'''',N'''''')+N''';';
INSERT #FileList EXEC master.sys.sp_executesql @Sql;

IF NOT EXISTS (SELECT 1 FROM #FileList WHERE [Type]='D') OR NOT EXISTS (SELECT 1 FROM #FileList WHERE [Type]='L')
    THROW 51223, 'The backup file list does not contain both data and log files.', 1;

SELECT @Moves=STRING_AGG(
  N'MOVE N'''+REPLACE(LogicalName,N'''',N'''''')+N''' TO N'''
  +REPLACE(CASE WHEN [Type]='L' THEN @LogPath ELSE @DataPath END,N'''',N'''''')
  +REPLACE(@TargetDatabase,N'''',N'''''')+N'_'
  +CONVERT(nvarchar(20),FileID)
  +CASE WHEN [Type]='L' THEN N'.ldf' ELSE N'.mdf' END+N'''',N','+CHAR(10))
FROM #FileList;

IF DB_ID(@TargetDatabase) IS NOT NULL
BEGIN
 SET @Sql=N'ALTER DATABASE '+QUOTENAME(@TargetDatabase)+N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
 EXEC master.sys.sp_executesql @Sql;
END;

BEGIN TRY
 SET @Sql=N'RESTORE DATABASE '+QUOTENAME(@TargetDatabase)+N'
 FROM DISK=N'''+REPLACE(@BackupFile,N'''',N'''''')+N'''
 WITH REPLACE,CHECKSUM,RECOVERY,STATS=5,'+CHAR(10)+@Moves+N';';
 EXEC master.sys.sp_executesql @Sql;

 /* The procedure immediately returns the restored database to SINGLE_USER, removes
    restored PROD security, replays DEV security, validates counts, and only then opens it. */
 EXEC DBA_Admin.dbo.usp_ApplyDevDatabaseSecurity
      @DatabaseName=@TargetDatabase,
      @SnapshotId=@SnapshotId;

 SET @Sql=N'DBCC CHECKDB('+QUOTENAME(@TargetDatabase,N'''')+N') WITH NO_INFOMSGS,ALL_ERRORMSGS;';
 EXEC master.sys.sp_executesql @Sql;
END TRY
BEGIN CATCH
 /* Never force MULTI_USER here. A failed security replay intentionally remains isolated. */
 THROW;
END CATCH;

SELECT d.name,d.state_desc,d.user_access_desc,d.recovery_model_desc,d.compatibility_level,
       SUSER_SNAME(d.owner_sid) AS database_owner
FROM sys.databases AS d WHERE d.name=@TargetDatabase;
GO

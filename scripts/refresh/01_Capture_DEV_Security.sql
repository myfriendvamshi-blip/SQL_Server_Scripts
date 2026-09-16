/*
  Run on DEV before overwriting the database.
  Requires scripts/refresh/00_Install_DevSecuritySnapshot.sql to be installed.
  SQLCMD mode must be enabled in SSMS/sqlcmd.
*/
:setvar DevDatabase "CHANGE_ME_DEV_DATABASE"

USE DBA_Admin;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DatabaseName sysname=N'$(DevDatabase)',@SnapshotId uniqueidentifier;
IF @DatabaseName=N'CHANGE_ME_DEV_DATABASE'
    THROW 51200, 'Set the DevDatabase SQLCMD variable.', 1;

EXEC dbo.usp_CaptureDevDatabaseSecurity
     @DatabaseName=@DatabaseName,
     @SnapshotId=@SnapshotId OUTPUT;

SELECT @SnapshotId AS snapshot_id_to_use_during_restore;
GO

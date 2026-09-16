/* LAB ONLY: verifies login SID mapping, roles and explicit permissions across restore. */
USE master;
SET NOCOUNT ON;
IF SUSER_ID(N'DBA_Toolkit_TestLogin') IS NOT NULL DROP LOGIN DBA_Toolkit_TestLogin;
CREATE LOGIN DBA_Toolkit_TestLogin WITH PASSWORD=N'Strong_Test_Only!2026',CHECK_POLICY=OFF;
GO
USE DBA_Toolkit_Lab;
CREATE USER DBA_Toolkit_TestLogin FOR LOGIN DBA_Toolkit_TestLogin;
ALTER ROLE db_datareader ADD MEMBER DBA_Toolkit_TestLogin;
GRANT UPDATE ON dbo.Account TO DBA_Toolkit_TestLogin;
GO
USE master;
BACKUP DATABASE DBA_Toolkit_Lab TO DISK=N'/var/opt/mssql/backup/DBA_Toolkit_Lab.bak'
 WITH INIT,COPY_ONLY,COMPRESSION,CHECKSUM,STATS=10;
RESTORE VERIFYONLY FROM DISK=N'/var/opt/mssql/backup/DBA_Toolkit_Lab.bak' WITH CHECKSUM;

DECLARE @data sysname=(SELECT name FROM DBA_Toolkit_Lab.sys.database_files WHERE type=0),
        @log sysname=(SELECT name FROM DBA_Toolkit_Lab.sys.database_files WHERE type=1);
IF DB_ID(N'DBA_Toolkit_Lab_Restore') IS NOT NULL
BEGIN ALTER DATABASE DBA_Toolkit_Lab_Restore SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DBA_Toolkit_Lab_Restore; END;
DECLARE @restore nvarchar(max)=N'RESTORE DATABASE DBA_Toolkit_Lab_Restore
 FROM DISK=N''/var/opt/mssql/backup/DBA_Toolkit_Lab.bak''
 WITH MOVE N'''+REPLACE(@data,'''','''''')+N''' TO N''/var/opt/mssql/data/DBA_Toolkit_Lab_Restore.mdf'',
      MOVE N'''+REPLACE(@log,'''','''''')+N''' TO N''/var/opt/mssql/data/DBA_Toolkit_Lab_Restore_log.ldf'',
      CHECKSUM,RECOVERY,STATS=10;';
EXEC sys.sp_executesql @restore;

DECLARE @orphan_count int,@role_count int,@permission_count int,@q nvarchar(max)=N'
USE DBA_Toolkit_Lab_Restore;
SELECT @o=COUNT(*) FROM sys.database_principals dp
LEFT JOIN master.sys.server_principals sp ON sp.sid=dp.sid
WHERE dp.name=N''DBA_Toolkit_TestLogin'' AND sp.sid IS NULL;
SELECT @r=COUNT(*) FROM sys.database_role_members rm
JOIN sys.database_principals rolep ON rolep.principal_id=rm.role_principal_id
JOIN sys.database_principals memberp ON memberp.principal_id=rm.member_principal_id
WHERE rolep.name=N''db_datareader'' AND memberp.name=N''DBA_Toolkit_TestLogin'';
SELECT @p=COUNT(*) FROM sys.database_permissions p
JOIN sys.database_principals dp ON dp.principal_id=p.grantee_principal_id
WHERE dp.name=N''DBA_Toolkit_TestLogin'' AND p.permission_name=N''UPDATE'' AND p.state IN (''G'',''W'');';
EXEC sys.sp_executesql @q,N'@o int OUTPUT,@r int OUTPUT,@p int OUTPUT',@o=@orphan_count OUTPUT,@r=@role_count OUTPUT,@p=@permission_count OUTPUT;
IF @orphan_count<>0 THROW 51000,'Restored user is orphaned.',1;
IF @role_count<>1 THROW 51001,'Role membership was not preserved.',1;
IF @permission_count<>1 THROW 51002,'Explicit permission was not preserved.',1;
DBCC CHECKDB(N'DBA_Toolkit_Lab_Restore') WITH NO_INFOMSGS,ALL_ERRORMSGS;
SELECT N'PASS' AS test_result,@orphan_count AS orphan_count,@role_count AS role_count,@permission_count AS permission_count;
GO

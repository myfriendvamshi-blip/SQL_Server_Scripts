/*
  Run on PROD. SQLCMD mode must be enabled.
  COPY_ONLY avoids changing the differential base. The backup must be copied to a path
  readable by the DEV SQL Server service account before running step 03.
*/
:setvar ProdDatabase "CHANGE_ME_PROD_DATABASE"
:setvar BackupFile "D:\SQLBackups\CHANGE_ME_PROD_DATABASE_COPY_ONLY.bak"

USE master;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DatabaseName sysname=N'$(ProdDatabase)',
        @BackupFile nvarchar(4000)=N'$(BackupFile)',
        @Sql nvarchar(max);

IF @DatabaseName=N'CHANGE_ME_PROD_DATABASE' OR @BackupFile LIKE N'%CHANGE_ME%'
    THROW 51210, 'Set ProdDatabase and BackupFile SQLCMD variables.', 1;
IF DB_ID(@DatabaseName) IS NULL OR DB_ID(@DatabaseName)<=4
    THROW 51211, 'The production source database does not exist or is a system database.', 1;

SET @Sql=N'BACKUP DATABASE '+QUOTENAME(@DatabaseName)+N'
 TO DISK=N'''+REPLACE(@BackupFile,N'''',N'''''')+N'''
 WITH COPY_ONLY,COMPRESSION,CHECKSUM,INIT,STATS=5;';
EXEC master.sys.sp_executesql @Sql;

SET @Sql=N'RESTORE VERIFYONLY FROM DISK=N'''+REPLACE(@BackupFile,N'''',N'''''')+N''' WITH CHECKSUM;';
EXEC master.sys.sp_executesql @Sql;
GO

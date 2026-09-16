/* LAB ONLY: proves PROD security is removed and the saved DEV security is restored. */
USE master;
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_ID(N'DBA_Toolkit_Refresh_DEV') IS NOT NULL
BEGIN ALTER DATABASE DBA_Toolkit_Refresh_DEV SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DBA_Toolkit_Refresh_DEV; END;
IF DB_ID(N'DBA_Toolkit_Refresh_PROD') IS NOT NULL
BEGIN ALTER DATABASE DBA_Toolkit_Refresh_PROD SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DBA_Toolkit_Refresh_PROD; END;
IF SUSER_ID(N'DBA_Toolkit_DEV_Login') IS NOT NULL DROP LOGIN DBA_Toolkit_DEV_Login;
IF SUSER_ID(N'DBA_Toolkit_PROD_Login') IS NOT NULL DROP LOGIN DBA_Toolkit_PROD_Login;

CREATE LOGIN DBA_Toolkit_DEV_Login WITH PASSWORD=N'Dev_Test_Only!2026',CHECK_POLICY=OFF;
CREATE LOGIN DBA_Toolkit_PROD_Login WITH PASSWORD=N'Prod_Test_Only!2026',CHECK_POLICY=OFF;
CREATE DATABASE DBA_Toolkit_Refresh_DEV;
CREATE DATABASE DBA_Toolkit_Refresh_PROD;
GO

USE DBA_Toolkit_Refresh_DEV;
CREATE TABLE dbo.OrderData(OrderId int NOT NULL PRIMARY KEY,Payload nvarchar(100) NOT NULL);
CREATE SCHEMA DevOwned AUTHORIZATION dbo;
CREATE USER DevAlias FOR LOGIN DBA_Toolkit_DEV_Login WITH DEFAULT_SCHEMA=DevOwned;
ALTER AUTHORIZATION ON SCHEMA::DevOwned TO DevAlias;
CREATE ROLE DevReaders AUTHORIZATION DevAlias;
ALTER ROLE DevReaders ADD MEMBER DevAlias;
ALTER ROLE db_datareader ADD MEMBER DevAlias;
GRANT SELECT ON OBJECT::dbo.OrderData TO DevReaders;
DENY DELETE ON OBJECT::dbo.OrderData TO DevAlias;
GRANT UPDATE ON OBJECT::dbo.OrderData (Payload) TO DevAlias;
GRANT SELECT TO public;
GO

USE DBA_Toolkit_Refresh_PROD;
CREATE TABLE dbo.OrderData(OrderId int NOT NULL PRIMARY KEY,Payload nvarchar(100) NOT NULL);
INSERT dbo.OrderData VALUES(1,N'PROD DATA');
CREATE SCHEMA DevOwned AUTHORIZATION dbo;
CREATE USER DBA_Toolkit_PROD_Login FOR LOGIN DBA_Toolkit_PROD_Login;
ALTER AUTHORIZATION ON SCHEMA::DevOwned TO DBA_Toolkit_PROD_Login;
CREATE ROLE ProdOperators AUTHORIZATION DBA_Toolkit_PROD_Login;
ALTER ROLE ProdOperators ADD MEMBER DBA_Toolkit_PROD_Login;
GRANT CONTROL TO ProdOperators;
GRANT DELETE TO public;
ALTER AUTHORIZATION ON OBJECT::dbo.OrderData TO DBA_Toolkit_PROD_Login;
GO

USE DBA_Admin;
DECLARE @SnapshotId uniqueidentifier;
EXEC dbo.usp_CaptureDevDatabaseSecurity
  @DatabaseName=N'DBA_Toolkit_Refresh_DEV',@SnapshotId=@SnapshotId OUTPUT;

USE master;
BACKUP DATABASE DBA_Toolkit_Refresh_PROD
 TO DISK=N'/var/opt/mssql/backup/DBA_Toolkit_Refresh_PROD.bak'
 WITH INIT,COPY_ONLY,COMPRESSION,CHECKSUM;
RESTORE VERIFYONLY FROM DISK=N'/var/opt/mssql/backup/DBA_Toolkit_Refresh_PROD.bak' WITH CHECKSUM;

DECLARE @DataLogical sysname=(SELECT name FROM DBA_Toolkit_Refresh_PROD.sys.database_files WHERE type=0),
        @LogLogical sysname=(SELECT name FROM DBA_Toolkit_Refresh_PROD.sys.database_files WHERE type=1),
        @Restore nvarchar(max);
ALTER DATABASE DBA_Toolkit_Refresh_DEV SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
SET @Restore=N'RESTORE DATABASE DBA_Toolkit_Refresh_DEV
 FROM DISK=N''/var/opt/mssql/backup/DBA_Toolkit_Refresh_PROD.bak''
 WITH REPLACE,CHECKSUM,RECOVERY,
 MOVE N'''+REPLACE(@DataLogical,N'''',N'''''')+N''' TO N''/var/opt/mssql/data/DBA_Toolkit_Refresh_DEV.mdf'',
 MOVE N'''+REPLACE(@LogLogical,N'''',N'''''')+N''' TO N''/var/opt/mssql/data/DBA_Toolkit_Refresh_DEV_log.ldf'';';
EXEC master.sys.sp_executesql @Restore;

EXEC DBA_Admin.dbo.usp_ApplyDevDatabaseSecurity
  @DatabaseName=N'DBA_Toolkit_Refresh_DEV',@SnapshotId=@SnapshotId;

DECLARE @ProdUsers int,@ProdRoles int,@DevUsers int,@DevRoles int,@Memberships int,
        @DevPermissions int,@BadPublicDelete int,@GoodPublicSelect int,@SchemaOwner sysname,@RowCount int;
DECLARE @Assert nvarchar(max)=N'
USE DBA_Toolkit_Refresh_DEV;
SELECT @ProdUsersOut=COUNT(*) FROM sys.database_principals WHERE name=N''DBA_Toolkit_PROD_Login'';
SELECT @ProdRolesOut=COUNT(*) FROM sys.database_principals WHERE name=N''ProdOperators'';
SELECT @DevUsersOut=COUNT(*) FROM sys.database_principals WHERE name=N''DevAlias'' AND SUSER_SNAME(sid)=N''DBA_Toolkit_DEV_Login'';
SELECT @DevRolesOut=COUNT(*) FROM sys.database_principals WHERE name=N''DevReaders'' AND type=''R'';
SELECT @MembershipsOut=COUNT(*)
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id=rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id=rm.member_principal_id
WHERE m.name=N''DevAlias'' AND r.name IN (N''DevReaders'',N''db_datareader'');
SELECT @DevPermissionsOut=COUNT(*)
FROM sys.database_permissions AS p JOIN sys.database_principals AS g ON g.principal_id=p.grantee_principal_id
WHERE (g.name=N''DevReaders'' AND p.permission_name=N''SELECT'' AND p.state=''G'')
   OR (g.name=N''DevAlias'' AND p.permission_name=N''DELETE'' AND p.state=''D'')
   OR (g.name=N''DevAlias'' AND p.permission_name=N''UPDATE'' AND p.state=''G'' AND p.minor_id>0);
SELECT @BadPublicDeleteOut=COUNT(*)
FROM sys.database_permissions AS p JOIN sys.database_principals AS g ON g.principal_id=p.grantee_principal_id
WHERE g.name=N''public'' AND p.permission_name=N''DELETE'';
SELECT @GoodPublicSelectOut=COUNT(*)
FROM sys.database_permissions AS p JOIN sys.database_principals AS g ON g.principal_id=p.grantee_principal_id
WHERE g.name=N''public'' AND p.permission_name=N''SELECT'' AND p.class=0 AND p.state=''G'';
SELECT @SchemaOwnerOut=USER_NAME(principal_id) FROM sys.schemas WHERE name=N''DevOwned'';
SELECT @RowCountOut=COUNT(*) FROM dbo.OrderData WHERE Payload=N''PROD DATA'';';
EXEC sys.sp_executesql @Assert,
 N'@ProdUsersOut int OUTPUT,@ProdRolesOut int OUTPUT,@DevUsersOut int OUTPUT,@DevRolesOut int OUTPUT,
   @MembershipsOut int OUTPUT,@DevPermissionsOut int OUTPUT,@BadPublicDeleteOut int OUTPUT,
   @GoodPublicSelectOut int OUTPUT,@SchemaOwnerOut sysname OUTPUT,@RowCountOut int OUTPUT',
 @ProdUsersOut=@ProdUsers OUTPUT,@ProdRolesOut=@ProdRoles OUTPUT,@DevUsersOut=@DevUsers OUTPUT,
 @DevRolesOut=@DevRoles OUTPUT,@MembershipsOut=@Memberships OUTPUT,@DevPermissionsOut=@DevPermissions OUTPUT,
 @BadPublicDeleteOut=@BadPublicDelete OUTPUT,@GoodPublicSelectOut=@GoodPublicSelect OUTPUT,
 @SchemaOwnerOut=@SchemaOwner OUTPUT,@RowCountOut=@RowCount OUTPUT;

IF @ProdUsers<>0 THROW 51300,'PROD user survived the clean security refresh.',1;
IF @ProdRoles<>0 THROW 51301,'PROD role survived the clean security refresh.',1;
IF @DevUsers<>1 OR @DevRoles<>1 THROW 51302,'DEV user or role was not recreated.',1;
IF @Memberships<>2 THROW 51303,'DEV role memberships were not recreated.',1;
IF @DevPermissions<>3 THROW 51304,'DEV object/column permissions were not recreated.',1;
IF @BadPublicDelete<>0 OR @GoodPublicSelect<>1 THROW 51305,'Permissions on public were not replaced with DEV values.',1;
IF @SchemaOwner<>N'DevAlias' THROW 51306,'DEV schema ownership was not restored.',1;
IF @RowCount<>1 THROW 51307,'The PROD data was not restored into DEV.',1;

DBCC CHECKDB(N'DBA_Toolkit_Refresh_DEV') WITH NO_INFOMSGS,ALL_ERRORMSGS;
SELECT N'PASS' AS test_result,@SnapshotId AS snapshot_id,
       N'PROD data restored; PROD security removed; DEV security reapplied' AS assertion;
GO

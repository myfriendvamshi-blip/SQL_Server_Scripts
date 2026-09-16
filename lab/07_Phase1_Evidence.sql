/* DESTRUCTIVE LAB ONLY. SQLCMD, repo working directory. CI disposable container only.
   CI passes -v DisposableLab=YES. This is an accident guard, not environment attestation.
   Refuse pre-existing fixtures; never overwrite a database/login supplied by an operator. */
:on error exit
USE master;
IF N'$(DisposableLab)'<>N'YES' THROW 51500,'Disposable CI opt-in required.',1;
IF DB_ID(N'DBA_Toolkit_Phase1') IS NOT NULL OR SUSER_ID(N'DBA_Toolkit_Phase1_Login') IS NOT NULL
 OR SUSER_ID(N'DBA_Toolkit_Phase1_Disabled') IS NOT NULL OR SUSER_ID(N'DBA_Toolkit_Phase1_Repair') IS NOT NULL
 THROW 51501,'Fixture collision. Refusing to replace existing objects.',1;
CREATE DATABASE DBA_Toolkit_Phase1;
CREATE LOGIN DBA_Toolkit_Phase1_Login WITH PASSWORD='Fixture_Only!Phase1_2026',CHECK_POLICY=OFF;
CREATE LOGIN DBA_Toolkit_Phase1_Disabled WITH PASSWORD='Fixture_Only!Phase1_2026',CHECK_POLICY=OFF;
CREATE LOGIN DBA_Toolkit_Phase1_Repair WITH PASSWORD='Fixture_Only!Phase1_2026',CHECK_POLICY=OFF;
ALTER LOGIN DBA_Toolkit_Phase1_Disabled DISABLE;
GO
USE DBA_Toolkit_Phase1;
CREATE USER AliasDifferentFromLogin FOR LOGIN DBA_Toolkit_Phase1_Login;
CREATE USER DisabledIdentity FOR LOGIN DBA_Toolkit_Phase1_Disabled;
CREATE USER NoLoginIdentity WITHOUT LOGIN;
CREATE USER OrphanIdentity WITH SID=0x11112222333344445555666677778888,TYPE=S;
CREATE TABLE dbo.Payload(id int NOT NULL PRIMARY KEY,secret_value int);
CREATE ROLE FixtureReaders;
ALTER ROLE FixtureReaders ADD MEMBER AliasDifferentFromLogin;
GRANT SELECT ON dbo.Payload TO FixtureReaders;
DENY UPDATE ON dbo.Payload TO AliasDifferentFromLogin;
GRANT UPDATE ON dbo.Payload(secret_value) TO AliasDifferentFromLogin;
CREATE SYNONYM dbo.RemoteFixture FOR [MissingServer].[MissingDatabase].[dbo].[MissingTable];
GO
CREATE VIEW dbo.CrossDatabaseFixture AS SELECT name FROM master.sys.databases;
GO
:r scripts/scenarios/01_Access.sql
IF (SELECT COUNT(*) FROM #AccessEvidence WHERE finding=N'ORPHAN_CANDIDATE')<>1
 THROW 51502,'Expected exactly one SQL orphan, not a no-login or alias false positive.',1;
IF NOT EXISTS(SELECT 1 FROM #AccessEvidence WHERE user_name=N'OrphanIdentity' AND finding=N'ORPHAN_CANDIDATE')
 THROW 51503,'Missing orphan evidence.',1;
IF NOT EXISTS(SELECT 1 FROM #AccessEvidence WHERE user_name=N'AliasDifferentFromLogin' AND mapped_login=N'DBA_Toolkit_Phase1_Login')
 THROW 51504,'Mapping must use SID, not name.',1;
IF NOT EXISTS(SELECT 1 FROM #AccessEvidence WHERE user_name=N'DisabledIdentity' AND finding=N'LOGIN_DISABLED')
 THROW 51505,'Disabled login evidence missing.',1;
IF NOT EXISTS(SELECT 1 FROM #AccessEvidence WHERE user_name=N'NoLoginIdentity' AND finding=N'NO_LOGIN_EXPECTED')
 THROW 51506,'WITHOUT LOGIN user misclassified.',1;
GO
:r scripts/scenarios/03_Restore_Dependencies.sql
IF NOT EXISTS(SELECT 1 FROM #DependencyEvidence WHERE referencing_object=N'CrossDatabaseFixture' AND referenced_database_name=N'master')
 THROW 51507,'Cross-database dependency not captured.',1;
GO
:r scripts/scenarios/04_Integrity_Evidence.sql
IF EXISTS(SELECT 1 FROM #IntegrityEvidence) THROW 51508,'Unexpected suspect-page fixture evidence.',1;
GO
:r scripts/scenarios/05_Security_Evidence.sql
IF NOT EXISTS(SELECT 1 FROM #SecurityEvidence WHERE grantee=N'AliasDifferentFromLogin' AND permission_name=N'UPDATE' AND state_desc=N'DENY' AND minor_id=0)
 THROW 51509,'Object deny missing.',1;
IF NOT EXISTS(SELECT 1 FROM #SecurityEvidence WHERE grantee=N'AliasDifferentFromLogin' AND permission_name=N'UPDATE' AND state_desc=N'GRANT' AND column_name=N'secret_value')
 THROW 51510,'Column grant exception missing.',1;
/* Actual effective access test: a column GRANT can override an object DENY. */
EXECUTE AS USER=N'AliasDifferentFromLogin';
DECLARE @CanUpdate int=HAS_PERMS_BY_NAME(N'dbo.Payload','OBJECT','UPDATE',N'secret_value','COLUMN');
REVERT;
IF @CanUpdate<>1 OR @CanUpdate IS NULL THROW 51511,'Expected column-level effective permission.',1;
/* Preserve principle ID and grants when remapping; no drop/recreate user. */
DECLARE @Before int=USER_ID(N'OrphanIdentity');
ALTER USER OrphanIdentity WITH LOGIN=DBA_Toolkit_Phase1_Repair;
IF USER_ID(N'OrphanIdentity')<>@Before THROW 51512,'Remap changed principal identity.',1;
GO
:r scripts/scenarios/01_Access.sql
IF EXISTS(SELECT 1 FROM #AccessEvidence WHERE finding=N'ORPHAN_CANDIDATE')
 THROW 51513,'SID remap did not resolve orphan.',1;
DBCC CHECKDB(N'DBA_Toolkit_Phase1') WITH NO_INFOMSGS,ALL_ERRORMSGS;
SELECT N'PASS: Phase1 access/dependency/security assertions; integrity healthy-path only' AS result;
USE master;
DROP DATABASE DBA_Toolkit_Phase1;
DROP LOGIN DBA_Toolkit_Phase1_Login;
DROP LOGIN DBA_Toolkit_Phase1_Disabled;
DROP LOGIN DBA_Toolkit_Phase1_Repair;
GO

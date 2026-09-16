/* READ-ONLY (session temp tables only). SQL Server 2022, current user database.
   Requires VIEW ANY DEFINITION at server and VIEW DEFINITION in this database.
   Runbook: docs/PHASE1_RUNBOOKS.md. No password hashes or repair execution. */
SET NOCOUNT ON;
IF COALESCE(HAS_PERMS_BY_NAME(NULL,NULL,'VIEW ANY DEFINITION'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','VIEW DEFINITION'),0)<>1
    THROW 51400,'Complete metadata visibility is required; absence is not evidence of absence.',1;
DROP TABLE IF EXISTS #AccessEvidence;
SELECT DB_NAME() AS database_name, dp.name AS user_name,dp.type_desc,
       dp.authentication_type_desc,dp.sid AS user_sid,sp.name AS mapped_login,
       sp.is_disabled,sp.default_database_name,
       CASE
        WHEN dp.authentication_type_desc=N'DATABASE' THEN N'CONTAINED_NOT_ORPHAN'
        WHEN dp.authentication_type_desc=N'NONE' THEN N'NO_LOGIN_EXPECTED'
        WHEN dp.authentication_type_desc=N'INSTANCE' AND sp.sid IS NULL THEN N'ORPHAN_CANDIDATE'
        WHEN dp.type IN ('U','G') AND sp.sid IS NULL THEN N'WINDOWS_GROUP_PATH_REVIEW'
        WHEN sp.is_disabled=1 THEN N'LOGIN_DISABLED'
        ELSE N'MAPPING_PRESENT_REVIEW_ACCESS' END AS finding
INTO #AccessEvidence
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid=dp.sid AND sp.type IN ('S','U','G','E','X')
WHERE dp.principal_id>4 AND dp.type<>'R';
SELECT SYSUTCDATETIME() AS captured_utc,@@SERVERNAME AS server_name,
       SERVERPROPERTY('ProductVersion') AS build,DB_NAME() AS database_name,
       SERVERPROPERTY('IsIntegratedSecurityOnly') AS windows_auth_only;
SELECT * FROM #AccessEvidence ORDER BY user_name;
SELECT sp.name AS login_name,sp.is_disabled,sp.default_database_name,
       d.state_desc AS default_db_state,d.user_access_desc,d.containment_desc
FROM sys.server_principals AS sp
LEFT JOIN sys.databases AS d ON d.name=sp.default_database_name
WHERE sp.type IN ('S','U','G') AND sp.name NOT LIKE N'##%';
SELECT name,state_desc,user_access_desc,containment_desc FROM sys.databases WHERE database_id=DB_ID();
SELECT name,value_in_use FROM sys.configurations WHERE name=N'contained database authentication';
GO

/* READ-ONLY, SQL Server 2022. Current database.
   Conservative prerequisite: sysadmin for full security/audit metadata.
   Snapshot evidence only; does not attribute an actor or compute effective permissions. */
SET NOCOUNT ON;
IF COALESCE(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
    THROW 51430,'Complete security/audit inventory requires sysadmin in this implementation.',1;
SELECT SYSUTCDATETIME() AS captured_utc,@@SERVERNAME AS server_name,DB_NAME() AS database_name;
DROP TABLE IF EXISTS #SecurityEvidence;
SELECT p.class,p.class_desc,p.major_id,p.minor_id,p.permission_name,p.state_desc,
       g.name AS grantee,r.name AS grantor,
       CASE WHEN p.class=1 THEN OBJECT_SCHEMA_NAME(p.major_id) END AS object_schema,
       CASE WHEN p.class=1 THEN OBJECT_NAME(p.major_id)
            WHEN p.class=3 THEN SCHEMA_NAME(p.major_id)
            WHEN p.class=4 THEN USER_NAME(p.major_id) END AS securable_name,
       CASE WHEN p.class=1 AND p.minor_id>0 THEN COL_NAME(p.major_id,p.minor_id) END AS column_name
INTO #SecurityEvidence FROM sys.database_permissions AS p
JOIN sys.database_principals AS g ON g.principal_id=p.grantee_principal_id
JOIN sys.database_principals AS r ON r.principal_id=p.grantor_principal_id;
SELECT * FROM #SecurityEvidence ORDER BY grantee,class,major_id,minor_id,permission_name;
SELECT r.name AS role_name,m.name AS member_name
FROM sys.database_role_members AS rm JOIN sys.database_principals AS r ON r.principal_id=rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id=rm.member_principal_id;
SELECT name,USER_NAME(principal_id) AS owner_name FROM sys.schemas;
SELECT SCHEMA_NAME(schema_id) AS schema_name,name,USER_NAME(principal_id) AS explicit_owner
FROM sys.objects WHERE is_ms_shipped=0 AND principal_id IS NOT NULL;
SELECT g.name AS grantee,r.name AS grantor,p.class_desc,p.major_id,p.permission_name,p.state_desc
FROM sys.server_permissions AS p JOIN sys.server_principals AS g ON g.principal_id=p.grantee_principal_id
JOIN sys.server_principals AS r ON r.principal_id=p.grantor_principal_id;
SELECT r.name AS role_name,m.name AS member_name
FROM sys.server_role_members AS rm JOIN sys.server_principals AS r ON r.principal_id=rm.role_principal_id
JOIN sys.server_principals AS m ON m.principal_id=rm.member_principal_id;
SELECT name,type_desc,is_state_enabled,on_failure_desc FROM sys.server_audits;
SELECT name,is_state_enabled,create_date,modify_date FROM sys.server_audit_specifications;
SELECT name,is_state_enabled,create_date,modify_date FROM sys.database_audit_specifications;
SELECT audit_action_name,audited_result,is_group FROM sys.server_audit_specification_details;
SELECT audit_action_name,class_desc,major_id,minor_id,audited_result,is_group
FROM sys.database_audit_specification_details;
GO

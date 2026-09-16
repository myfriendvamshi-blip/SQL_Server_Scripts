/* READ-ONLY, SQL Server 2022. Current database. No secrets, no remote connections.
   Conservative prerequisite: sysadmin for complete cross-database/server inventory.
   Not a migration script or a proof that every dependency has been found. */
SET NOCOUNT ON;
IF COALESCE(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
    THROW 51410,'This cross-instance-scope inventory requires sysadmin metadata visibility.',1;
SELECT SYSUTCDATETIME() AS captured_utc,@@SERVERNAME AS server_name,DB_NAME() AS database_name;
DROP TABLE IF EXISTS #DependencyEvidence;
SELECT s.name AS schema_name,o.name AS referencing_object,
       d.referenced_server_name,d.referenced_database_name,d.referenced_schema_name,
       d.referenced_entity_name,d.is_caller_dependent,d.is_ambiguous
INTO #DependencyEvidence
FROM sys.sql_expression_dependencies AS d
JOIN sys.objects AS o ON o.object_id=d.referencing_id
JOIN sys.schemas AS s ON s.schema_id=o.schema_id
WHERE d.referenced_server_name IS NOT NULL OR d.referenced_database_name IS NOT NULL;
SELECT * FROM #DependencyEvidence ORDER BY schema_name,referencing_object;
SELECT name,base_object_name FROM sys.synonyms;
SELECT name,SUSER_SNAME(owner_sid) AS database_owner,is_trustworthy_on,is_db_chaining_on,
       is_broker_enabled,service_broker_guid FROM sys.databases WHERE database_id=DB_ID();
SELECT name,credential_identity FROM sys.database_scoped_credentials;
SELECT name,credential_identity FROM sys.credentials;
SELECT name,product,provider,is_data_access_enabled,is_rpc_out_enabled FROM sys.servers WHERE is_linked=1;
/* Do not print provider strings or job commands: they can embed credentials. */
SELECT j.name AS job_name,SUSER_SNAME(j.owner_sid) AS owner_login,j.enabled,
       s.step_id,s.subsystem,s.database_name,s.proxy_id
FROM msdb.dbo.sysjobs AS j JOIN msdb.dbo.sysjobsteps AS s ON s.job_id=j.job_id
WHERE s.database_name=DB_NAME();
SELECT p.name AS proxy_name,c.name AS credential_name,p.enabled
FROM msdb.dbo.sysproxies AS p LEFT JOIN sys.credentials AS c ON c.credential_id=p.credential_id;
SELECT name,type_desc,state_desc FROM sys.endpoints;
SELECT name,thumbprint,expiry_date,pvt_key_encryption_type_desc FROM master.sys.certificates;
SELECT database_id,encryption_state,encryptor_type,encryptor_thumbprint
FROM sys.dm_database_encryption_keys WHERE database_id=DB_ID();
SELECT SCHEMA_NAME(o.schema_id) AS schema_name,o.name,m.execute_as_principal_id,
       CASE WHEN m.execute_as_principal_id=-2 THEN N'OWNER' ELSE USER_NAME(m.execute_as_principal_id) END AS execute_as_name
FROM sys.sql_modules AS m JOIN sys.objects AS o ON o.object_id=m.object_id
WHERE m.execute_as_principal_id IS NOT NULL;
GO

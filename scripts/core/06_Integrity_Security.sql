/* Validation: EXECUTED-CI | Read-only; repair commands are output only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT DB_NAME(database_id) AS database_name,file_id,page_id,event_type,error_count,last_update_date
FROM msdb.dbo.suspect_pages ORDER BY last_update_date DESC;

DROP TABLE IF EXISTS #orphans;
CREATE TABLE #orphans(database_name sysname,user_name sysname,user_sid varbinary(85),type_desc nvarchar(60),repair_command nvarchar(max));
DECLARE @db sysname,@sql nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
 SELECT name FROM sys.databases WHERE database_id>4 AND state_desc='ONLINE' AND is_read_only=0;
OPEN c; FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @sql=N'USE '+QUOTENAME(@db)+N';
 INSERT #orphans
 SELECT DB_NAME(),dp.name,dp.sid,dp.type_desc,
   CASE WHEN sp.name IS NOT NULL THEN N''USE ''+QUOTENAME(DB_NAME())+N''; ALTER USER ''+QUOTENAME(dp.name)+N'' WITH LOGIN = ''+QUOTENAME(sp.name)+N'';'' END
 FROM sys.database_principals AS dp
 LEFT JOIN master.sys.server_principals AS sp ON sp.sid=dp.sid
 WHERE dp.authentication_type=1 AND dp.sid IS NOT NULL AND sp.sid IS NULL
   AND dp.principal_id>4 AND dp.type IN (''S'',''U'',''G'');';
 BEGIN TRY EXEC sys.sp_executesql @sql; END TRY
 BEGIN CATCH INSERT #orphans(database_name,user_name,type_desc,repair_command)
  VALUES(@db,N'<scan failed>',N'ERROR',ERROR_MESSAGE()); END CATCH;
 FETCH NEXT FROM c INTO @db;
END
CLOSE c; DEALLOCATE c;
SELECT * FROM #orphans ORDER BY database_name,user_name;

SELECT sp.name AS principal_name,sp.type_desc,sp.is_disabled,sp.default_database_name,
       srp.name AS server_role_name
FROM sys.server_principals AS sp
LEFT JOIN sys.server_role_members AS srm ON srm.member_principal_id=sp.principal_id
LEFT JOIN sys.server_principals AS srp ON srp.principal_id=srm.role_principal_id
WHERE sp.type IN ('S','U','G','E','X') AND sp.name NOT LIKE '##%'
ORDER BY sp.name,srp.name;

SELECT pr.name AS grantee,pe.state_desc,pe.permission_name,pe.class_desc,
       CASE pe.class WHEN 100 THEN @@SERVERNAME WHEN 101 THEN ep.name END AS securable_name
FROM sys.server_permissions AS pe
JOIN sys.server_principals AS pr ON pr.principal_id=pe.grantee_principal_id
LEFT JOIN sys.endpoints AS ep ON ep.endpoint_id=pe.major_id AND pe.class=105
ORDER BY pr.name,pe.class_desc,pe.permission_name;

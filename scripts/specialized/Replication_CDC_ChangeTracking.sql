/* Validation: PARSED-CI + LAB-REQUIRED | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT d.name,d.is_published,d.is_subscribed,d.is_merge_published,d.is_distributor,d.is_cdc_enabled,
       ctdb.is_auto_cleanup_on,ctdb.retention_period,ctdb.retention_period_units_desc
FROM sys.databases AS d
LEFT JOIN sys.change_tracking_databases AS ctdb ON ctdb.database_id=d.database_id
ORDER BY d.name;

IF DB_ID(N'distribution') IS NOT NULL
BEGIN
 EXEC(N'USE distribution;
 SELECT TOP (200) a.name AS agent_name,a.publisher_db,a.publication,
        h.time,h.runstatus,h.comments,h.delivery_rate,h.delivery_latency,h.delivered_transactions
 FROM dbo.MSlogreader_agents AS a
 LEFT JOIN dbo.MSlogreader_history AS h ON h.agent_id=a.id
 ORDER BY h.time DESC;

 SELECT TOP (200) a.name AS agent_name,a.publisher_db,a.publication,a.subscriber_db,
        h.time,h.runstatus,h.comments,h.delivery_rate,h.delivery_latency,h.delivered_transactions
 FROM dbo.MSdistribution_agents AS a
 LEFT JOIN dbo.MSdistribution_history AS h ON h.agent_id=a.id
 ORDER BY h.time DESC;');
END;

DECLARE @db sysname,@sql nvarchar(max);
DROP TABLE IF EXISTS #features;
CREATE TABLE #features(database_name sysname,schema_name sysname,table_name sysname,
 feature_name varchar(30),detail nvarchar(4000));
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE database_id>4 AND state_desc='ONLINE';
OPEN c; FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @sql=N'USE '+QUOTENAME(@db)+N';
 INSERT #features
 SELECT DB_NAME(),SCHEMA_NAME(t.schema_id),t.name,''CDC'',CONCAT(''capture_instance='',ct.capture_instance,'',supports_net_changes='',ct.supports_net_changes)
 FROM sys.tables t JOIN cdc.change_tables ct ON ct.source_object_id=t.object_id
 UNION ALL
 SELECT DB_NAME(),SCHEMA_NAME(t.schema_id),t.name,''CHANGE_TRACKING'',CONCAT(''track_columns_updated='',ct.is_track_columns_updated_on)
 FROM sys.tables t JOIN sys.change_tracking_tables ct ON ct.object_id=t.object_id;';
 BEGIN TRY EXEC sys.sp_executesql @sql; END TRY BEGIN CATCH
  IF ERROR_NUMBER() NOT IN (208,229) INSERT #features VALUES(@db,NULL,NULL,'ERROR',ERROR_MESSAGE());
 END CATCH;
 FETCH NEXT FROM c INTO @db;
END
CLOSE c; DEALLOCATE c;
SELECT * FROM #features ORDER BY database_name,feature_name,schema_name,table_name;

/* Validation: EXECUTED-CI | Run in the affected user database | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @MinimumPages int=1000;

SELECT OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,OBJECT_NAME(i.object_id) AS table_name,
       i.name AS index_name,i.index_id,i.type_desc,i.is_unique,i.is_disabled,i.has_filter,
       ps.page_count,CAST(ps.avg_fragmentation_in_percent AS decimal(6,2)) AS fragmentation_pct,
       COALESCE(us.user_seeks,0) AS seeks,COALESCE(us.user_scans,0) AS scans,
       COALESCE(us.user_lookups,0) AS lookups,COALESCE(us.user_updates,0) AS updates,
       us.last_user_seek,us.last_user_scan,us.last_user_lookup,us.last_user_update
FROM sys.indexes AS i
JOIN sys.dm_db_index_physical_stats(DB_ID(),NULL,NULL,NULL,'LIMITED') AS ps
 ON ps.object_id=i.object_id AND ps.index_id=i.index_id
LEFT JOIN sys.dm_db_index_usage_stats AS us
 ON us.database_id=DB_ID() AND us.object_id=i.object_id AND us.index_id=i.index_id
WHERE i.index_id>0 AND ps.page_count>=@MinimumPages
ORDER BY ps.page_count DESC,ps.avg_fragmentation_in_percent DESC;

SELECT OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,OBJECT_NAME(s.object_id) AS table_name,
       s.name AS statistics_name,s.auto_created,s.user_created,s.no_recompute,s.has_filter,
       sp.last_updated,sp.rows,sp.rows_sampled,sp.steps,sp.unfiltered_rows,sp.modification_counter,
       CASE WHEN sp.rows>0 THEN CAST(100.0*sp.rows_sampled/sp.rows AS decimal(6,2)) END AS sample_pct
FROM sys.stats AS s CROSS APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id,'IsUserTable')=1
ORDER BY sp.modification_counter DESC,sp.last_updated;

SELECT mid.database_id,DB_NAME(mid.database_id) AS database_name,
       OBJECT_SCHEMA_NAME(mid.object_id,mid.database_id) AS schema_name,
       OBJECT_NAME(mid.object_id,mid.database_id) AS table_name,
       migs.user_seeks,migs.user_scans,migs.avg_total_user_cost,migs.avg_user_impact,
       CAST(migs.user_seeks*migs.avg_total_user_cost*(migs.avg_user_impact/100.0) AS decimal(18,2)) AS estimated_benefit,
       mid.equality_columns,mid.inequality_columns,mid.included_columns
FROM sys.dm_db_missing_index_group_stats AS migs
JOIN sys.dm_db_missing_index_groups AS mig ON mig.index_group_handle=migs.group_handle
JOIN sys.dm_db_missing_index_details AS mid ON mid.index_handle=mig.index_handle
WHERE mid.database_id=DB_ID()
ORDER BY estimated_benefit DESC;

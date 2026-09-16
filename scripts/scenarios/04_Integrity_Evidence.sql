/* READ-ONLY metadata, SQL Server 2022. Current database.
   Requires SELECT msdb.dbo.suspect_pages and VIEW DEFINITION in database.
   Does NOT execute CHECKDB or attempt repair. Empty suspect_pages is not a clean bill of health. */
SET NOCOUNT ON;
IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','VIEW DEFINITION'),0)<>1
    THROW 51420,'VIEW DEFINITION in the selected database is required.',1;
SELECT SYSUTCDATETIME() AS captured_utc,@@SERVERNAME AS server_name,DB_NAME() AS database_name,
       DATABASEPROPERTYEX(DB_NAME(),'LastGoodCheckDbTime') AS last_good_checkdb_reported;
SELECT name,state_desc,user_access_desc,page_verify_option_desc,recovery_model_desc
FROM sys.databases WHERE database_id=DB_ID();
SELECT file_id,type_desc,state_desc,name,physical_name,size FROM sys.database_files;
DROP TABLE IF EXISTS #IntegrityEvidence;
SELECT database_id,file_id,page_id,event_type,error_count,last_update_date,
       CASE event_type WHEN 1 THEN N'823_OR_OTHER_824' WHEN 2 THEN N'BAD_CHECKSUM'
            WHEN 3 THEN N'TORN_PAGE' WHEN 4 THEN N'RESTORED' WHEN 5 THEN N'REPAIRED'
            WHEN 7 THEN N'DEALLOCATED' ELSE N'REVIEW' END AS interpretation
INTO #IntegrityEvidence FROM msdb.dbo.suspect_pages WHERE database_id=DB_ID();
SELECT * FROM #IntegrityEvidence ORDER BY last_update_date DESC;
GO

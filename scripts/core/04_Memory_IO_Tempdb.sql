/* Validation: EXECUTED-CI | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT physical_memory_in_use_kb/1024 AS sql_memory_mb,locked_page_allocations_kb/1024 AS locked_pages_mb,
       large_page_allocations_kb/1024 AS large_pages_mb,total_virtual_address_space_kb/1024 AS vas_mb,
       process_physical_memory_low,process_virtual_memory_low
FROM sys.dm_os_process_memory;

SELECT TOP (25) type,SUM(pages_kb)/1024 AS pages_mb
FROM sys.dm_os_memory_clerks GROUP BY type ORDER BY pages_mb DESC;

SELECT mg.session_id,mg.request_id,mg.request_time,mg.grant_time,mg.requested_memory_kb,
       mg.granted_memory_kb,mg.required_memory_kb,mg.used_memory_kb,mg.max_used_memory_kb,
       mg.queue_id,mg.wait_order,mg.is_next_candidate,txt.text
FROM sys.dm_exec_query_memory_grants AS mg
OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) AS txt
ORDER BY mg.requested_memory_kb DESC;

SELECT DB_NAME(vfs.database_id) AS database_name,mf.type_desc,mf.name,mf.physical_name,
       vfs.num_of_reads,vfs.num_of_bytes_read,
       CAST(vfs.io_stall_read_ms/NULLIF(vfs.num_of_reads,0.0) AS decimal(18,2)) AS avg_read_ms,
       vfs.num_of_writes,vfs.num_of_bytes_written,
       CAST(vfs.io_stall_write_ms/NULLIF(vfs.num_of_writes,0.0) AS decimal(18,2)) AS avg_write_ms,
       CAST(vfs.io_stall/NULLIF(vfs.num_of_reads+vfs.num_of_writes,0.0) AS decimal(18,2)) AS avg_io_ms
FROM sys.dm_io_virtual_file_stats(NULL,NULL) AS vfs
JOIN sys.master_files AS mf ON mf.database_id=vfs.database_id AND mf.file_id=vfs.file_id
ORDER BY avg_io_ms DESC;

USE tempdb;
SELECT name,type_desc,physical_name,size/128.0 AS size_mb,
       CASE WHEN is_percent_growth=1 THEN CONCAT(growth,'%') ELSE CONCAT(growth/128,' MB') END AS growth_setting
FROM sys.database_files ORDER BY type,file_id;
SELECT SUM(user_object_reserved_page_count)*8/1024.0 AS user_objects_mb,
       SUM(internal_object_reserved_page_count)*8/1024.0 AS internal_objects_mb,
       SUM(version_store_reserved_page_count)*8/1024.0 AS version_store_mb,
       SUM(unallocated_extent_page_count)*8/1024.0 AS free_mb
FROM sys.dm_db_file_space_usage;
USE master;

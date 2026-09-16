/* Validation: EXECUTED-CI | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT name,value,value_in_use,minimum,maximum,is_dynamic,is_advanced
FROM sys.configurations
WHERE name IN
 ('max server memory (MB)','min server memory (MB)','max degree of parallelism',
  'cost threshold for parallelism','optimize for ad hoc workloads','backup compression default',
  'remote admin connections','blocked process threshold (s)','contained database authentication',
  'xp_cmdshell','Ad Hoc Distributed Queries')
ORDER BY name;

SELECT cpu_count,hyperthread_ratio,scheduler_count,max_workers_count,socket_count,
       cores_per_socket,numa_node_count,physical_memory_kb/1024 AS physical_memory_mb,
       committed_kb/1024 AS committed_mb,committed_target_kb/1024 AS committed_target_mb,
       sqlserver_start_time
FROM sys.dm_os_sys_info;

SELECT DB_NAME(mf.database_id) AS database_name,mf.type_desc,
       COUNT(*) AS file_count,SUM(mf.size)*8.0/1024 AS allocated_mb,
       SUM(CASE WHEN mf.max_size=-1 THEN 0 ELSE mf.max_size END)*8.0/1024 AS configured_max_mb
FROM sys.master_files AS mf
GROUP BY mf.database_id,mf.type_desc
ORDER BY database_name,mf.type_desc;

SELECT counter_name,instance_name,cntr_value,cntr_type
FROM sys.dm_os_performance_counters
WHERE (object_name LIKE '%:Buffer Manager%' AND counter_name IN ('Page life expectancy','Lazy writes/sec','Free list stalls/sec'))
   OR (object_name LIKE '%:Memory Manager%' AND counter_name IN ('Memory Grants Pending','Target Server Memory (KB)','Total Server Memory (KB)'))
   OR (object_name LIKE '%:SQL Statistics%' AND counter_name IN ('Batch Requests/sec','SQL Compilations/sec','SQL Re-Compilations/sec'))
ORDER BY object_name,counter_name,instance_name;

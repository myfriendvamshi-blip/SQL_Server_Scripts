/* Validation: PARSED-CI + LAB-REQUIRED | Read-only | Requires HADR-enabled instance */
SET NOCOUNT ON;
IF SERVERPROPERTY('IsHadrEnabled')<>1
BEGIN SELECT N'Always On Availability Groups is not enabled on this instance.' AS status; RETURN; END;

SELECT ag.name AS ag_name,ar.replica_server_name,ars.role_desc,ars.operational_state_desc,
       ars.connected_state_desc,ars.synchronization_health_desc,ar.availability_mode_desc,
       ar.failover_mode_desc,ar.seeding_mode_desc,ar.session_timeout
FROM sys.availability_groups AS ag
JOIN sys.availability_replicas AS ar ON ar.group_id=ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS ars ON ars.replica_id=ar.replica_id
ORDER BY ag.name,ar.replica_server_name;

SELECT ag.name AS ag_name,ar.replica_server_name,DB_NAME(drs.database_id) AS database_name,
       drs.is_local,drs.is_primary_replica,drs.synchronization_state_desc,
       drs.synchronization_health_desc,drs.database_state_desc,drs.is_suspended,
       drs.suspend_reason_desc,drs.log_send_queue_size,drs.log_send_rate,
       CASE WHEN drs.log_send_rate>0 THEN drs.log_send_queue_size*1.0/drs.log_send_rate END AS estimated_send_seconds,
       drs.redo_queue_size,drs.redo_rate,
       CASE WHEN drs.redo_rate>0 THEN drs.redo_queue_size*1.0/drs.redo_rate END AS estimated_redo_seconds,
       drs.last_sent_time,drs.last_received_time,drs.last_hardened_time,drs.last_redone_time,drs.last_commit_time
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS ar ON ar.replica_id=drs.replica_id
JOIN sys.availability_groups AS ag ON ag.group_id=drs.group_id
ORDER BY ag.name,database_name,ar.replica_server_name;

SELECT ag.name AS ag_name,ags.primary_replica,ags.primary_recovery_health_desc,
       ags.synchronization_health_desc,ags.automated_backup_preference_desc
FROM sys.dm_hadr_availability_group_states AS ags
JOIN sys.availability_groups AS ag ON ag.group_id=ags.group_id;

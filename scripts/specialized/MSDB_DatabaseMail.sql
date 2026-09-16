/* Validation: PARSED-CI + LAB-REQUIRED | Read-only */
SET NOCOUNT ON;
SELECT TOP (200) mailitem_id,profile_id,recipients,copy_recipients,blind_copy_recipients,
       subject,file_attachments,send_request_date,send_request_user,sent_account_id,
       sent_status,sent_date,last_mod_date,last_mod_user
FROM msdb.dbo.sysmail_allitems ORDER BY mailitem_id DESC;

SELECT TOP (200) event_type,log_date,description,process_id,mailitem_id,account_id,last_mod_date,last_mod_user
FROM msdb.dbo.sysmail_event_log
WHERE event_type IN ('error','warning')
ORDER BY log_date DESC;

SELECT SUM(reserved_page_count)*8.0/1024 AS reserved_mb,SUM(used_page_count)*8.0/1024 AS used_mb,
       SUM(row_count) AS approximate_rows
FROM msdb.sys.dm_db_partition_stats
WHERE object_id IN (OBJECT_ID(N'msdb.dbo.sysmail_allitems'),OBJECT_ID(N'msdb.dbo.sysmail_event_log'));

SELECT p.name AS profile_name,a.name AS account_name,a.email_address,a.display_name,
       s.servername,s.port,s.enable_ssl,s.username
FROM msdb.dbo.sysmail_profile AS p
JOIN msdb.dbo.sysmail_profileaccount AS pa ON pa.profile_id=p.profile_id
JOIN msdb.dbo.sysmail_account AS a ON a.account_id=pa.account_id
JOIN msdb.dbo.sysmail_server AS s ON s.account_id=a.account_id
ORDER BY p.name,pa.sequence_number;

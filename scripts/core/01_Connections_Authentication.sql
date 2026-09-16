/* Validation: EXECUTED-CI | Read-only */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT c.session_id,s.login_name,s.original_login_name,s.host_name,s.program_name,
       c.connect_time,c.net_transport,c.protocol_type,c.auth_scheme,c.encrypt_option,
       c.client_net_address,c.local_net_address,c.local_tcp_port,
       DB_NAME(s.database_id) AS database_name,s.status,s.last_request_start_time,s.last_request_end_time
FROM sys.dm_exec_connections AS c
JOIN sys.dm_exec_sessions AS s ON s.session_id=c.session_id
WHERE s.is_user_process=1
ORDER BY c.connect_time DESC;

SELECT type_desc,ip_address,port,state_desc,start_time
FROM sys.dm_tcp_listener_states
ORDER BY listener_id,ip_address;

SELECT name,type_desc,is_disabled,default_database_name,create_date,modify_date
FROM sys.server_principals
WHERE type IN ('S','U','G','E','X') AND name NOT LIKE '##%'
ORDER BY name;

-- Login failures from current error log. Access can be restricted.
BEGIN TRY
 DECLARE @e TABLE(LogDate datetime,ProcessInfo nvarchar(50),[Text] nvarchar(max));
 INSERT @e EXEC master.dbo.xp_readerrorlog 0,1,N'Login failed';
 SELECT * FROM @e ORDER BY LogDate DESC;
END TRY
BEGIN CATCH
 SELECT ERROR_NUMBER() AS error_number,ERROR_MESSAGE() AS error_message,
        N'Grant appropriate diagnostic access or review the SQL Server error log.' AS next_step;
END CATCH;

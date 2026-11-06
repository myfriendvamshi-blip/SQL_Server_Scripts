USE [DBAUtility];
GO
/* Creates supporting objects only; source ServerEventLogs and PatchSchedule are untouched. */
IF OBJECT_ID('dbo.ServerPatchEventLedger','U') IS NULL
BEGIN
 CREATE TABLE dbo.ServerPatchEventLedger(
  EventHash varbinary(32) NOT NULL CONSTRAINT PK_ServerPatchEventLedger PRIMARY KEY,
  ServerName sysname NOT NULL,LogName nvarchar(128) NULL,EventID int NOT NULL,
  TimeCreated datetime2(3) NOT NULL,Message nvarchar(max) NULL,StatusCategory nvarchar(50) NULL,
  EventType varchar(40) NOT NULL,
  FirstSeen datetime2(3) NOT NULL CONSTRAINT DF_ServerPatchEventLedger_FirstSeen DEFAULT SYSUTCDATETIME(),
  ProcessedAt datetime2(3) NULL);
 CREATE INDEX IX_ServerPatchEventLedger_Pending ON dbo.ServerPatchEventLedger(ProcessedAt,TimeCreated) INCLUDE(ServerName,EventID,EventType);
END;
GO
IF OBJECT_ID('dbo.ServerPatchMonitorState','U') IS NULL
BEGIN
 CREATE TABLE dbo.ServerPatchMonitorState(
  ServerName sysname NOT NULL CONSTRAINT PK_ServerPatchMonitorState PRIMARY KEY,
  IncidentId uniqueidentifier NOT NULL,FirstEventTime datetime2(3) NOT NULL,LastEventTime datetime2(3) NOT NULL,
  EventSummary varchar(100) NULL,EventIds varchar(400) NULL,
  PatchStarted bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_PatchStarted DEFAULT(0),
  PatchSucceeded bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_PatchSucceeded DEFAULT(0),
  PatchFailed bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_PatchFailed DEFAULT(0),
  ShutdownInitiated bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_Shutdown DEFAULT(0),
  RebootDetected bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_Reboot DEFAULT(0),
  FirstFailureTime datetime2(3) NULL,LastCheckedTime datetime2(3) NULL,
  SQLServiceStatus varchar(30) NULL,AgentServiceStatus varchar(30) NULL,
  SSISServiceStatus varchar(30) NULL,SSRSServiceStatus varchar(30) NULL,
  RecoveryStatus varchar(30) NOT NULL CONSTRAINT DF_ServerPatchMonitorState_Recovery DEFAULT('Monitoring'),
  GaveUpNotified bit NOT NULL CONSTRAINT DF_ServerPatchMonitorState_GaveUp DEFAULT(0),
  LastUpdated datetime2(3) NOT NULL CONSTRAINT DF_ServerPatchMonitorState_LastUpdated DEFAULT SYSUTCDATETIME());
 CREATE UNIQUE INDEX UX_ServerPatchMonitorState_IncidentId ON dbo.ServerPatchMonitorState(IncidentId);
 CREATE INDEX IX_ServerPatchMonitorState_Active ON dbo.ServerPatchMonitorState(RecoveryStatus,LastCheckedTime) INCLUDE(ServerName,IncidentId);
END;
GO
IF OBJECT_ID('dbo.ServerPatchNotificationLog','U') IS NULL
BEGIN
 CREATE TABLE dbo.ServerPatchNotificationLog(
  NotificationId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ServerPatchNotificationLog PRIMARY KEY,
  IncidentId uniqueidentifier NOT NULL,ServerName sysname NOT NULL,
  NotificationType varchar(30) NOT NULL,EmailSubject nvarchar(300) NOT NULL,
  SentAt datetime2(3) NOT NULL CONSTRAINT DF_ServerPatchNotificationLog_SentAt DEFAULT SYSUTCDATETIME());
 CREATE UNIQUE INDEX UX_ServerPatchNotificationLog_IncidentType ON dbo.ServerPatchNotificationLog(IncidentId,NotificationType);
 CREATE INDEX IX_ServerPatchNotificationLog_ServerSent ON dbo.ServerPatchNotificationLog(ServerName,SentAt DESC);
END;
GO
CREATE OR ALTER VIEW dbo.vw_ServerPatchMonitor_Current AS
SELECT ServerName,IncidentId,FirstEventTime,LastEventTime,EventSummary,EventIds,
 PatchStarted,PatchSucceeded,PatchFailed,ShutdownInitiated,RebootDetected,FirstFailureTime,
 SQLServiceStatus,AgentServiceStatus,SSISServiceStatus,SSRSServiceStatus,
 RecoveryStatus,GaveUpNotified,LastCheckedTime,LastUpdated
FROM dbo.ServerPatchMonitorState;
GO
SELECT name,type_desc FROM sys.objects
WHERE name IN('ServerPatchEventLedger','ServerPatchMonitorState','ServerPatchNotificationLog','vw_ServerPatchMonitor_Current')
ORDER BY name;
GO

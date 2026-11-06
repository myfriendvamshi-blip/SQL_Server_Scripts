#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$CentralSqlInstance='CENTRALSQL01',[string]$CentralDatabase='DBAUtility',
 [string]$SmtpServer='smtp.yourdomain.com',[int]$SmtpPort=25,
 [string]$MailFrom='sql-patch-monitor@yourdomain.com',
 [string[]]$MailTo=@('dba-team@yourdomain.com'),
 [string]$SmtpCredentialFile='C:\SQLAgent\Secrets\PatchMonitorSmtpPassword.txt',
 [int]$LookbackHours=48,[int]$EscalationHours=4,[int]$DiskWarningPercentFree=10,
 [switch]$SuppressEmail
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function New-DbConnection([string]$server,[string]$db) {
 $b=New-Object System.Data.SqlClient.SqlConnectionStringBuilder
 $b.DataSource=$server;$b.InitialCatalog=$db;$b.IntegratedSecurity=$true
 $b.ApplicationName='CentralPatchMonitor';$b.ConnectTimeout=15
 New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
}
function Invoke-Db([string]$server,[string]$db,[string]$sql,[hashtable]$p=@{},[switch]$NonQuery) {
 $cn=New-DbConnection $server $db
 try {
  $cn.Open();$cmd=$cn.CreateCommand();$cmd.CommandText=$sql;$cmd.CommandTimeout=90
  foreach($k in $p.Keys) {
   $v=$p[$k];if($null -eq $v){$v=[DBNull]::Value}
   $param=$cmd.Parameters.AddWithValue("@$k",$v)
   if($v -is [byte[]]){$param.SqlDbType=[System.Data.SqlDbType]::VarBinary}
  }
  if($NonQuery){[void]$cmd.ExecuteNonQuery();return}
  $dt=New-Object System.Data.DataTable
  $da=New-Object System.Data.SqlClient.SqlDataAdapter($cmd);[void]$da.Fill($dt);return $dt
 } finally {if($cn.State -ne 'Closed'){$cn.Close()};$cn.Dispose()}
}
function Invoke-DbMulti([string]$server,[string]$db,[string]$sql,[hashtable]$p=@{}) {
 $cn=New-DbConnection $server $db
 try {
  $cn.Open();$cmd=$cn.CreateCommand();$cmd.CommandText=$sql;$cmd.CommandTimeout=90
  foreach($k in $p.Keys) {
   $v=$p[$k];if($null -eq $v){$v=[DBNull]::Value}
   $param=$cmd.Parameters.AddWithValue("@$k",$v)
   if($v -is [byte[]]){$param.SqlDbType=[System.Data.SqlDbType]::VarBinary}
  }
  $ds=New-Object System.Data.DataSet
  $da=New-Object System.Data.SqlClient.SqlDataAdapter($cmd);[void]$da.Fill($ds);return $ds
 } finally {if($cn.State -ne 'Closed'){$cn.Close()};$cn.Dispose()}
}
function Send-Mail([string]$subject,[string]$html) {
 if($SuppressEmail){Write-Output "EMAIL SUPPRESSED: $subject";return}
 if(!(Test-Path -LiteralPath $SmtpCredentialFile)){throw "SMTP credential file missing: $SmtpCredentialFile"}
 $secure=Get-Content -LiteralPath $SmtpCredentialFile -Raw | ConvertTo-SecureString
 $cred=New-Object System.Management.Automation.PSCredential($MailFrom,$secure)
 $msg=New-Object System.Net.Mail.MailMessage
 try {
  $msg.From=$MailFrom;foreach($a in $MailTo){[void]$msg.To.Add($a)}
  $msg.Subject=$subject;$msg.Body=$html;$msg.IsBodyHtml=$true
  $smtp=New-Object System.Net.Mail.SmtpClient($SmtpServer,$SmtpPort)
  $smtp.EnableSsl=$false;$smtp.Credentials=$cred.GetNetworkCredential();$smtp.Send($msg)
 } finally {$msg.Dispose()}
}
function Classify-Event([int]$id,[string]$message) {
 switch($id) {
  1074 {'ShutdownInitiated';break}
  41 {'UnexpectedRestart';break}
  6008 {'UnexpectedRestart';break}
  6006 {'ShutdownRecord';break}
  6005 {'BootEvent';break}
  43 {'UpdateStarted';break}
  19 {'UpdateSucceeded';break}
  20 {'UpdateFailed';break}
  7036 {
   if($message -match '(?i)(SQL Server Agent|SQLAgent).*(stopped|stop state)'){'AgentStopped';break}
   if($message -match '(?i)(SQL Server Agent|SQLAgent).*(running state|started)'){'AgentStarted';break}
   if($message -match '(?i)(SQL Server|MSSQLSERVER|MSSQL\$).*(stopped|stop state)'){'SqlStopped';break}
   if($message -match '(?i)(SQL Server|MSSQLSERVER|MSSQL\$).*(running state|started)'){'SqlStarted';break}
   if($message -match '(?i)(Integration Services|MsDtsServer).*(stopped|stop state)'){'SsisStopped';break}
   if($message -match '(?i)(Integration Services|MsDtsServer).*(running state|started)'){'SsisStarted';break}
   if($message -match '(?i)(Reporting Services|ReportServer).*(stopped|stop state)'){'SsrsStopped';break}
   if($message -match '(?i)(Reporting Services|ReportServer).*(running state|started)'){'SsrsStarted';break}
   break
  }
 }
}
function Service-Name([string]$instance,[string]$kind) {
 if([string]::IsNullOrWhiteSpace($instance) -or $instance -eq 'MSSQLSERVER') {
  if($kind -eq 'SQL'){'MSSQLSERVER'}elseif($kind -eq 'Agent'){'SQLSERVERAGENT'}elseif($kind -eq 'SSIS'){'MsDtsServer*'}else{'ReportServer*'}
 } else {
  if($kind -eq 'SQL'){'MSSQL$'+$instance}elseif($kind -eq 'Agent'){'SQLAgent$'+$instance}elseif($kind -eq 'SSIS'){'MsDtsServer*'}else{'ReportServer*'}
 }
}
function Get-ServiceState([string]$server,[string]$name) {
 try {
  $all=@(Get-CimInstance Win32_Service -ComputerName $server -ErrorAction Stop)
  if($name.EndsWith('*')) {
   $prefix=$name.TrimEnd('*');$matches=@($all|Where-Object{$_.Name -like ($prefix+'*')})
   if(!$matches){return 'NotConfigured'}
   if(@($matches|Where-Object{$_.State -eq 'Running'})){return 'Running'}
   return 'Stopped'
  }
  $s=$all|Where-Object{$_.Name -eq $name}|Select-Object -First 1
  if(!$s){return 'NotConfigured'};return [string]$s.State
 } catch {return 'Unknown'}
}
function Notify([guid]$incident,[string]$server,[string]$type,[string]$subject,[string]$html) {
 if($SuppressEmail){Write-Output "EMAIL SUPPRESSED: $subject";return}
 $x=Invoke-Db $CentralSqlInstance $CentralDatabase @'
SELECT COUNT(*) Cnt FROM dbo.ServerPatchNotificationLog WHERE IncidentId=@Id AND NotificationType=@Type;
'@ @{Id=$incident;Type=$type}
 if([int]$x.Rows[0].Cnt -gt 0){return}
 Send-Mail $subject $html
 Invoke-Db $CentralSqlInstance $CentralDatabase @'
INSERT dbo.ServerPatchNotificationLog(IncidentId,ServerName,NotificationType,EmailSubject,SentAt)
VALUES(@Id,@Server,@Type,@Subject,SYSUTCDATETIME());
'@ @{Id=$incident;Server=$server;Type=$type;Subject=$subject} -NonQuery
}

# One run at a time across SQL Agent retries.
$lock=New-DbConnection $CentralSqlInstance $CentralDatabase
try {
 $lock.Open();$lc=$lock.CreateCommand()
 $lc.CommandText="DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'CentralPatchMonitor',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0; SELECT @r;"
 if([int]$lc.ExecuteScalar() -lt 0){Write-Output 'A previous run is active; exiting.';return}

 $events=Invoke-Db $CentralSqlInstance $CentralDatabase @'
SELECT ServerName,LogName,EventID,TimeCreated,Message,StatusCategory
FROM dbo.ServerEventLogs WHERE TimeCreated>=DATEADD(hour,-@Hours,GETDATE()) ORDER BY TimeCreated;
'@ @{Hours=$LookbackHours}
 foreach($e in $events.Rows) {
  $server=[string]$e.ServerName;$id=[int]$e.EventID;$msg=[string]$e.Message
  $type=Classify-Event $id $msg
  if([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($type)){continue}
  $time=([datetime]$e.TimeCreated).ToString('o',[Globalization.CultureInfo]::InvariantCulture)
  $raw="$server|$($e.LogName)|$id|$time|$msg|$($e.StatusCategory)"
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))}finally{$sha.Dispose()}
  $newIncident=[guid]::NewGuid()
  $result=Invoke-DbMulti $CentralSqlInstance $CentralDatabase @'
IF NOT EXISTS(SELECT 1 FROM dbo.ServerPatchEventLedger WHERE EventHash=@Hash)
BEGIN
 INSERT dbo.ServerPatchEventLedger(EventHash,ServerName,LogName,EventID,TimeCreated,Message,StatusCategory,EventType)
 VALUES(@Hash,@Server,@LogName,@EventID,@TimeCreated,@Message,@Category,@Type);
END;
SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.ServerPatchEventLedger WHERE EventHash=@Hash AND ProcessedAt IS NULL) THEN 1 ELSE 0 END IsNew;
SELECT TOP(1) IncidentId FROM dbo.ServerPatchMonitorState WHERE ServerName=@Server AND RecoveryStatus<>'Recovered';
'@ @{Hash=$hash;Server=$server;LogName=[string]$e.LogName;EventID=$id;TimeCreated=[datetime]$e.TimeCreated;Message=$msg;Category=[string]$e.StatusCategory;Type=$type}
  if([int]$result.Tables[0].Rows[0].IsNew -eq 0){continue}
  if($result.Tables[1].Rows.Count -eq 0) {
   Invoke-Db $CentralSqlInstance $CentralDatabase @'
IF EXISTS(SELECT 1 FROM dbo.ServerPatchMonitorState WHERE ServerName=@Server)
 UPDATE dbo.ServerPatchMonitorState
 SET IncidentId=@Incident,FirstEventTime=@When,LastEventTime=@When,EventSummary=@Type,
  EventIds=CONVERT(varchar(20),@EventID),PatchStarted=@Started,PatchSucceeded=@Succeeded,
  PatchFailed=@Failed,ShutdownInitiated=@Shutdown,RebootDetected=@Reboot,
  FirstFailureTime=CASE WHEN @Failure=1 THEN SYSUTCDATETIME() END,
  LastCheckedTime=NULL,SQLServiceStatus=NULL,AgentServiceStatus=NULL,SSISServiceStatus=NULL,
  SSRSServiceStatus=NULL,RecoveryStatus='Monitoring',GaveUpNotified=0,LastUpdated=SYSUTCDATETIME()
 WHERE ServerName=@Server;
ELSE
 INSERT dbo.ServerPatchMonitorState(ServerName,IncidentId,FirstEventTime,LastEventTime,EventSummary,EventIds,
  PatchStarted,PatchSucceeded,PatchFailed,ShutdownInitiated,RebootDetected,FirstFailureTime,RecoveryStatus)
 VALUES(@Server,@Incident,@When,@When,@Type,CONVERT(varchar(20),@EventID),
  @Started,@Succeeded,@Failed,@Shutdown,@Reboot,
  CASE WHEN @Failure=1 THEN SYSUTCDATETIME() END,'Monitoring');
'@ @{Server=$server;Incident=$newIncident;When=[datetime]$e.TimeCreated;Type=$type;EventID=$id;
 Started=($type -eq 'UpdateStarted');Succeeded=($type -eq 'UpdateSucceeded');Failed=($type -eq 'UpdateFailed');
 Shutdown=($type -eq 'ShutdownInitiated');Reboot=($type -eq 'UnexpectedRestart');
 Failure=($type -in @('UpdateFailed','SqlStopped','AgentStopped','UnexpectedRestart'))} -NonQuery
   $incident=$newIncident
  } else {$incident=[guid]$result.Tables[1].Rows[0].IncidentId}
  Invoke-Db $CentralSqlInstance $CentralDatabase @'
UPDATE dbo.ServerPatchMonitorState SET LastEventTime=@When,EventSummary=@Type,
 EventIds=CASE WHEN CHARINDEX(CONVERT(varchar(20),@EventID),EventIds)=0 THEN CONCAT(EventIds,',',@EventID) ELSE EventIds END,
 PatchStarted=CASE WHEN @Type='UpdateStarted' THEN 1 ELSE PatchStarted END,
 PatchSucceeded=CASE WHEN @Type='UpdateSucceeded' THEN 1 ELSE PatchSucceeded END,
 PatchFailed=CASE WHEN @Type='UpdateFailed' THEN 1 ELSE PatchFailed END,
 ShutdownInitiated=CASE WHEN @Type='ShutdownInitiated' THEN 1 ELSE ShutdownInitiated END,
 RebootDetected=CASE WHEN @Type='UnexpectedRestart' THEN 1 ELSE RebootDetected END,
 FirstFailureTime=CASE WHEN FirstFailureTime IS NULL AND @Failure=1 THEN SYSUTCDATETIME() ELSE FirstFailureTime END,
 LastUpdated=SYSUTCDATETIME() WHERE ServerName=@Server AND IncidentId=@Incident;
'@ @{When=[datetime]$e.TimeCreated;Type=$type;EventID=$id;Failure=($type -in @('UpdateFailed','SqlStopped','AgentStopped','UnexpectedRestart'));Server=$server;Incident=$incident;Hash=$hash} -NonQuery
  if($type -in @('UpdateFailed','SqlStopped','AgentStopped','UnexpectedRestart')) {
   Notify $incident $server 'Failure' "PATCH FAILURE: $server - $type" "<html><body><h2>$type</h2><p>$server</p><p>$msg</p></body></html>"
  }
  Invoke-Db $CentralSqlInstance $CentralDatabase "UPDATE dbo.ServerPatchEventLedger SET ProcessedAt=SYSUTCDATETIME() WHERE EventHash=@Hash;" @{Hash=$hash} -NonQuery
 }

 $active=Invoke-Db $CentralSqlInstance $CentralDatabase "SELECT ServerName,IncidentId,FirstFailureTime FROM dbo.ServerPatchMonitorState WHERE RecoveryStatus<>'Recovered';"
 foreach($r in $active.Rows) {
  $server=[string]$r.ServerName
  $cfg=Invoke-Db $CentralSqlInstance $CentralDatabase @'
SELECT TOP(1) InstanceName FROM dbo.PatchSchedule WHERE ServerName=@Server ORDER BY PatchDate DESC;
'@ @{Server=$server}
  $instance=if($cfg.Rows.Count){[string]$cfg.Rows[0].InstanceName}else{''}
  $sql=Get-ServiceState $server (Service-Name $instance 'SQL')
  $agent=Get-ServiceState $server (Service-Name $instance 'Agent')
  $ssis=Get-ServiceState $server (Service-Name $instance 'SSIS')
  $ssrs=Get-ServiceState $server (Service-Name $instance 'SSRS')
  $ok=($sql -eq 'Running' -and $agent -eq 'Running')
  $first=$null;if($null -ne $r.FirstFailureTime -and $r.FirstFailureTime -isnot [DBNull]){$first=([datetime]$r.FirstFailureTime)}
  $escalate=(!$ok -and $first -and (([datetime]::UtcNow-$first).TotalHours -ge $EscalationHours))
  Invoke-Db $CentralSqlInstance $CentralDatabase @'
UPDATE dbo.ServerPatchMonitorState SET SQLServiceStatus=@SQL,AgentServiceStatus=@Agent,
 SSISServiceStatus=@SSIS,SSRSServiceStatus=@SSRS,
 RecoveryStatus=CASE WHEN @OK=1 THEN 'Recovered' ELSE 'Monitoring' END,
 GaveUpNotified=CASE WHEN @Escalate=1 THEN 1 ELSE GaveUpNotified END,
 LastCheckedTime=SYSUTCDATETIME(),LastUpdated=SYSUTCDATETIME()
WHERE ServerName=@Server AND IncidentId=@Incident;
'@ @{SQL=$sql;Agent=$agent;SSIS=$ssis;SSRS=$ssrs;OK=$ok;Escalate=$escalate;Server=$server;Incident=[guid]$r.IncidentId} -NonQuery
  if($ok) {
   $html="<html><body><h2>Recovered: $server</h2><p>SQL=$sql; Agent=$agent; SSIS=$ssis; SSRS=$ssrs</p><p>Service recovery does not certify database/job health.</p></body></html>"
   Notify ([guid]$r.IncidentId) $server 'Recovery' "PATCH RECOVERED: $server" $html
  }
  if($escalate) {
   Notify ([guid]$r.IncidentId) $server 'ManualAttention' "MANUAL ATTENTION: $server" "<html><body><h2>Manual attention required</h2><p>$server SQL=$sql Agent=$agent</p></body></html>"
  }

 }
} finally {
 if($lock.State -ne 'Closed') {
  try{$u=$lock.CreateCommand();$u.CommandText="EXEC sys.sp_releaseapplock @Resource=N'CentralPatchMonitor',@LockOwner='Session';";[void]$u.ExecuteNonQuery()}catch{}
  $lock.Close()
 }
 $lock.Dispose()
}

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Server,
    [int]$Port = 1433,
    [string]$Database = 'master',
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$TrustServerCertificate,
    [int]$TimeoutSeconds = 5
)
$ErrorActionPreference = 'Stop'

Write-Host 'DNS resolution'
try { Resolve-DnsName -Name $Server -ErrorAction Stop | Select-Object Name,Type,IPAddress }
catch { Write-Warning "DNS lookup failed: $($_.Exception.Message)" }

Write-Host 'TCP connection'
$tcp = Test-NetConnection -ComputerName $Server -Port $Port -InformationLevel Detailed
$tcp | Select-Object ComputerName,RemoteAddress,RemotePort,NameResolutionSucceeded,TcpTestSucceeded
if (-not $tcp.TcpTestSucceeded) { throw "TCP $Server`:$Port is unreachable." }

$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']="$Server,$Port"; $builder['Initial Catalog']=$Database
$builder['Application Name']='DBA Connectivity Test'; $builder['Connect Timeout']=$TimeoutSeconds
$builder['Encrypt']=$true; $builder['TrustServerCertificate']=[bool]$TrustServerCertificate
if ($Credential) { $builder['User ID']=$Credential.UserName; $builder['Password']=$Credential.GetNetworkCredential().Password }
else { $builder['Integrated Security']=$true }

$connection=[System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
 $connection.Open(); $command=$connection.CreateCommand()
 $command.CommandText=@'
SELECT @@SERVERNAME AS server_name,DB_NAME() AS database_name,SUSER_SNAME() AS login_name,
       auth_scheme,encrypt_option,net_transport,client_net_address,local_net_address,local_tcp_port
FROM sys.dm_exec_connections WHERE session_id=@@SPID;
'@
 $reader=$command.ExecuteReader();$table=[System.Data.DataTable]::new();$table.Load($reader);$table|Format-Table -AutoSize
} catch { throw "SQL login/query failed after TCP succeeded: $($_.Exception.Message)" }
finally { if($connection.State-ne[System.Data.ConnectionState]::Closed){$connection.Close()};$connection.Dispose() }

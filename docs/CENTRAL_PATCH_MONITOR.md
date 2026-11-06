# Central Patch Monitor

## Contents
- scripts/patch-monitor/CentralPatchMonitor.ps1
- scripts/patch-monitor/CentralPatchMonitor_SQLObjects.sql

## Design
Runs from a SQL Agent PowerShell subsystem step every 15 minutes. Reads all recent rows from
dbo.ServerEventLogs, fingerprints events with SHA-256, records unique events, maintains one
active incident per Windows server, checks SQL Server and SQL Agent service state every cycle,
and sends failure/recovery/manual-attention notifications. A session-owned sp_getapplock
prevents overlapping runs.

## Required source schema
The script expects dbo.ServerEventLogs columns:
YearWeek, ServerName, LogName, EventID, TimeCreated, Message, StatusCategory.
It expects dbo.PatchSchedule columns: ServerName, InstanceName, PatchDate.
**Verify these exact names and data types in DBAUtility before deployment.**
The schedule lookup chooses the latest PatchDate row for a server. The state key is ServerName,
so this version supports one monitored SQL instance per Windows server. Multi-instance hosts
need a composite (ServerName, InstanceName) incident key and corresponding workflow changes.

## Event classification
1074 planned shutdown initiation; 41/6008 unexpected restart evidence; 6006/6005 event-log
service stop/start; 43 update started; 19 update succeeded; 20 update failed; 7036 is parsed
from Message for SQL Server, SQL Agent, SSIS, and SSRS state changes. Event ID alone is not
enough to classify 7036.

## Notification behavior
Implements both_failure: sends immediate failure notices and recovery notices, plus one
manual-attention notice after the configured escalation interval. Informational update start
and success events are recorded but do not send individual emails. Recovery means SQL Server
and SQL Agent are Running; absent SSIS/SSRS services are NotConfigured and do not block it.

## Setup
1. Run the SQL object script in DBAUtility.
2. Edit SMTP/server/recipient parameters in the SQL Agent job step.
3. Create the DPAPI password file under the SQL Agent service identity:
   Read-Host -AsSecureString | ConvertFrom-SecureString | Set-Content C:\SQLAgent\Secrets\PatchMonitorSmtpPassword.txt
4. Grant the Agent identity SQL read/write permissions to the monitor objects and read access
   to source tables. Grant remote CIM/WinRM query permissions on each monitored server.
5. Use -SuppressEmail to exercise event/state processing without sending email. This is **not** a dry run: it still reads and writes monitor tables. Test on a non-production database/server before enabling the 15-minute schedule.
6. Use PowerShell subsystem, not CmdExec. Ensure the SQL Agent service identity can read the
   script and secret file.

## Known boundaries to resolve before production
- TimeCreated is filtered against central SQL GETDATE(); confirm both use compatible local
  time semantics. No conversion to UTC is assumed for source event timestamps.
- SHA-256 deduplication does not include Windows EventRecordID because the source schema listed
  does not expose it. Add EventRecordID to the collector/source if possible.
- Notification mail is sent before its SQL log row is inserted; a mail success followed by
  database insert failure can cause a duplicate on retry.
- Health checks are currently service-state focused. Database state, disk capacity, and Agent
  job history checks are not yet included in this rebuilt baseline.
- FirstFailureTime is incident-level; confirm the desired timeout semantics for patch-start-only
  events. Reboot event correlation against OS boot time is not yet implemented.
- This repository build has been statically reviewed only. It has not been executed against the
  actual SQL schema, Windows CIM endpoints, SQL Agent identity, or SMTP relay.

## Acceptance tests
- Confirm actual PatchSchedule and ServerEventLogs schema.
- Run SQL DDL and verify all four objects exist.
- Test default and named-instance service names.
- Test Event IDs 1074, 41, 19, 20, and multiple 7036 message variants.
- Test duplicate event ingestion and 10-server concurrent failure/recovery behavior.
- Verify 9 recovered servers close while the 10th remains monitored.
- Verify exactly one failure, recovery, and escalation email per incident.
- Verify SQL Agent account, CIM permissions, SMTP credentials, and timezone behavior.

# Validation matrix

| File | Expected level | CI scenario |
|---|---|---|
| `scripts/core/00_First_Response.sql` | EXECUTED-CI | Run after lab setup |
| `scripts/core/01_Connections_Authentication.sql` | EXECUTED-CI | Run against container instance |
| `scripts/core/02_Blocking_Deadlocks.sql` | EXECUTED-CI | Run during a real blocking pair and after a deadlock |
| `scripts/core/03_CPU_Plans_QueryStore.sql` | EXECUTED-CI | Run with populated plan cache and Query Store |
| `scripts/core/04_Memory_IO_Tempdb.sql` | EXECUTED-CI | Run against active instance |
| `scripts/core/05_Storage_Backup_Recovery.sql` | EXECUTED-CI | Run after full backup and restore |
| `scripts/core/06_Integrity_Security.sql` | EXECUTED-CI | Run before and after permission restore test |
| `scripts/core/07_Log_Transactions.sql` | EXECUTED-CI | Inspect log statistics and active transactions |
| `scripts/core/08_Index_Statistics.sql` | EXECUTED-CI | Inspect current database metadata/DMVs |
| `scripts/core/09_Configuration_Capacity.sql` | EXECUTED-CI | Inspect instance configuration and counters |
| `scripts/specialized/AlwaysOn_AG_Health.sql` | PARSED-CI, LAB-REQUIRED | Parse on 2022; functional test requires multi-node AG |
| `scripts/specialized/SQL_Agent_Operations.sql` | PARSED-CI, LAB-REQUIRED | Parse on 2022; Linux container has no Agent service |
| `scripts/specialized/Replication_CDC_ChangeTracking.sql` | PARSED-CI, LAB-REQUIRED | Functional test requires configured topology/features |
| `scripts/specialized/Encryption_TDE.sql` | PARSED-CI, LAB-REQUIRED | Functional test requires TDE/key lifecycle lab |
| `scripts/specialized/MSDB_DatabaseMail.sql` | PARSED-CI, LAB-REQUIRED | Functional test requires Database Mail/SMTP |
| `powershell/Test-SqlConnectivity.ps1` | PARSED-CI, LAB-REQUIRED | PowerShell AST parse; functional test must run from the affected client network path |
| `lab/00_Setup.sql` | EXECUTED-CI | Creates lab, skew, Query Store, CHECKDB |
| `lab/01_Blocker_Session.sql` | EXECUTED-CI | Background blocker |
| `lab/02_Blocked_Session.sql` | EXECUTED-CI | Waits on blocker and completes |
| `lab/03_Deadlock_Session_A.sql` | EXECUTED-CI | Opposite update order |
| `lab/04_Deadlock_Session_B.sql` | EXECUTED-CI | Opposite update order |
| `lab/05_Backup_Restore_Permissions.sql` | EXECUTED-CI | CHECKSUM backup/verify/restore, CHECKDB, SID/role/grant assertions |
| `lab/99_Cleanup.sql` | EXECUTED-CI | Removes only named lab objects |

The Actions run is the source of truth. A green workflow proves execution only for the image digest/build used by that run; it does not prove every production topology, edition, permission set or workload.

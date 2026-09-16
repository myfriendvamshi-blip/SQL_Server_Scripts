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
| `scripts/refresh/00_Install_DevSecuritySnapshot.sql` | EXECUTED-CI | Install capture/apply engine in external DBA_Admin database |
| `scripts/refresh/01_Capture_DEV_Security.sql` | PARSED-CI | SQLCMD operator template; capture procedure is executed by lab 06 |
| `scripts/refresh/02_Backup_PROD_Database.sql` | PARSED-CI | SQLCMD operator template; equivalent backup is executed by lab 06 |
| `scripts/refresh/03_Restore_PROD_Over_DEV_And_Reapply_Security.sql` | PARSED-CI | SQLCMD operator template; equivalent restore/apply is executed by lab 06 |
| `lab/06_Clean_DEV_Security_Refresh.sql` | EXECUTED-CI | Restore PROD data over DEV, remove PROD user/role/public grant, replay DEV user/roles/owners/object+column permissions |
| `lab/99_Cleanup.sql` | EXECUTED-CI | Removes only named lab objects |

The Actions run is the source of truth. A green workflow proves execution only for the image digest/build used by that run; it does not prove every production topology, edition, permission set or workload.

## Issue #3 Phase 1 increment

These are the workflow's coverage contracts, not a claim that every listed scenario
has passed. Consult the PR's exact SHA/run result. The workflow prints the image digest
and SQL build. It does not publish a SQL port or accept an external SQL endpoint.

| File | Execution path | Explicit limits |
|---|---|---|
| `scripts/scenarios/01_Access.sql` | Lab 07 executes before/after real SID remap; asserts alias, disabled login, orphan, WITHOUT LOGIN | No real login-failure state, contained-password, AD or Entra tests |
| `scripts/scenarios/02_Recovery_Evidence.sql` | Lab 08 executes source and restored-copy inventories; asserts differential UUID and checksum flags | Inventory, not automated chain selection; no damaged/fork/stripe/TDE tests |
| `scripts/scenarios/03_Restore_Dependencies.sql` | Lab 07 executes every query; asserts cross-database view reference | Agent/proxy/TDE/linked server branches may return empty; integrations LAB-REQUIRED |
| `scripts/scenarios/04_Integrity_Evidence.sql` | Lab 07 executes healthy metadata/suspect-page query; separate CHECKDB | No 823/824/825 reproduction or repair |
| `scripts/scenarios/05_Security_Evidence.sql` | Lab 07 executes queries; asserts object deny, column grant and effective permission | Empty Audit configuration path only; not forensic event attribution or full drift engine |
| `lab/07_Phase1_Evidence.sql` | Disposable fixtures, assertions, SID remap, CHECKDB, cleanup | Mutation permitted in isolated CI only |
| `lab/08_Phase1_PITR.sql` | Full + differential + log, actual STOPAT restore, row inclusion/exclusion and CHECKDB | Positive single-file FULL-recovery case only |
| `tests/phase1_guards.sh` | Two opt-out errors, two fixture-collision errors, four metadata-denial errors; exact error numbers asserted | Eight refusal tests, not environment authentication; local bash syntax check only |

The pre-existing 10 core SQL collectors are executed by the unchanged suite. Five
specialized SQL collectors and three refresh operator templates are **PARSED ONLY**;
the PowerShell connectivity script receives AST parsing only. The refresh engine and
lab 06 execute, but not the operator templates. See [safety review](REFRESH_SAFETY_REVIEW.md).

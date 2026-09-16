# Phase 1: access, recovery and security evidence

Increment for issue #3, 2026-09-16. These are scenario-specific evidence collectors,
not a universal repair system. Open a query connection to the affected **user database**
and execute the relevant `scripts/scenarios` file. Save results privately with the
incident time, instance, database and collector commit. Never publish customer names,
SIDs, paths or audit output to a public issue. All SQL in this increment is original;
no upstream implementation is vendored.

## Safety and prerequisites

| Module | Scope and prerequisites | Classification |
|---|---|---|
| 01 Access | SQL Server 2022; server VIEW ANY DEFINITION and database VIEW DEFINITION | READ-ONLY; temp-table output; no login changes |
| 02 Recovery evidence | SELECT on msdb backupset, backupmediafamily, restorehistory | READ-ONLY; history scan can be large; no media access |
| 03 Restore dependencies | sysadmin required by this conservative implementation | READ-ONLY; metadata only, no linked-server connection |
| 04 Integrity evidence | database VIEW DEFINITION; SELECT on msdb suspect_pages | READ-ONLY; no CHECKDB or repair |
| 05 Security evidence | sysadmin required by this conservative implementation | READ-ONLY; current-state snapshot, not effective access proof |
| Lab 07 and 08 | disposable SQL Server 2022 Developer CI container, sysadmin, explicit opt-in | DESTRUCTIVE-LAB-ONLY; create/drop fixed fixture objects, write backups |

The sysadmin gates are implementation prerequisites, not claims that sysadmin is the
theoretical least privilege. Do not grant sysadmin to an application or auditor for
these scripts: ask an authorized DBA to capture evidence. Limited visibility must not
be interpreted as missing identities or dependencies. Metadata queries still consume
resources and can wait for schema locks. Schedule history scans appropriately.
Only SQL Server 2022 Developer Linux is execution-tested by this workflow; other
editions, Windows integration, Azure SQL, MI and RDS remain separately unvalidated.

## 01 — Login 18456, default database and SID mapping

1. Record the complete client error, timestamp/timezone, endpoint, authentication type,
   initial catalog and driver version. Do not record the password. Confirm the intended
   instance before resetting anything.
2. Ask an authorized DBA to correlate the matching SQL error-log **reason and state**.
   Client state 1 is not a reliable root cause. Error-log access on SQL Server 2022
   requires the appropriate VIEW ANY ERROR LOG permission; archived logs may be needed.
3. Run `01_Access.sql` in the requested database. It maps SIDs rather than names and
   separates instance-authenticated orphans from contained/no-login identities.
4. Route by evidence:

   | Server-side evidence | Next check | Approved repair and rollback |
   |---|---|---|
   | 2/5: invalid identity; 8: password mismatch | intended instance/login and credential source | correct client secret through secret management; do not guess passwords |
   | 7: disabled login/password issue | is_disabled plus server reason | enable only if approved; record prior state and disable again on rollback |
   | 11/12: server access failure | CONNECT SQL, denies, group token | correct exact permission; preserve prior grant/deny for rollback |
   | 18: password must change | application support for password rotation | approved credential rotation, not disabling policy |
   | 38/46 or error 4064: requested/default DB unavailable | exact reason, initial catalog, default DB, state, mapping | restore database access or correct catalog/default; save prior default |
   | 58: SQL authentication against Windows-only configuration | actual endpoint and auth mode | use intended auth path; do not casually switch mode/restart |

5. An `ORPHAN_CANDIDATE` requires identity-owner confirmation. If the correct login
   exists, review `ALTER USER [user] WITH LOGIN = [approved_login]` in that database.
   Preserve the original SID/mapping and permissions before change; rollback requires
   the previous approved login/SID, not dropping the user. Lab 07 executes a remap and
   asserts that principal_id survives. No remediation is embedded in the collector.
6. Contained users need the database in the connection string and containment enabled;
   absence of an instance login is normal. A Windows identity may authenticate through
   a group: no direct SID match does not prove an orphan. Do not auto-map by name.
7. Validate from the affected application identity and client path. A sysadmin query
   succeeding does not demonstrate application access.

LAB-REQUIRED: real failed-auth state reproduction, contained-password authentication,
Windows groups/Kerberos, Entra and client TLS. The current lab asserts catalog-based
alias/orphan/disabled/no-login classifications, not successful end-to-end login repair.

## Connectivity evidence pack — manual, LAB-REQUIRED

Capture from the affected client: UTC/timezone, FQDN/listener and explicit TCP port,
DNS answers, TCP reachability, driver name/version, encryption and certificate-validation
settings, certificate chain/expiry/SAN hostname, auth type, and initial catalog. Redact
connection secrets. On Windows, read-only `Resolve-DnsName`, `Test-NetConnection`,
`klist` and an authorized `setspn -Q MSSQLSvc/host:port` lookup can separate DNS/TCP
from Kerberos issues. Do not run SPN add/delete or ticket purge during evidence gathering.
Check the actual application session's `sys.dm_exec_connections` transport, encrypt_option
and auth_scheme using the existing core collector; a local sysadmin connection is not
a delegation test. A TCP success is not TLS or SQL authentication success. Do not
"fix" certificate failures by recommending TrustServerCertificate in production.
The CI `-C` switch is only for the isolated container's certificate.

## 02 — Backup chain, PITR and tail-log decisions

1. Agree on the target database, required recovery point/timezone, allowable data loss
   and separate restore destination. Preserve evidence and existing backup files.
2. Run `02_Recovery_Evidence.sql`. Review full/differential/log sets, UUID-based
   differential parent, LSN ranges, database family, recovery forks, checksum/damage
   flags, encryption thumbprint, media position and **all stripes** for one mirror.
   No history rows means unavailable local evidence, not no backups.
3. This is an inventory, **not a chain-selection algorithm**. Validate actual media
   HEADERONLY/FILELISTONLY, media positions, file destinations, keys and capacity.
   History paths may have moved; UUID/LSN metadata is not proof that bytes are readable.
   Do not pick the latest full solely by date: it may postdate the requested point.
   A copy-only full is not a new differential base. Multibased differentials require
   file-level analysis. Fork transitions require lineage review; do not join different
   database families or insist log ranges are always strictly adjacent without overlap.
4. For FULL/BULK_LOGGED, evaluate tail-log capture **before** restore if unbacked log
   is needed. NORECOVERY makes the source unavailable. Damaged/offline databases need
   a separate DBA-approved strategy; do not blindly use CONTINUE_AFTER_ERROR or
   NO_TRUNCATE. SIMPLE has no transaction-log backup chain. Bulk-logged operations can
   prevent stopping inside a log backup. Do not change recovery model to solve this.
5. Rehearse on a new isolated destination: full WITH NORECOVERY, compatible differential
   WITH NORECOVERY if used, required logs in order, and STOPAT on the applicable log
   restore(s). Recover only when the target is reached. Do not use WITH REPLACE on a
   live source. If the rehearsal is wrong, drop only the isolated copy and start over;
   there is no transactional rollback of a completed overwrite restore.
6. Check row/business markers, CHECKDB results and application behavior. VERIFYONLY
   alone is not an end-to-end recovery test. Lab 08 exercises a full + differential +
   log restore with STOPAT, checks that the later row is absent, and executes CHECKDB.

Remaining recovery tests: missing log/stripe, damaged tail-log, copy-only selection,
fork transition, encrypted backup/TDE keys, file/filegroup and bulk-logged variants.
No automatic production restore planner is delivered in this increment.

## 03 — Post-restore dependencies

1. Run `03_Restore_Dependencies.sql` on the isolated restored copy before reconnecting
   applications. Review owner, TRUSTWORTHY/chaining, synonyms, explicit cross-database
   and cross-server references, EXECUTE AS, jobs, proxy/credential identities,
   linked-server flags, endpoints and encryption metadata.
2. Compare with an approved destination inventory. Logins, server grants, Agent objects,
   linked servers and key material are not supplied by a user-database restore.
   A matching certificate name is insufficient: confirm thumbprint and usable private key.
3. System-object references, dynamic SQL, connection strings, SSIS packages, external schedulers and cross-database
   references hidden in modules may escape dependency metadata. Job commands are
   deliberately omitted because they can contain secrets; steps with another database
   context may still reference the target. This is a lead list, not completeness proof.
4. Recreate only approved dependencies through separate change control. Do not copy
   production credentials or enable TRUSTWORTHY as a shortcut. Save before-state and
   rollback each dependency individually; validate under real destination identities.

LAB-REQUIRED: Agent execution/proxies, remote linked servers, TDE/key restore, delegation,
SSIS and external services. Lab 07 executes catalog queries and asserts one real
cross-database reference; it does not test those integrations.

## 04 — 823/824/825 and CHECKDB

1. Preserve SQL error logs, OS/storage events, timestamps, database/file/page/offset and
   recent infrastructure changes. 823 is an OS I/O failure; 824 is logical I/O validation
   failure; 825 is a read that succeeded after retry and still demands investigation.
2. Run `04_Integrity_Evidence.sql`. Correlate suspect pages with the affected files and
   storage. An empty table or an old LastGoodCheckDbTime does not prove current health.
3. Engage storage/platform owners. With an approved impact window, run CHECKDB on an
   isolated restored copy first where feasible; PHYSICAL_ONLY is not a substitute for
   all logical checks. CHECKDB can be expensive in CPU, I/O and tempdb.
4. Prefer tested restore from known-good backups; review page restore feasibility with
   recovery model/edition/topology specialists. Check backups and the entire storage path.
   Do not detach a suspect database, delete logs, or run emergency repair blindly.
5. REPAIR_ALLOW_DATA_LOSS is a last-resort, separately approved data-loss decision, not
   a collector action. Preserve a copy and seek Microsoft support before irreversible work.
   Restore/repair has no simple undo: retain original evidence and rollback media.

Current lab: healthy database metadata and CHECKDB only. No corrupted page is injected,
and no 823/824/825 incident or repair is claimed tested.

## 05 — Permission drift and forensic evidence

1. Capture `05_Security_Evidence.sql` plus module 03's ownership/EXECUTE AS evidence.
   Compare against a protected baseline from the same scope and known timestamp.
2. Compare exact tuples (database, grantee, grantor, securable/class, column, permission,
   state), memberships and owners, not just row counts. Resolve object IDs to names
   across restores. Catalog grants alone do not express fixed-role, sysadmin, nested
   Windows groups, ownership chaining, signed-module or EXECUTE AS effective access.
3. Preserve existing Audit/XE files and collection retention details. Catalog create/
   modify times and current audit configuration cannot identify who made a past change.
   If the event was never captured, explicitly report attribution as unknown. Do not
   purge or recycle logs; do not enable a new audit and imply it reconstructs history.
4. Review precise grant/revoke/deny changes with the security owner, record before-state,
   test using the affected identity, then apply through change control. Roll back using
   the saved exact tuple. Column grants can override object denies; lab 07 asserts that
   behavior, demonstrating why simplistic "DENY always wins" advice is unsafe.

This increment provides snapshots, not a persistent drift diff engine or audit-file
parser. Audit emission/collection, signed modules and nested role paths remain untested.

## Sources and mature-tool comparison

Reviewed 2026-09-16. Follow linked primary documentation; no source code is copied.

The guard suite also checks eight expected-error paths: two opt-out gates, two existing
fixture collisions (including preserving a sentinel row), and four limited-login metadata
denials. It checks the exact SQL error number so an unrelated connection failure cannot
be reported as a successful guard. These checks still do not attest a real environment.

- Microsoft: [orphaned users](https://learn.microsoft.com/en-us/sql/sql-server/failover-clusters/troubleshoot-orphaned-users-sql-server),
  [18456](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-18456-database-engine-error),
  [backupset](https://learn.microsoft.com/en-us/sql/relational-databases/system-tables/backupset-transact-sql),
  [tail-log backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/tail-log-backups-sql-server),
  [823](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-823-database-engine-error),
  [824](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-824-database-engine-error),
  [database permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-database-permissions-transact-sql).
- [dbatools Test-DbaLastBackup](https://dbatools.io/Test-DbaLastBackup/) performs actual
  restore and CHECKDB; our inventory cannot replace it. Explicitly supply a disposable
  destination when evaluating it: its documented default can use the source instance.
  [Repair-DbaDbOrphanUser](https://dbatools.io/Repair-DbaDbOrphanUser/) is remediation,
  unlike our read-only classification. Its reviewed implementation selects eligible
  same-name logins; our lab includes a differently named alias to test SID-based
  evidence rather than automatic name-based repair. Review parameters and identities before use.
  Reviewed source: [Repair-DbaDbOrphanUser](https://github.com/dataplat/dbatools/blob/development/public/Repair-DbaDbOrphanUser.ps1)
  (blob `ad200f185c4ee6a833b167aabfa2020e9a3d167d`) and
  [Test-DbaLastBackup](https://github.com/dataplat/dbatools/blob/development/public/Test-DbaLastBackup.ps1)
  (blob `c1b85526d7756de597e52f9714e4f2f7090517aa`).
  dbatools is [MIT-licensed](https://github.com/dataplat/dbatools/blob/development/license); preserve notices if code is ever incorporated. Pin and review
  a release/commit before installing; no external tools are installed by this increment.
- [Ola Hallengren](https://github.com/olahallengren/sql-server-maintenance-solution)
  provides mature backup/integrity scheduling and logging, not incident attribution.
  Prefer a separately reviewed deployment over extending these evidence scripts into
  an untested maintenance scheduler. Respect the upstream MIT license/notices.

See [refresh safety review](REFRESH_SAFETY_REVIEW.md) before considering the old refresh
workflow. Its passing example must not be interpreted as production approval.

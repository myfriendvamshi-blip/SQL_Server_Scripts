# SQL Server DBA Expert Toolkit

An evidence-driven SQL Server 2022 troubleshooting library for senior and lead DBAs. The toolkit separates **observation**, **reproduction**, and **remediation** so that a diagnostic query cannot silently change production state.

## Quick start

1. Start with [`scripts/core/00_First_Response.sql`](scripts/core/00_First_Response.sql).
2. Run the subject-specific collector from `scripts/core`.
3. Use `scripts/specialized` only when its prerequisites are satisfied.
4. Reproduce the symptom in the disposable scripts under `lab`; never run lab scripts in production.
5. Read [`docs/DECISION_TREE.md`](docs/DECISION_TREE.md) for symptom-to-script routing.

## Coverage

| Area | Included |
|---|---|
| Emergency triage | instance state, active requests, waits, blocking, errors, backup exposure |
| Connectivity | listener endpoint, sessions, transport, TLS, authentication, login failures |
| Performance | CPU, waits, plan cache, Query Store, memory grants, schedulers, I/O latency |
| Concurrency | blocking chains, sleeping blockers, open transactions, deadlock XE setup/parser |
| Storage | database files, volumes, VLFs, log reuse, tempdb allocation and version store |
| Recovery | backup chain, restore planning, progress, orphan detection, permission validation |
| HA/DR | AG replica/database state, queues, rates, RPO/RTO indicators, cluster notes |
| Integrity | suspect pages, CHECKDB history, corruption evidence and safe response order |
| Security | principals, role membership, explicit permissions, orphaned users, impersonation |
| Operations | Agent failures, schedules, owners, long-running jobs, capacity and configuration |

## Safety contract

- Core collectors are read-only.
- Remediation is not automatic. Generated commands are output for review.
- No production collector runs `KILL`, `DBCC ... REPAIR_ALLOW_DATA_LOSS`, `DROP DATABASE`, cache-clearing commands, shrink, failover, or server reconfiguration. Lab setup/cleanup drops only the explicitly named disposable lab databases.
- Lab scripts abort unless the database is named `DBA_Toolkit_Lab`.
- Test artifacts are disposable and isolated inside GitHub Actions SQL Server 2022 Developer Edition.

## Validation levels

| Level | Meaning |
|---|---|
| `EXECUTED-CI` | Executed with `sqlcmd -b` against SQL Server 2022 Developer Edition in Actions |
| `PARSED-CI` | Parsed by SQL Server 2022 but not functionally executable in a single Linux container |
| `REVIEWED` | Checked against Microsoft documentation and catalog/DMV contracts |
| `LAB-REQUIRED` | Requires SQL Agent, Windows/WSFC, AG replicas, SSIS, or external infrastructure |

See [`docs/VALIDATION_MATRIX.md`](docs/VALIDATION_MATRIX.md) for per-file evidence.

## Open-source position

This repository does not copy mature tools and pretend to improve them. Use pinned, reviewed releases of:

- [First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) for `sp_Blitz*`, deadlock, cache, index, and first-response analysis.
- [Ola Hallengren Maintenance Solution](https://github.com/olahallengren/sql-server-maintenance-solution) for backup, CHECKDB, index/statistics maintenance, and command logging.
- [dbatools](https://github.com/dataplat/dbatools) for instance migrations and repeatable PowerShell administration.
- [Microsoft Tiger Toolbox](https://github.com/microsoft/tigertoolbox) for Microsoft field-engineering diagnostics.
- [DarlingData](https://github.com/erikdarlingdata/DarlingData) for Query Store, pressure, XE, and performance procedures.

Review licenses and pin a release/commit before production deployment. See [`docs/OPEN_SOURCE_COMPARISON.md`](docs/OPEN_SOURCE_COMPARISON.md).

## Supported target

Primary target: SQL Server 2022 (16.x), Windows or Linux. Most read-only collectors also work on SQL Server 2016–2019, but CI proves SQL Server 2022 only. Azure SQL Database, Azure SQL Managed Instance, and Amazon RDS have different DMV and feature surfaces; validate before use.

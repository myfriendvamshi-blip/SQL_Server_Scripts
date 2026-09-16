# Phase 1 validation evidence — 2026-09-16

Partial implementation for [issue #3](https://github.com/myfriendvamshi-blip/SQL_Server_Scripts/issues/3),
submitted in [PR #4](https://github.com/myfriendvamshi-blip/SQL_Server_Scripts/pull/4).
Issue completion and production readiness are **not** claimed. Nothing was merged.

## First green implementation run

- Implementation commit: `05e85a3344e48d9abb5e28186ae5a510a2f319f7`.
- [Successful PR workflow](https://github.com/myfriendvamshi-blip/SQL_Server_Scripts/actions/runs/35090286717).
- [Job with SQL output and assertions](https://github.com/myfriendvamshi-blip/SQL_Server_Scripts/actions/runs/35090286717/job/104774719461).
- SQL Server 2022 Developer Linux, RTM-CU27, build `16.0.4295.3` as reported by @@VERSION.
- Image: `mcr.microsoft.com/mssql/server@sha256:4402d880dd4c34bfa7d8705e56a86cd6c88da80a1f6bbbe741f999e76264a090`.
- Runtime uses `2022-latest`; future runs may use another build. The recorded digest
  identifies this test only, not a supported-build certification.
- No external SQL endpoint or production/development credentials were used. All SQL
  connections were docker exec to localhost in an ephemeral Actions container with no
  published SQL port. Container and backup volume were destroyed after the job.

## Executed versus parsed

| Surface | Actual evidence |
|---|---|
| Five new scenario collectors | Executed by labs 07/08, not merely parsed |
| Access | SID-based alias match, real orphan via dropped login, disabled login, WITHOUT LOGIN; actual ALTER USER remap preserves principal_id |
| Recovery | Full/differential/log metadata; actual full + differential + log STOPAT restore; exactly two pre-target rows, later row excluded; CHECKDB |
| Dependencies | All queries executed; real cross-user-database view reference asserted; remote/Agent/TDE surfaces not functionally exercised |
| Integrity | Healthy metadata and empty suspect_pages path; CHECKDB on healthy fixtures; no corruption injected |
| Security | Object DENY, column GRANT and effective column permission asserted; no audit event emission/forensic attribution test |
| Eight refusal cases | Two explicit opt-outs, two fixture collisions, four restricted metadata checks; expected error numbers verified; existing sentinel preserved |
| Existing suite | 10 core collectors executed, blocking/deadlock labs, backup/restore permissions lab, refresh engine and example lab executed |
| SQL parse only | Five specialized collectors and three refresh operator templates; PARSEONLY does not resolve objects or execute dynamic SQL |
| PowerShell parse only | Existing connectivity script AST parsed, not exercised across a real client/network path |
| Local checks | `git diff --check`, `bash -n tests/phase1_guards.sh`; no local SQL Server/Docker runtime available |

Execution of catalog queries that return no rows is not functional coverage of the
corresponding feature. Existing core collectors are invoked in the suite's default
connection context; passing that invocation does not prove every user-database branch.

## Failures found and corrected before green

1. Azure-style CREATE USER SID/TYPE syntax did not parse on SQL Server 2022: replaced
   with create-login/create-user/drop-login to reproduce a real orphan.
2. Incorrect server class argument in HAS_PERMS_BY_NAME rejected the privileged test:
   corrected to NULL securable/class and tested low-privilege rejection separately.
3. System-view reference was not tracked in sys.sql_expression_dependencies: replaced
   the fixture with a cross-user-database reference and documented this metadata blind spot.

## Remaining work

Phase 1 remains open: full contained/Windows/Entra authentication reproductions;
client DNS/TLS/SPN integration; automated chain selection and negative recovery cases;
tail-log/fork/stripe/TDE scenarios; dependency integrations; corrupted-page incidents;
persistent permission drift comparison and forensic event ingestion. The existing
refresh workflow needs the hardening described in [its safety review](REFRESH_SAFETY_REVIEW.md).
Phases 2–4 still need scenario-specific expansion. See [runbooks](PHASE1_RUNBOOKS.md)
and [coverage matrix](VALIDATION_MATRIX.md) for each limitation.

Subsequent warning-comment/documentation commits do not expand runtime coverage.
Always review the latest PR-head Actions result before considering a merge.

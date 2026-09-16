# PROD-to-DEV refresh with clean DEV security

## Outcome

> **Safety qualification (2026-09-16):** This is an experimental destructive workflow,
> not a production-approved isolation mechanism. Read [the safety review](REFRESH_SAFETY_REVIEW.md).
> SINGLE_USER is not an access-control boundary; exact permission equivalence is not
> established by counts. The template runs CHECKDB after MULTI_USER, so its failure can
> leave the target open. External isolation is required even if the lab passes.

The workflow intends to restore production **data and database objects** into DEV and replace the tested subset of database security. The existing lab demonstrates a limited SQL-login/role/permission example, not every security surface. It captures DEV security in `DBA_Admin`, overwrites DEV, removes restored principals/permissions and replays the snapshot; review the limitations before use.

A SQL Server database backup always contains database-level security metadata. `RESTORE DATABASE` has no option to exclude users or permissions, so security replacement must happen immediately after recovery.

## Files

| Order | File | Run on |
|---|---|---|
| 0 | `scripts/refresh/00_Install_DevSecuritySnapshot.sql` | DEV, once per server/deployment |
| 1 | `scripts/refresh/01_Capture_DEV_Security.sql` | DEV, immediately before refresh |
| 2 | `scripts/refresh/02_Backup_PROD_Database.sql` | PROD |
| 3 | `scripts/refresh/03_Restore_PROD_Over_DEV_And_Reapply_Security.sql` | DEV during outage |

Use SSMS **Query → SQLCMD Mode** or run the files with `sqlcmd`. Replace every SQLCMD variable before execution.

## Pre-change checklist

1. Confirm the destination is DEV and obtain the change record/approval.
2. Stop DEV application pools, services, Agent jobs, ETL, monitoring probes, and connection pools.
3. Confirm enough disk space for the backup, restore files, and post-restore growth.
4. Confirm every required DEV server login already exists. Database users are recreated against those existing DEV logins by SID.
5. Run step 1 and save the returned `SnapshotId` in the change record.
6. Review the generated commands in `DBA_Admin.dbo.DevSecuritySnapshotCommand`.
7. Run the PROD copy-only backup, copy it to DEV, and grant the DEV SQL Server service account read access.
8. Record rollback paths: the pre-refresh DEV backup, the security `SnapshotId`, and the prior DEV database/file locations.

## Execution and safety behavior

- PROD backup uses `COPY_ONLY`, `COMPRESSION`, `CHECKSUM`, and `RESTORE VERIFYONLY`.
- Restore uses `WITH REPLACE`, `CHECKSUM`, dynamically generated `MOVE` clauses for every data/log file, and an explicit outage.
- Security apply sets the target to `SINGLE_USER`.
- Existing restored permissions—including grants to `public` and fixed roles—are revoked.
- Existing restored role memberships, custom roles, and users are removed.
- DEV users, roles, owners, memberships, grants, denies, grant options, and column exceptions are replayed inside one transaction.
- Principal sets and security row counts are checked before the database is returned to `MULTI_USER`.
- Any replay/validation failure rolls back the security transaction and deliberately leaves the target `SINGLE_USER`.

## Intentional fail-closed limitations

The capture stops instead of silently losing security when it finds:

- contained SQL users whose password hashes cannot be exported through supported catalog views;
- application roles whose passwords cannot be recovered;
- certificate/asymmetric-key mapped users that require key material;
- an instance-mapped DEV user whose server-login SID is missing;
- a permission class unknown to the SQL Server 2022 implementation.

Microsoft Entra users/groups are scripted by name and require a correctly configured Entra-enabled DEV SQL Server. Server-level objects are outside a database backup and must be managed separately: logins, server roles/grants, credentials, proxies, Agent jobs, linked servers, endpoints, certificates used for TDE restore, and SQL Server service permissions.

## Post-refresh validation

1. Confirm `DBA_Admin.dbo.DevSecuritySnapshot.status = 'APPLIED'`.
2. Confirm the target reports `MULTI_USER`, the expected DEV owner, and the required recovery model.
3. Run `DBCC CHECKDB` (step 3 does this after successful security replay).
4. Test DEV application identities and least-privilege access.
5. Search for known PROD login/user/group names and validate that none remain.
6. Validate masking/sanitization requirements for production data before giving developers access. This toolkit replaces security; it does **not** anonymize sensitive production data.
7. Re-enable jobs and applications only after security, data masking, smoke tests, and business validation pass.

## Recovery from a failed replay

Do not manually switch the database to `MULTI_USER`. Read `error_message` in `DBA_Admin.dbo.DevSecuritySnapshot`, correct the missing login/object/key dependency, and rerun:

```sql
EXEC DBA_Admin.dbo.usp_ApplyDevDatabaseSecurity
     @DatabaseName = N'YourDevDatabase',
     @SnapshotId = 'your-snapshot-guid';
```

If the restored schema is incompatible with the DEV permission targets, restore the pre-refresh DEV backup or correct the approved DEV security model before retrying.

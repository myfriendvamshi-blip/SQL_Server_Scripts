# Clean-security refresh: safety review, 2026-09-16

Reviewed existing main commit `253ba88`. Existing tests prove a narrow example, not
an isolation or production-security guarantee. This increment does not reuse the
refresh engine in its new modules and does not certify that engine safe for real data.

## Findings from code inspection

1. `SINGLE_USER` limits connection count, not authorized identity. Another connection
   can take the slot. The operator restores WITH RECOVERY before invoking the apply
   procedure; that sequence is not an atomic access-control boundary. External network/
   identity isolation is required throughout, including failures and data sanitization.
2. The apply procedure validates principal name/type/authentication sets but only counts
   memberships/permissions. Equal counts do not prove equal grants, grantors, SIDs,
   owners, schema defaults or effective permissions. Identity-by-name Entra replay is
   also not a validated SID-preservation mechanism.
3. The procedure returns MULTI_USER before the operator template runs CHECKDB. A
   CHECKDB failure therefore does not imply the target remains SINGLE_USER. A failure
   before apply can also bypass the procedure's intended isolation behavior.
4. The procedure itself does not bind the snapshot's database_name/source_server to
   the target (the operator template checks the database name, not the server).
   Direct procedure calls can bypass that wrapper precondition.
5. Restored executable modules, signatures, EXECUTE AS references, credentials, data,
   feature settings and external access paths are not proven sanitized by the lab.
   Dropping/recreating principals may fail for dependencies the happy-path lacks.
6. Operator templates are PARSED, not executed by lab 06. VERIFYONLY does not validate
   logical consistency or prove a full recovery. Dynamic MOVE assumes ordinary data/log
   files; FILESTREAM/container variants, multi-file/path collisions, escaping and capacity
   need dedicated tests. There is no default-disabled execution switch once variables
   are filled in. Treat the templates as destructive operator code.

## Required before broader use

- Independently enforce isolated destination and deny application/job/network access;
  a database name containing DEV is not an authorization mechanism.
- Bind the capture to the intended server/database and reject mismatches before changes.
- Test complete tuple comparisons and effective-access assertions for the supported
  principal/securable surface, including negative/failure injection and concurrent access.
- Keep the destination externally isolated through CHECKDB, sanitization, identity tests
  and explicit operator release; define rollback from pre-refresh backups.
- Test unsupported identities, keys, missing objects, grant chains, EXECUTE AS and
  interrupted restore/apply. Execute the actual operator template in isolation.

These are outstanding hardening items. Only warning comments/documentation were changed;
destructive refresh behavior is unchanged. The issue's checked refresh checkbox is not evidence that
these findings have been resolved.

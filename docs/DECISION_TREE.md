# Incident decision tree

## Application cannot connect

1. Capture the exact client error, timestamp, client host, server/instance, database, authentication type and connection string shape.
2. Test DNS, TCP port and TLS from the affected client—not only from the SQL Server.
3. Run `01_Connections_Authentication.sql` and correlate the error log.
4. Separate network (`timeout`, name resolution, firewall) from pre-login/TLS, authentication (18456 state), authorization, and database availability.
5. For AG listeners, test listener DNS records, resolved IPs, port, `MultiSubnetFailover`, replica endpoint health and cluster resources.

## Server is slow now

1. Run `00_First_Response.sql` before restarting, clearing cache or killing a session.
2. Decide whether the dominant constraint is blocking, CPU/runnable queue, memory grant/pressure, I/O latency, log throughput, tempdb, or an external dependency.
3. Use `02_Blocking_Deadlocks.sql`, `03_CPU_Plans_QueryStore.sql`, or `04_Memory_IO_Tempdb.sql`.
4. Compare a short interval with a known-good baseline. Lifetime counters are not interval evidence.
5. Remediate the causal query, transaction, plan, index/statistic, capacity, or application behavior; do not treat a wait type as a fix instruction.

## Query was fast and is now slow

1. Compare query text/hash, parameters, plan hash, runtime, waits, reads, rows and memory grant.
2. Check Query Store for plan regression and environment change: deployment, compatibility level, statistics, indexes, parameter distribution, CE, configuration and hardware.
3. Validate parameter sensitivity before using recompilation, hints or forcing.
4. Prefer a reversible Query Store hint/plan force only after testing and documenting an exit condition.

## Database/log/disk is full

1. Determine which file and volume is constrained and whether autogrowth is possible.
2. For log, inspect `log_reuse_wait_desc`, active transactions, AG/replication/CDC consumers and log-backup health.
3. Protect availability first by adding correctly sized capacity or fixing the blocking reuse condition.
4. Do not make shrink recurring maintenance. Shrink only after an exceptional, permanent data reduction and plan for index impact/regrowth.

## Suspected corruption

1. Preserve error logs, suspect-pages output, storage/OS evidence and affected backups.
2. Run CHECKDB without repair on a restored copy when possible.
3. Prefer restore/page restore from known-good backups and address the storage/hardware cause.
4. `REPAIR_ALLOW_DATA_LOSS` is a last-resort business decision, not a routine DBA command.

## AG behind or unhealthy

1. Use `AlwaysOn_AG_Health.sql` on every replica and compare clocks.
2. Separate send queue (primary/network/secondary hardening) from redo queue (secondary redo/read workload/I/O).
3. Check database suspension, endpoint connectivity, flow control, worker exhaustion, log generation and secondary storage.
4. Estimate RPO/RTO from validated rates and timestamps; DMV instantaneous rates can be zero or volatile.

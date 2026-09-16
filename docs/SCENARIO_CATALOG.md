# Senior DBA scenario catalog

The repository scripts provide evidence collection for these incident families. Environment-specific remediation remains a reviewed change, not an automatic script.

1. DNS resolves incorrectly or intermittently.
2. TCP port blocked, listener not bound, dynamic port changed.
3. TLS certificate trust, expiry, hostname or protocol mismatch.
4. Kerberos falls back to NTLM; SPN/delegation problem.
5. Login 18456, disabled login, default database unavailable, contained user mismatch.
6. Connection pool exhaustion, leaked connections, worker/thread pressure.
7. AG listener multi-subnet or read-only routing failure.
8. Root blocker with sleeping session/open transaction.
9. Lock escalation, conversion deadlock, key/page/object contention.
10. Deadlock from inconsistent access order, missing index, long transaction or isolation choice.
11. CPU saturation, runnable queue, parallelism skew, compilation storm.
12. Plan regression, parameter sensitivity, stale statistics, CE/compatibility change.
13. Query Store read-only/error state, excessive storage or capture settings.
14. Memory pressure, grants pending, workspace spill, stolen memory or external pressure.
15. Buffer-pool churn, lazy writes, low PLE interpreted per NUMA node and workload.
16. Data/log I/O latency, queueing, autogrowth stall or storage throttling.
17. Tempdb allocation contention, version store growth, spills or file imbalance.
18. Transaction log full: active transaction, LOG_BACKUP, AG, replication, CDC or availability replica.
19. Excessive VLFs, tiny growth, percentage growth or volume capacity risk.
20. Missing, late, corrupt or non-restorable backup chain.
21. Point-in-time restore planning, tail-log decision and STOPAT validation.
22. Restored database orphaned user/login SID mismatch.
23. Server objects missing after database restore: jobs, credentials, proxies, linked servers, endpoints.
24. TDE certificate/private-key missing during restore.
25. CHECKDB/suspect-pages errors, 823/824/825 or storage-path evidence.
26. AG send queue, redo queue, suspension, disconnected endpoint or unhealthy synchronization.
27. Unexpected AG failover, lease timeout, cluster quorum or replica transition evidence.
28. Replication latency, undistributed commands, agent failure or retention cleanup.
29. CDC capture/cleanup failure, LSN gap or metadata inconsistency.
30. Change Tracking retention and min-valid-version exposure.
31. SQL Agent job failure, long run, disabled schedule, bad owner or proxy.
32. Database Mail queue growth, SMTP failure, MSDB retention/size problem.
33. SSIS service account/gMSA rights, catalog execution, proxy and file/network access.
34. Database/user/server permission drift, role membership, ownership or impersonation.
35. SQL Audit/default trace/XE coverage gap during forensic investigation.
36. TDE/encryption state transition, expiring certificate or key governance issue.
37. Database/file/volume capacity forecast and abnormal growth.
38. Index fragmentation versus page count and workload; avoid threshold-only maintenance.
39. Missing-index DMV volatility, overlap, write cost and consolidation.
40. Statistics sampling, modification counter, skew and ascending-key problem.
41. Configuration drift: max memory, MAXDOP, cost threshold, unsafe surface area.
42. Patch/CU regression, build inventory, startup parameters and rollback readiness.
43. Master/model/msdb/tempdb startup or recovery failure.
44. Service account change, service SID, instant file initialization, SPNs and filesystem ACLs.
45. Linked server/OLE DB/ODBC provider, architecture, DSN, delegation and timeout.
46. Azure VM/storage/cache/accelerated networking or AWS EC2/EBS constraints.
47. RDS/Managed Instance feature restrictions and platform backup/HA boundaries.
48. Migration precheck: compatibility, collation, features, logins, jobs, keys, dependencies.
49. Cutover validation: control totals, smoke tests, latency, jobs, security and rollback criteria.
50. Evidence-preserving RCA: timeline, metrics, changes, symptoms, causal chain and actions.

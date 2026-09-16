# Open-source comparison and adoption guide

| Project | Best fit | Strengths | Important boundary | Toolkit decision |
|---|---|---|---|---|
| First Responder Kit | Incident and performance triage | Prioritized health, cache, waits, indexes, blocking/deadlocks, backups | Install/update as a versioned dependency; some procedures have platform limitations | Recommend; do not fork into this repo |
| Ola Hallengren Maintenance Solution | Production maintenance | Mature backup, CHECKDB, index/statistics, logging and jobs | Maintenance execution, not a complete incident diagnostic suite | Recommend as maintenance standard |
| dbatools | Migration and fleet automation | Broad PowerShell surface, object copy, tests and community support | Requires module/version governance and credentials strategy | Recommend for migrations and automation |
| Microsoft Tiger Toolbox | Deep diagnostics and support tools | Microsoft field-engineering provenance, specialized collectors | Tools vary in age, scope and support posture | Select per case after review |
| DarlingData | Performance/XE/Query Store | Pressure, plan cache, Query Store, blocked process and system-health analysis | Supported-version focus; deploy as external procedures | Recommend for advanced performance work |
| SQL Undercover | Monitoring and DBA utilities | Broad community toolbox and monitoring components | Evaluate each component and operational footprint | Optional after proof of concept |
| SQL Server Kit | Reference collection | Wide catalog of scripts, links, XE and diagnostic queries | Mixed provenance/age; not one uniform product | Research source, not blind deployment |

## Selection rule

1. Microsoft documentation defines supported behavior.
2. Prefer a mature upstream tool when it already solves the problem.
3. Pin a release or commit, record its license and checksum, and test in the target edition.
4. Keep local collectors small, read-only, explainable and version-aware.
5. Never combine outputs from different capture intervals as if they were one point-in-time snapshot.

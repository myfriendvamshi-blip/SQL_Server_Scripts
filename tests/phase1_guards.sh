#!/usr/bin/env bash
# CI ONLY: fixed disposable docker container, no external endpoint parameter.
set -euo pipefail
: "${SA_PASSWORD:?CI credential required}"
sql() {
  docker exec -w /tmp sql2022 /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -C -b "$@"
}
expect_error() {
  local error="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    echo "FAIL: expected SQL error $error but command succeeded"
    exit 1
  fi
  echo "$output"
  # A network/driver/parse failure must not masquerade as a tested safety gate.
  grep -Fq "Msg $error," <<< "$output"
}
expect_error 51500 sql -v DisposableLab=NO -i lab/07_Phase1_Evidence.sql
expect_error 51600 sql -v DisposableLab=NO -i lab/08_Phase1_PITR.sql
sql -Q "IF DB_ID(N'DBA_Toolkit_Phase1') IS NOT NULL OR DB_ID(N'DBA_Toolkit_PITR_Source') IS NOT NULL THROW 51700,'Opt-out created a database.',1;"

sql -Q "CREATE DATABASE DBA_Toolkit_Phase1;"
sql -d DBA_Toolkit_Phase1 -Q "CREATE TABLE dbo.PreserveMe(id int); INSERT dbo.PreserveMe VALUES(42);"
expect_error 51501 sql -v DisposableLab=YES -i lab/07_Phase1_Evidence.sql
sql -Q "IF (SELECT COUNT(*) FROM DBA_Toolkit_Phase1.dbo.PreserveMe WHERE id=42)<>1 THROW 51701,'Collision changed existing fixture.',1; DROP DATABASE DBA_Toolkit_Phase1;"

sql -Q "CREATE DATABASE DBA_Toolkit_PITR_Source;"
expect_error 51601 sql -v DisposableLab=YES -i lab/08_Phase1_PITR.sql
sql -Q "IF DB_ID(N'DBA_Toolkit_PITR_Source') IS NULL THROW 51702,'Collision removed source.',1; DROP DATABASE DBA_Toolkit_PITR_Source;"

# The existing initial lab database is disposable and only used for this permission test.
sql -Q "CREATE LOGIN DBA_Toolkit_Limited WITH PASSWORD='Fixture_Only!Limited2026',CHECK_POLICY=OFF;"
sql -d DBA_Toolkit_Lab -Q "CREATE USER DBA_Toolkit_Limited FOR LOGIN DBA_Toolkit_Limited;"
for pair in '01_Access.sql 51400' '03_Restore_Dependencies.sql 51410' '04_Integrity_Evidence.sql 51420' '05_Security_Evidence.sql 51430'; do
  read -r file error <<< "$pair"
  expect_error "$error" docker exec -w /tmp sql2022 /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U DBA_Toolkit_Limited -P 'Fixture_Only!Limited2026' -C -b \
    -d DBA_Toolkit_Lab -i "scripts/scenarios/$file"
done
sql -d DBA_Toolkit_Lab -Q "DROP USER DBA_Toolkit_Limited;"
sql -Q "DROP LOGIN DBA_Toolkit_Limited;"
echo 'PASS: opt-out, fixture collision and restricted metadata gates'

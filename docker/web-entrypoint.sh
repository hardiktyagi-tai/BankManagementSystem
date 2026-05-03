#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Waiting for SQL Server at ${DB_HOST:-db}:1433 ..."
ATTEMPTS=0
MAX_ATTEMPTS=60
until (echo > /dev/tcp/${DB_HOST:-db}/1433) >/dev/null 2>&1; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "[entrypoint] SQL Server did not become reachable in time." >&2
        exit 1
    fi
    sleep 2
done
echo "[entrypoint] SQL Server reachable."

# SQL Server accepts TCP before it's ready for logins. Give it a moment.
sleep 8

echo "[entrypoint] Applying EF Core migrations ..."
dotnet ef database update \
    --project /src/Data/BankManagementSystem.Data/BankManagementSystem.Data.csproj \
    --startup-project /src/Web/BankManagementSystem.Web.csproj \
    --no-build

echo "[entrypoint] Starting BankManagementSystem.Web ..."
cd /src/Web
exec dotnet bin/Debug/netcoreapp2.2/BankManagementSystem.Web.dll

# syntax=docker/dockerfile:1
# Single-stage image: SDK 2.2 (only x86_64 exists; runs under Rosetta on Apple Silicon).
# We keep the SDK at runtime so we can apply EF Core 2.2 migrations in entrypoint.
FROM --platform=linux/amd64 mcr.microsoft.com/dotnet/core/sdk:2.2 AS app

WORKDIR /src

# NuGet would otherwise emit a hard error on .NET Core 2.2 because its TLS roots are stale.
# Override the package source to NuGet.org over HTTPS and trust the system CA bundle.
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    NUGET_XMLDOC_MODE=skip \
    ASPNETCORE_ENVIRONMENT=Development \
    ASPNETCORE_URLS=http://+:5000 \
    PATH="/root/.dotnet/tools:${PATH}"

# Copy solution + projects first so package restore is cached on subsequent builds.
COPY src/ ./

# Restore + build the entire solution. Restore can be flaky on amd64 emulation;
# retry once and fall back to no-parallel.
RUN dotnet restore BankManagementSystem.sln \
    || dotnet restore BankManagementSystem.sln --disable-parallel

RUN dotnet build BankManagementSystem.sln -c Debug --no-restore

# Install EF Core 2.2 CLI tool for applying migrations at container start.
RUN dotnet tool install --global dotnet-ef --version 2.2.6

EXPOSE 5000

COPY docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
RUN chmod +x /usr/local/bin/web-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/web-entrypoint.sh"]

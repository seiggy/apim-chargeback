---
name: nuget-manager
description: Safe NuGet package management workflow for Mosaic Money .NET services. Use when adding, removing, or updating package references in .NET projects, including Aspire CLI special handling for Aspire integrations.
---

# NuGet Manager

Use this skill for all package dependency changes in .NET projects.

## Decision tree
1. If the request is for an Aspire integration (for example `postgres`, `redis`, `kafka`), use `aspire add` first.
2. If the request is to update Aspire packages or templates across an Aspire app, use `aspire update`.
3. If the request is a normal non-Aspire package change, use `dotnet add package` or `dotnet remove package`.
4. Use direct file edits only for version changes when command-based workflows are not appropriate.

## Rules
- Use `dotnet add package` and `dotnet remove package` for add/remove operations.
- Direct file edits are only for version updates when required.
- After updates, run `dotnet restore` and resolve dependency issues immediately.

## Aspire-first package policy
- Prefer Aspire integration packages before provider-only alternatives.
- Validate package changes against `docs/agent-context/aspire-dotnet-integration-policy.md`.
- Do not bypass service defaults and reference-based configuration.

## Aspire special situations

### 1. Adding Aspire integrations
- Prefer `aspire add <integration>` for Aspire-related additions.
- `aspire add` targets the Aspire AppHost project and resolves integration packages through the CLI workflow.
- Use `--project` when multiple AppHost projects exist.
- Use `--version` to pin integration version when required.
- Use `--source` only when a non-default NuGet source is explicitly required.

Example commands:
- `aspire add postgres`
- `aspire add kafka --version 13.1.0 --project ./src/AppHost/AppHost.csproj`

### 2. Updating Aspire dependencies
- Prefer `aspire update` for Aspire package/template updates in Aspire-managed solutions.
- Use `aspire update --project <apphost.csproj>` to avoid selecting the wrong AppHost in multi-AppHost repos.
- Use `aspire update --self` to update the Aspire CLI.
- Use `--channel stable|staging|daily` only when channel selection is explicitly requested.

Example commands:
- `aspire update`
- `aspire update --project ./src/AppHost/AppHost.csproj`
- `aspire update --self --channel stable`

### 3. AppHost package vs service client package split
- After `aspire add`, verify whether service projects also need Aspire client packages.
- If a service package is still required, add it with `dotnet add package` in the service project.
- Keep AppHost (`Aspire.Hosting.*`) and service (`Aspire.*`) responsibilities separated.

### 4. Provider-only exception path
- If Aspire integration packages do not support the required capability, provider-only packages may be used.
- In that case, document the exception reason and keep Aspire orchestration wiring intact.

## Update workflow
1. Verify target version exists.
2. Identify where version is managed (`.csproj` or central props).
3. Apply update.
4. Run restore and capture result.

## Source grounding
- `https://aspire.dev/reference/cli/commands/aspire-add/`
- `https://aspire.dev/reference/cli/commands/aspire-update/`

# BeTerna-AccountAcquisition

Dynamics 365 CE / Power Platform project. Read this before changing anything.

## Project facts
- Environment (dev): https://org888c7c34.crm17.dynamics.com
- Solution (unique name): BeTernaAccountAcquisition
- Publisher prefix: `lrw` — every custom table, column, choice, web resource and environment variable uses it (e.g. `lrw_invoicestatus`).
- Every component belongs in solution `BeTernaAccountAcquisition`. Never create components outside a solution.

## Repo layout
| Folder | Contents |
|---|---|
| `WebResources/<TableSchemaName>/` | One folder per table, named by **schema name** (`Account`, `lrw_NewEntity`): `FormCustomization.js`, `Ribbon.js`, … |
| `WebResources/Shared/` | Cross-table scripts, incl. `constants.js`. |
| `Plugins/` | C# plugin libraries (`pac plugin init`), target `net462`, signed. |
| `Solutions/BeTernaAccountAcquisition/` | Full unpacked solution (`Both`), cumulative: everything committed so far. Refreshed by `Export-Solution.ps1`. |
| `deployment/` | `map.xml`, `scripts/Pack-Solution.ps1`, `settings/deploymentSettings.<env>.json`, `data/` (config rows). |
| `azure/` | (only with `-Azure`) `infra/` Bicep + `main.<env>.bicepparam`, `scripts/Deploy-Azure.ps1`, function/web app projects (`azure/<Name>.Functions/`). Not built or deployed by the pipeline. |
| `apps/<name>/` | Power Pages code sites, code apps, native mobile apps — one self-contained folder each (own `package.json`, lint, build). Create with the matching plugin skill when needed. |
| `http/` | REST Client requests against the Dataverse Web API. |

`WebResources/` is the source you edit. Don't hand-edit web resource copies inside `Solutions/`.

## Standards (all workloads)
- Flows and apps use **connection references**, never direct connections.
- Sensitive or environment-specific values go in **environment variables**, never hard-coded. No secrets in the repo.
- Refer to Dataverse columns by **schema/logical name** in code, expressions and queries — never display names.
- Canvas apps: tablet layout 1920×1080 unless told otherwise.
- Schema changes (tables, columns, choices, relationships) need explicit approval — propose them, don't just make them.

## Schema constants
- Web resources: all table/column/entity-set names and choice values come from `WebResources/Shared/constants.js` (`LrwSchema`). Add new ones there; never write literal schema names in form logic.
- `constants.js` is a separate web resource; add it as a dependency of each script that uses it, and declare `/* global LrwSchema */` at the top of that script.
- Plugins: a `Constants/` folder in the plugin project, one static class per table named by **schema name** (`Constants/Account.cs`, `Constants/lrw_NewEntity.cs`), plus cross-table classes (`CustomApis.cs`, `ConfigKeys.cs`). Each table class holds `LogicalName`, `EntitySetName`, a nested `Fields` class and choice `enum`s. No early-bound generation.
  ```csharp
  public static class Account
  {
      public const string LogicalName = "account";
      public const string EntitySetName = "accounts";
      public static class Fields { public const string Name = "name"; public const string StateCode = "statecode"; }
      public enum StateCode { Active = 0, Inactive = 1 }
  }
  ```
- Apps under `apps/` keep their own constants module in their own source tree.
- .NET projects under `azure/` (web apps, functions) keep a `Constants/` folder like the plugins: one class per table by schema name, plus `ConfigKeys.cs` for configuration keys read outside options classes and a class for API routes. Don't reuse a Dataverse constant for a non-Dataverse value (e.g. an APIM operation path).

## Web resources
- Web resource name in Dataverse = `lrw_/` + path under `WebResources/`, exactly (e.g. `lrw_/Account/Ribbon.js`). Pack-Solution relies on this to find the source.
- Namespace per file: `Lrw.<Table>.Form`, `Lrw.<Table>.Ribbon` — form and ribbon scripts can load on the same page, so never assign `Lrw.<Table>` wholesale (`Lrw.Account = Lrw.Account || {}` first).
- Type-checked against `@types/xrm` (`jsconfig.json`); keep it error-free. Run `npm run lint` before committing.
- Root `npm run lint` covers `WebResources/` only; apps under `apps/` use their own lint setup.
- Always take `executionContext` and call `getFormContext()`; don't use the deprecated `Xrm.Page`.

## Plugins
- Build: `dotnet build`. Update: `pac plugin push --pluginId <assemblyId> --type Assembly`.
- First registration and step registration happen in the Plugin Registration Tool (`pac tool prt`), not the CLI.
- Keep plugins short and stateless; offload long-running work (Azure Function, async step).

## ALM / deployment
- Refresh from dev with `deployment/scripts/Export-Solution.ps1 -SolutionName BeTernaAccountAcquisition`: exports unmanaged + managed via the active `pac auth` profile, unpacks with `--packagetype Both` (incl. deletions), then bumps the solution version in dev (`-NoVersionBump` to skip).
- Selection happens at commit time: after an export, commit only the diffs that belong in the release (new tables, columns, views, steps…) and leave the rest uncommitted. Check that every committed component's dependencies are committed too.
- Never commit connection strings or credential files; authenticate with `pac auth` profiles.
- Commit messages: no `Co-Authored-By: Claude …` trailer (or any other AI co-author line).
- Pack with `deployment/scripts/Pack-Solution.ps1 -SolutionName BeTernaAccountAcquisition` → `out/BeTernaAccountAcquisition.zip` + `out/BeTernaAccountAcquisition_managed.zip` (default `-PackageType Both`; Managed/Both refuse a folder not unpacked with `Both`). It swaps every web resource and plugin DLL in the solution for its repo source automatically (warns when a source is missing) — never hand-copy them into `Solutions/`. `deployment/map.xml` is for exceptions only; its `to` paths are relative to the unpacked solution folder.
- Import modes:
  - **update** — components not in the package stay in the target; anything deleted in dev must be removed in the target separately.
  - **upgrade** — everything in the target that is not in the package is **deleted**. The package is the full committed solution, so this removes components deleted in dev — but also anything that exists in the target and was never committed. Only with explicit approval.
- Environment-specific values live in `deployment/settings/deploymentSettings.<env>.json` (regenerate the skeleton with `pac solution create-settings` when env variables or connection references change). Secrets: secret-type env variables pointing at Key Vault, never plaintext.
- Configuration-table rows do not travel with the solution: export/import them via `deployment/data/` (`pac data`) and list them in the release notes.
- CI/CD: `deployment/azure-pipelines.yml` if it exists (created only with `-Pipeline AzureDevOps`); otherwise releases are imported manually with `deployment/scripts/Import-Solution.ps1`. Release mode (pipeline only): **Deploy** (Deploy = we import into Test → Prod with environment approvals; Deliver = we upload packages to the client's storage and the client imports). Setup checklist in README. Don't change pipeline variable groups, environments or approvals without asking.

## Azure (Functions, web apps…)
- Lives in `azure/` in this repo but is **outside** the Dataverse pipeline; deploy it with `azure/scripts/Deploy-Azure.ps1` (manually or from a separate pipeline). Resources go into the **client's** subscription.
- Infrastructure as code only: `azure/infra/main.bicep` + `main.<env>.bicepparam`. No secrets in bicepparam files; `local.settings.json` is never committed.
- Deploy Azure **before** importing a solution that depends on it.
- Connection points with the solution: endpoint URLs as solution environment variables (values in `deploymentSettings.<env>.json`); secrets in Key Vault via secret-type env variables; Dataverse → Azure via webhook / Service Bus service endpoints (solution components) or plugins/flows reading the env variable; Azure → Dataverse via the function's managed identity added as an application user. Prefer managed identity / Entra auth over function keys.
- Integration rules: define the contract, idempotency, retries and failure handling; log with correlation IDs, never secrets or personal data.

## Power Pages / code apps / mobile app
- Use the matching Claude Code plugin skills (`power-pages:*`, `code-apps-preview:*`, `mobile-app:*`) for scaffolding, data sources and deployment.
- Power Pages: grant data access through table permissions and web roles; expose only the Web API columns that are needed (no `*`).

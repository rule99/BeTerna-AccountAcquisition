# BeTerna-AccountAcquisition

Starter workspace for Dataverse web resources, plugins, and solution development.

## Layout

```
.vscode/            Recommended extensions + workspace settings
WebResources/       Form/ribbon JavaScript web resources (client-side)
  Shared/constants.js   Shared schema names (web resource <prefix>_/Shared/constants.js)
  Account/              One folder per table, named by table SCHEMA name (Account, acme_NewEntity)
    FormCustomization.js  -> web resource <prefix>_/Account/FormCustomization.js
apps/               Power Pages / code apps / mobile apps, one folder each (create when needed)
Plugins/            Server-side C# plugin class libraries (pac plugin init)
Solutions/          Unpacked Dataverse solution XML (pac solution clone)
http/               REST Client files for the Dataverse Web API
  dataverse.http      WhoAmI + CRUD samples
eslint.config.js    ESLint flat config (knows the Xrm global)
.editorconfig       Consistent formatting (2-space JS/XML, 4-space C#)
package.json        ESLint + Prettier dev dependencies
```

## Getting started

1. **Install the Power Platform CLI** (if not already):
   ```powershell
   pac install latest      # or: dotnet tool install --global Microsoft.PowerApps.CLI.Tool
   ```
2. **Authenticate to your environment:**
   ```powershell
   pac auth create --environment https://org888c7c34.crm17.dynamics.com
   pac org who
   ```
3. **Test the Web API:** run `az login` once, then `.\http\Get-DataverseToken.ps1`. It creates the git-ignored `http/.env` (set `DATAVERSE_URL` there if the scaffolder didn't) and writes a fresh token. Open `http/dataverse.http` and click *Send Request* over the WhoAmI block. Tokens last ~1 hour; re-run the script on a 401.
4. **Lint web resources:**
   ```powershell
   npm run lint        # check
   npm run lint:fix    # auto-fix
   ```

## Deployment

1. `pac auth create --environment <dev url>` (once).
2. Export: `.\deployment\scripts\Export-Solution.ps1 -SolutionName <SolutionName>` exports unmanaged + managed from dev, unpacks into `Solutions/<SolutionName>/` (`Both`, incl. deletions) and bumps the version in dev.
3. Commit only the changes that belong in the release (`git status` / `git add -p`). The folder is cumulative: everything committed so far.
4. Pack: `.\deployment\scripts\Pack-Solution.ps1 -SolutionName <SolutionName>` → `out/<SolutionName>.zip` + `out/<SolutionName>_managed.zip`. It builds plugins, then swaps every web resource and plugin DLL in the solution for its repo source (by path / by name) and warns about any file with no source. `deployment/map.xml` is only for exceptions.
- Per-environment env variables / connection references: `deployment/settings/deploymentSettings.<env>.json`.
- Config-table data: `deployment/data/` (`pac data export` / `pac data import`).
- Import as **update** to keep target components that aren't in the package; **upgrade** deletes them (incl. anything in the target that was never committed) — explicit approval only.

## Azure DevOps setup (`deployment/azure-pipelines.yml`)

Release mode is set per client when scaffolding (`-ReleaseMode Deploy|Deliver`, variable `releaseMode` in the YAML):
**Deploy** imports the managed package into Test, then Prod; **Deliver** uploads both packages to the client's storage and the client imports.

1. **Agent pool**: self-hosted Windows agent with .NET SDK, .NET Framework 4.6.2 targeting pack, Node.js, Git (+ Azure CLI for Deliver). Set `agentPool` in the YAML. pac is installed by the pipeline from nuget.org.
2. **Pipeline**: New pipeline → Azure Repos Git → *Existing Azure Pipelines YAML file* → `/deployment/azure-pipelines.yml`.
3. **Deploy**, for each target in `deployTargets` (default `test`, `prod`):
   - App registration + application user in that environment with the security role it needs.
   - Variable group `vg-<Solution>-<target>`: `EnvironmentUrl`, `TenantId`, `ClientId`, `ClientSecret` (secret; ideally linked to Key Vault).
   - Environment `<Solution>-<target>` with *Approvals and checks* → Approvals. **Create it before the first run** — otherwise it is auto-created without approvals.
   - `deployment/settings/deploymentSettings.<target>.json` filled in (`pac solution create-settings`).
4. **Deliver**: variable group `vg-<Solution>-deliver`: `DeliverStorageAccount`, `DeliverContainer`, `DeliverStorageKey` (secret); environment `<Solution>-deliver` (approval optional).
5. **Solution Checker** (stage `Check`, on by default in Deploy, off in Deliver — variable `solutionChecker`): uses variable group `checkerVariableGroup` (default `vg-<Solution>-test`). Fails on High+ findings; results are published as artifact `checker-results`. Locally: `.\deployment\scripts\Test-Solution.ps1 -Path out\<Solution>_managed.zip -EnvironmentUrl <url>`.
6. **Run**: pick `importMode` — `update` (default) or `upgrade` (deletes target components missing from the package).

Configuration data: CMT zips in `deployment/data/` are imported after the solution, in name order (`pac data import`).
Preview an import locally: `.\deployment\scripts\Import-Solution.ps1 -ZipPath out\<Solution>_managed.zip -EnvironmentUrl <url> -SettingsFile deployment\settings\deploymentSettings.test.json -DataFolder deployment\data -DryRun`.

## Azure components (`-Azure`)

`azure/` holds Azure Functions / web apps and their infrastructure. It is **not** part of the Dataverse pipeline; deploy it manually (or from a separate pipeline), into the client's subscription, **before** importing a solution that depends on it.

1. Function project: `func init azure\<Name>.Functions --worker-runtime dotnet-isolated --target-framework net8.0`, then `cd azure\<Name>.Functions; func new --template "HTTP trigger" --name Ping`; run locally with `func start`.
2. Fill in `azure/infra/main.test.bicepparam` / `main.prod.bicepparam` (`dataverseUrl`). The example `main.bicep` creates a Flex Consumption Function App with identity-based storage and Application Insights; extend it for other resources.
3. `az login`, then preview: `.\azure\scripts\Deploy-Azure.ps1 -Environment test -ResourceGroup <rg> -Subscription <id> -WhatIf`
4. Deploy infra + code: `.\azure\scripts\Deploy-Azure.ps1 -Environment test -ResourceGroup <rg> -FunctionProject azure\<Name>.Functions`
   (needs Contributor + role-assignment rights — Owner or User Access Administrator — on the resource group).
5. Wire it to Dataverse: function URL into the solution's environment variable (`deploymentSettings.<env>.json`); the managed identity's Application ID as an application user with the right security role.

## Common pac commands

| Task | Command |
|---|---|
| Clone a solution to source | `pac solution clone --name MySolution` |
| Unpack solution zip | `pac solution unpack --zipfile my.zip --folder src` |
| Pack solution | `pac solution pack --folder src --zipfile out.zip` |
| Scaffold a plugin project | `pac plugin init` |
| Push a plugin | `pac plugin push` |
| Scaffold a PCF control | `pac pcf init` |

## Plugin development & deployment workflow

Prerequisites (already installed on this machine): **.NET SDK 8**, **.NET Framework 4.6.2 Developer Pack**, **pac CLI**.

### 1. Create the plugin class library
```powershell
cd Plugins
pac plugin init --outputDirectory .\MyOrg.Plugins
```
This generates an SDK-style project targeting `net462`, a strong-name key (`.snk`),
and a reference to `Microsoft.CrmSdk.CoreAssemblies`.

### 2. Write your plugin
Implement `IPlugin.Execute` in a class, e.g. `PreOperationAccountCreate.cs`:
```csharp
public sealed class PreOperationAccountCreate : IPlugin
{
    public void Execute(IServiceProvider serviceProvider)
    {
        var context = (IPluginExecutionContext)serviceProvider
            .GetService(typeof(IPluginExecutionContext));
        // ... business logic ...
    }
}
```

### 3. Build
```powershell
dotnet build                 # output: bin\Debug\net462\MyOrg.Plugins.dll
```

### 4. Authenticate (once per environment)
```powershell
pac auth create --environment https://org888c7c34.crm17.dynamics.com
pac auth list                # see/select active profile
pac auth select --index 1
```

### 5. Push the assembly to Dataverse
First time only: register the assembly and its steps in step 6, then copy the
assembly's ID from the Plugin Registration Tool. After that, every code change is:
```powershell
dotnet build
pac plugin push --pluginId <assemblyId> --type Assembly
```
`pac plugin push` only **updates** an already-registered assembly. It does not
register new assemblies or create steps.

### 6. Register steps (which message/entity/stage triggers the plugin)
Step registration is done with a GUI tool, not the CLI:

- **Plugin Registration Tool (PRT):** `pac tool prt` (downloads & launches it), **or**
- **XrmToolBox** → *Plugin Registration* plugin.

In the tool:
1. **Create Connection** to your environment.
2. **Register New Assembly** → browse to `bin\Debug\net462\MyOrg.Plugins.dll`
   (or *Register from solution* if already pushed).
3. Right-click the plugin type → **Register New Step**:
   - **Message** (e.g. `Create`, `Update`), **Primary Entity** (e.g. `account`),
   - **Event Pipeline Stage** (`PreValidation` / `PreOperation` / `PostOperation`),
   - **Execution Mode** (`Synchronous` / `Asynchronous`), and filtering attributes.
4. (Optional) Register **images** (PreImage/PostImage) if your logic needs the
   before/after record snapshot.

### 7. Iterate
After code changes: `dotnet build` → `pac plugin push`. The registered steps stay
intact; only the assembly is updated. Use **Plugin Trace Log** (Settings ▸ Auditing,
or `tracingService.Trace(...)`) to debug.

## Azure integration

This workspace includes the **Azure Tools** extensions (Functions, App Service,
Storage, Resource Groups, Container Apps, Cosmos DB), **Bicep**, and **Azure CLI**.
Common Dynamics ↔ Azure patterns:

| Pattern | Azure piece | How it connects to Dataverse |
|---|---|---|
| Offload heavy/async logic from a plugin | **Azure Function** | Plugin (or a **Webhook** step) posts to the Function endpoint |
| Event-driven integration | **Service Bus** / **Event Grid** | Register a *Service Endpoint* step in PRT; Dataverse pushes messages |
| Scheduled / external jobs calling Dataverse | **Azure Function (timer)** | Calls the Web API with a Managed Identity / app registration |
| Infrastructure as code | **Bicep** | Provision Function App, Service Bus, Key Vault |

```powershell
az login                     # sign in to Azure
func init MyOrg.Functions --dotnet     # scaffold a Functions project (Azure Functions Core Tools)
```
Register a **Webhook** or **Service Endpoint** step in the Plugin Registration Tool
to have Dataverse call your Azure Function or Service Bus queue.
